import RclInterfaces.Msg.ParameterValue
import RclInterfaces.Msg.ParameterDescriptor

/-!
# Parameter values

ROS 2 parameters hold one of the nine types in
`rcl_interfaces/msg/ParameterType`.  A `ParameterValue` is that choice as a
Lean inductive, so the type is not a tag checked at run time.
-/

namespace Rcllean

/-- A parameter's value.  The constructors are in the order
`rcl_interfaces/msg/ParameterType` numbers them. -/
inductive ParameterValue where
  /-- Declared but not set, which is how an undeclared parameter reads. -/
  | notSet
  | bool (v : Bool)
  | integer (v : Int64)
  | double (v : Float)
  | string (v : String)
  | byteArray (v : ByteArray)
  | boolArray (v : Array Bool)
  | integerArray (v : Array Int64)
  | doubleArray (v : Array Float)
  | stringArray (v : Array String)
deriving Inhabited

/-- The nine parameter types, plus "not set". -/
inductive ParameterType where
  | notSet | bool | integer | double | string
  | byteArray | boolArray | integerArray | doubleArray | stringArray
deriving DecidableEq, Repr, Inhabited, BEq

namespace ParameterType

/-- The code `rcl_interfaces/msg/ParameterType` uses. -/
def toUInt8 : ParameterType → UInt8
  | .notSet => 0 | .bool => 1 | .integer => 2 | .double => 3 | .string => 4
  | .byteArray => 5 | .boolArray => 6 | .integerArray => 7
  | .doubleArray => 8 | .stringArray => 9

def ofUInt8? : UInt8 → Option ParameterType
  | 0 => some .notSet | 1 => some .bool | 2 => some .integer
  | 3 => some .double | 4 => some .string | 5 => some .byteArray
  | 6 => some .boolArray | 7 => some .integerArray | 8 => some .doubleArray
  | 9 => some .stringArray | _ => none

@[simp] theorem ofUInt8?_toUInt8 (t : ParameterType) :
    ofUInt8? t.toUInt8 = some t := by cases t <;> rfl

def toString : ParameterType → String
  | .notSet => "not set" | .bool => "bool" | .integer => "integer"
  | .double => "double" | .string => "string" | .byteArray => "byte array"
  | .boolArray => "bool array" | .integerArray => "integer array"
  | .doubleArray => "double array" | .stringArray => "string array"

instance : ToString ParameterType := ⟨toString⟩

end ParameterType

namespace ParameterValue

/-- The type of a value. -/
def type : ParameterValue → ParameterType
  | .notSet => .notSet
  | .bool _ => .bool
  | .integer _ => .integer
  | .double _ => .double
  | .string _ => .string
  | .byteArray _ => .byteArray
  | .boolArray _ => .boolArray
  | .integerArray _ => .integerArray
  | .doubleArray _ => .doubleArray
  | .stringArray _ => .stringArray

/-- Whether a value can be stored in a parameter of a given type.  `notSet` is
accepted everywhere: it is how an unset parameter reads and how one is
cleared. -/
def matchesType (v : ParameterValue) (t : ParameterType) : Bool :=
  v.type == t || v.type == .notSet || t == .notSet

def asBool? : ParameterValue → Option Bool
  | .bool v => some v | _ => none
def asInt? : ParameterValue → Option Int64
  | .integer v => some v | _ => none
def asFloat? : ParameterValue → Option Float
  | .double v => some v
  -- A YAML integer literal is accepted, so `1` works where `1.0` is meant.
  | .integer v => some v.toFloat
  | _ => none
def asString? : ParameterValue → Option String
  | .string v => some v | _ => none
def asBoolArray? : ParameterValue → Option (Array Bool)
  | .boolArray v => some v | _ => none
def asIntArray? : ParameterValue → Option (Array Int64)
  | .integerArray v => some v | _ => none
def asFloatArray? : ParameterValue → Option (Array Float)
  | .doubleArray v => some v | _ => none
def asStringArray? : ParameterValue → Option (Array String)
  | .stringArray v => some v | _ => none
def asByteArray? : ParameterValue → Option ByteArray
  | .byteArray v => some v | _ => none

