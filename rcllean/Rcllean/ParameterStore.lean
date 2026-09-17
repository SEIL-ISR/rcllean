import Std.Data.HashMap
import Rcllean.Node
import Rcllean.Parameter

/-!
# Parameter storage on a node

A node's parameters must be declared before use.  Declaring one gives it a
type, a default and any constraints; setting it afterwards is checked against
those and against any callback the node registered.

A command-line override wins over the declared default, so
`--ros-args -p rate:=10.0` works without the program knowing about it.
-/

namespace Rcllean

/-- The result of trying to set parameters, mirroring
`rcl_interfaces/msg/SetParametersResult`. -/
structure SetResult where
  successful : Bool
  reason : String := ""
deriving Repr, Inhabited

namespace SetResult
def ok : SetResult := { successful := true }
def refuse (reason : String) : SetResult := { successful := false, reason }
end SetResult

/-- A node's parameters. -/
structure ParameterStore where
  /-- Declared parameters, by name. -/
  params : IO.Ref (Std.HashMap String Parameter)
  /-- Declaration order, so listings are stable rather than hash order. -/
  order : IO.Ref (Array String)
  /-- Overrides from the command line that apply to this node. -/
  overrides : Std.HashMap String ParameterValue
  /-- Callbacks consulted before a set takes effect; any one may refuse. -/
  onSet : IO.Ref (Array (Array Parameter → IO SetResult))
  /-- Whether reading or setting an undeclared parameter is allowed.  Off by
  default. -/
  allowUndeclared : Bool

namespace ParameterStore

/-- Collect the overrides that apply to a node.  rcl reports them per node
name and a block may be a wildcard; more specific blocks win, so wildcards are
applied first. -/
def collectOverrides (ctx : Context) (nodeFqn : String) :
    IO (Std.HashMap String ParameterValue) := do
  let mut wildcards : Array (String × ParameterValue) := #[]
  let mut exact : Array (String × ParameterValue) := #[]
  let nodeCount ← FFI.paramOverrideNodeCount ctx.handle
  for i in [0:nodeCount.toNat] do
    let idx := UInt32.ofNat i
    let name ← FFI.paramOverrideNodeName ctx.handle idx
    let isWildcard := name == "/**" || name == "/*" || name == "**"
    let applies := isWildcard || name == nodeFqn ||
      -- rcl reports names with or without the leading slash, depending on
      -- how they were written on the command line.
      ("/" ++ name) == nodeFqn || name == nodeFqn.drop 1
    if !applies then
      continue
    let count ← FFI.paramOverrideCount ctx.handle idx
    for j in [0:count.toNat] do
      let jdx := UInt32.ofNat j
      let pname ← FFI.paramOverrideName ctx.handle idx jdx
      let value := ParameterValue.ofWire (← FFI.paramOverrideValue ctx.handle idx jdx)
      if isWildcard then wildcards := wildcards.push (pname, value)
      else exact := exact.push (pname, value)

  let mut out : Std.HashMap String ParameterValue := {}
  for (k, v) in wildcards do out := out.insert k v
  for (k, v) in exact do out := out.insert k v
  return out

def create (ctx : Context) (nodeFqn : String) (allowUndeclared : Bool := false) :
    IO ParameterStore := do
  return { params := ← IO.mkRef {}
           order := ← IO.mkRef #[]
           overrides := ← collectOverrides ctx nodeFqn
           onSet := ← IO.mkRef #[]
           allowUndeclared := allowUndeclared }

/-- Whether a parameter has been declared. -/
def has (store : ParameterStore) (name : String) : IO Bool :=
  return (← store.params.get).contains name

/-- Declare a parameter.  The value is the command-line override if there is
one, otherwise the default.  Redeclaring is an error: it would discard the
first declaration's constraints. -/
def declare (store : ParameterStore) (name : String)
    (defaultValue : ParameterValue := .notSet)
    (descriptor : ParameterDescriptor := {}) : IO ParameterValue := do
  if ← store.has name then
    throw (IO.userError s!"parameter '{name}' is already declared")
  -- With no type in the descriptor, take it from the default value.
  let declaredType :=
    if descriptor.type == .notSet then defaultValue.type else descriptor.type
  let descriptor := { descriptor with name := name, type := declaredType }
  let value := store.overrides[name]?.getD defaultValue
  match descriptor.check value with
  | .error e => throw (IO.userError s!"declaring '{name}': {e}")
  | .ok _ => pure ()
  store.params.modify (·.insert name { name, value, descriptor })
  store.order.modify (·.push name)
  return value

/-- Undeclare a parameter.  A read-only one cannot be undeclared. -/
def undeclare (store : ParameterStore) (name : String) : IO Unit := do
  match (← store.params.get)[name]? with
  | none => throw (IO.userError s!"parameter '{name}' is not declared")
  | some p =>
    if p.descriptor.readOnly then
      throw (IO.userError s!"parameter '{name}' is read-only")
    store.params.modify (·.erase name)
    store.order.modify (·.filter (· != name))

/-- The value of a parameter, or `notSet` if it is not declared and undeclared
parameters are allowed. -/
def get (store : ParameterStore) (name : String) : IO ParameterValue := do
  match (← store.params.get)[name]? with
  | some p => return p.value
  | none =>
    if store.allowUndeclared then return .notSet
    throw (IO.userError s!"parameter '{name}' is not declared")

/-- The full record of a parameter, descriptor included. -/
def getParameter? (store : ParameterStore) (name : String) : IO (Option Parameter) :=
  return (← store.params.get)[name]?

/-- Every declared parameter, in declaration order. -/
def all (store : ParameterStore) : IO (Array Parameter) := do
  let params ← store.params.get
  return (← store.order.get).filterMap (params[·]?)

/-- Register a callback consulted before any set takes effect.  An
unsuccessful result refuses the change and nothing is written. -/
def addOnSetCallback (store : ParameterStore)
    (cb : Array Parameter → IO SetResult) : IO Unit :=
  store.onSet.modify (·.push cb)

/-- Set several parameters at once, all or nothing.  Types, ranges, read-only
and every registered callback are checked first, so a rejected batch leaves the
node unchanged. -/
def setAtomically (store : ParameterStore) (updates : Array (String × ParameterValue)) :
    IO SetResult := do
  let current ← store.params.get
  let mut proposed : Array Parameter := #[]

  for (name, value) in updates do
    match current[name]? with
    | none =>
      if !store.allowUndeclared then
        return .refuse s!"parameter '{name}' is not declared"
      proposed := proposed.push { name, value }
    | some p =>
      if p.descriptor.readOnly then
        return .refuse s!"parameter '{name}' is read-only"
      match p.descriptor.check value with
      | .error e => return .refuse e
      | .ok _ => proposed := proposed.push { p with value := value }

  for cb in ← store.onSet.get do
    let result ← cb proposed
    if !result.successful then
      return result

  for p in proposed do
    if !(← store.has p.name) then
      store.order.modify (·.push p.name)
    store.params.modify (·.insert p.name p)
  return .ok

/-- Set one parameter. -/
def set (store : ParameterStore) (name : String) (value : ParameterValue) :
    IO SetResult :=
  store.setAtomically #[(name, value)]

end ParameterStore

end Rcllean