/-- Convert to the wire representation. -/
def toWire (v : ParameterValue) : RclInterfaces.Msg.ParameterValue :=
  let base : RclInterfaces.Msg.ParameterValue := { type := v.type.toUInt8 }
  match v with
  | .notSet => base
  | .bool b => { base with bool_value := b }
  | .integer i => { base with integer_value := i }
  | .double d => { base with double_value := d }
  | .string s => { base with string_value := s }
  | .byteArray b => { base with byte_array_value := b }
  | .boolArray a => { base with bool_array_value := a }
  | .integerArray a => { base with integer_array_value := a }
  | .doubleArray a => { base with double_array_value := a }
  | .stringArray a => { base with string_array_value := a }

/-- Read a wire value back.  The `type` field says which of the union's
fields is meaningful; this is also how rcl reports a command-line override. -/
def ofWire (v : RclInterfaces.Msg.ParameterValue) : ParameterValue :=
  match ParameterType.ofUInt8? v.type with
  | some .bool => .bool v.bool_value
  | some .integer => .integer v.integer_value
  | some .double => .double v.double_value
  | some .string => .string v.string_value
  | some .byteArray => .byteArray v.byte_array_value
  | some .boolArray => .boolArray v.bool_array_value
  | some .integerArray => .integerArray v.integer_array_value
  | some .doubleArray => .doubleArray v.double_array_value
  | some .stringArray => .stringArray v.string_array_value
  | _ => .notSet

instance : ToString ParameterValue where
  toString
    | .notSet => "(not set)"
    | .bool v => toString v
    | .integer v => toString v
    | .double v => toString v
    | .string v => v
    | .byteArray v => s!"<{v.size} bytes>"
    | .boolArray v => toString v.toList
    | .integerArray v => toString v.toList
    | .doubleArray v => toString v.toList
    | .stringArray v => toString v.toList

end ParameterValue

/-- Constraints and documentation attached to a parameter, mirroring
`rcl_interfaces/msg/ParameterDescriptor`. -/
structure ParameterDescriptor where
  name : String := ""
  /-- The type the parameter is fixed to.  `notSet` means any type. -/
  type : ParameterType := .notSet
  description : String := ""
  /-- Free-form text for constraints the range fields cannot express. -/
  additionalConstraints : String := ""
  /-- A read-only parameter can be declared but never set afterwards. -/
  readOnly : Bool := false
  /-- Whether the parameter may change type after declaration. -/
  dynamicTyping : Bool := false
  /-- Inclusive bounds for an integer parameter. -/
  integerRange : Option (Int64 × Int64) := none
  /-- Inclusive bounds for a double parameter. -/
  floatingPointRange : Option (Float × Float) := none
deriving Inhabited

namespace ParameterDescriptor

/-- Whether a value satisfies this descriptor, and why not if it does not. -/
def check (d : ParameterDescriptor) (v : ParameterValue) : Except String Unit := do
  if d.type != .notSet && !d.dynamicTyping && !v.matchesType d.type then
    throw s!"parameter '{d.name}' is {d.type}, but a {v.type} was given"
  if let some (lo, hi) := d.integerRange then
    if let .integer i := v then
      if i < lo || i > hi then
        throw s!"parameter '{d.name}' must be between {lo} and {hi}, got {i}"
  if let some (lo, hi) := d.floatingPointRange then
    if let .double f := v then
      if f < lo || f > hi then
        throw s!"parameter '{d.name}' must be between {lo} and {hi}, got {f}"
  return ()

/-- Convert to the wire representation. -/
def toWire (d : ParameterDescriptor) : RclInterfaces.Msg.ParameterDescriptor :=
  let base : RclInterfaces.Msg.ParameterDescriptor :=
    { name := d.name, type := d.type.toUInt8, description := d.description,
      additional_constraints := d.additionalConstraints,
      read_only := d.readOnly, dynamic_typing := d.dynamicTyping }
  let base := match d.integerRange with
    | none => base
    | some (lo, hi) =>
      { base with integer_range :=
          ⟨#[{ from_value := lo, to_value := hi, step := 0 }], by simp⟩ }
  match d.floatingPointRange with
  | none => base
  | some (lo, hi) =>
    { base with floating_point_range :=
        ⟨#[{ from_value := lo, to_value := hi, step := 0.0 }], by simp⟩ }

end ParameterDescriptor

/-- A parameter: a name, its value, and the constraints it was declared with. -/
structure Parameter where
  name : String
  value : ParameterValue
  descriptor : ParameterDescriptor := {}
deriving Inhabited

end Rcllean
