import Rcllean.Context
import Rcllean.Logging
import Rcllean.Clock
import RclInterfaces.Msg.ParameterValue

/-!
# Nodes

A `Node` owns publishers, subscriptions, services, timers and parameters, and
appears in `ros2 node list`.  Creating one starts nothing running; entities
become active when the node is given to an executor.
-/

namespace Rcllean.FFI

-- C bindings

private opaque NodePointed : NonemptyType
/-- An `rcl_node_t`.  Keeps its context alive. -/
def Node : Type := NodePointed.type
instance : Nonempty Node := NodePointed.property

/-- `rcl_node_init`. -/
@[extern "rcllean_node_create"]
opaque nodeCreate (ctx : @& Context) (name : @& String) (namespace_ : @& String)
    (useGlobalArguments : Bool) (enableRosout : Bool)
    (args : @& Array String) : IO Node

/-- `rcl_node_fini`.  Idempotent. -/
@[extern "rcllean_node_destroy"]
opaque nodeDestroy (node : @& Node) : IO Unit

@[extern "rcllean_node_is_valid"]
opaque nodeIsValid (node : @& Node) : IO Bool

@[extern "rcllean_node_get_name"]
opaque nodeName (node : @& Node) : IO String

@[extern "rcllean_node_get_namespace"]
opaque nodeNamespace (node : @& Node) : IO String

@[extern "rcllean_node_get_fully_qualified_name"]
opaque nodeFullyQualifiedName (node : @& Node) : IO String

@[extern "rcllean_node_logger_name"]
opaque nodeLoggerName (node : @& Node) : IO String

/-- rcl parses `--ros-args -p name:=value` and `--params-file file.yaml` into a
table of per-node overrides. -/
@[extern "rcllean_param_override_node_count"]
opaque paramOverrideNodeCount (ctx : @& Context) : IO UInt32

/-- The node an override block applies to.  It may be a wildcard pattern such
as `/**`, which matches every node. -/
@[extern "rcllean_param_override_node_name"]
opaque paramOverrideNodeName (ctx : @& Context) (i : UInt32) : IO String

@[extern "rcllean_param_override_count"]
opaque paramOverrideCount (ctx : @& Context) (i : UInt32) : IO UInt32

@[extern "rcllean_param_override_name"]
opaque paramOverrideName (ctx : @& Context) (i : UInt32) (j : UInt32) : IO String

@[extern "rcllean_param_override_value"]
opaque paramOverrideValue (ctx : @& Context) (i : UInt32) (j : UInt32) :
    IO RclInterfaces.Msg.ParameterValue

end Rcllean.FFI

namespace Rcllean

/-- Options controlling how a node is created.  The defaults match `rclpy`. -/
structure NodeOptions where
  /-- Whether the context's command-line arguments (remapping, parameter
  overrides) apply to this node. -/
  useGlobalArguments : Bool := true
  /-- Whether the node publishes its log records to `/rosout`. -/
  enableRosout : Bool := true
  /-- Arguments applying only to this node, in `--ros-args` form. -/
  arguments : Array String := #[]
deriving Inhabited

/-- A ROS 2 node. -/
structure Node where
  /-- The underlying `rcl_node_t`.  Internal. -/
  handle : FFI.Node
  /-- The context this node belongs to, held so it cannot be collected while
  the node is alive. -/
  context : Context
  /-- The node's logger, resolved once at creation.  Its name comes from the
  fully qualified node name, so `--log-level /my_node:=debug` reaches it. -/
  logger : Logger

namespace Node

/-- Create a node.  `name` must be a valid node name (no slashes) and
`namespace_` a valid namespace; `Rcllean.Names` states the rules, and rcl
raises on anything else. -/
def create (ctx : Context) (name : String) (namespace_ : String := "")
    (options : NodeOptions := {}) : IO Node := do
  let handle ← FFI.nodeCreate ctx.handle name namespace_
    options.useGlobalArguments options.enableRosout options.arguments
  let logger : Logger := ⟨← FFI.nodeLoggerName handle⟩
  return ⟨handle, ctx, logger⟩

/-- Destroy the node and every entity created on it.  Idempotent.

Call this before `Context.shutdown`: rcl keeps a process-wide table of
`/rosout` publishers keyed by logger name, and a node torn down after its
context leaves a stale entry the next node with that name reads. -/
def destroy (node : Node) : IO Unit :=
  FFI.nodeDestroy node.handle

/-- Whether the node is still usable: not destroyed and its context still up. -/
def isValid (node : Node) : IO Bool :=
  FFI.nodeIsValid node.handle

/-- The node's name, without its namespace. -/
def name (node : Node) : IO String :=
  FFI.nodeName node.handle

/-- The node's namespace. -/
def namespace_ (node : Node) : IO String :=
  FFI.nodeNamespace node.handle

/-- The node's fully qualified name, as it appears in `ros2 node list`. -/
def fullyQualifiedName (node : Node) : IO String :=
  FFI.nodeFullyQualifiedName node.handle

instance : HasLogger Node := ⟨Node.logger⟩

/-- Log a debug record through the node's logger. -/
def logDebug (node : Node) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  node.logger.debug message function

/-- Log an informational record through the node's logger. -/
def logInfo (node : Node) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  node.logger.info message function

/-- Log a warning through the node's logger. -/
def logWarn (node : Node) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  node.logger.warn message function

/-- Log an error through the node's logger. -/
def logError (node : Node) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  node.logger.error message function

/-- Log a fatal record through the node's logger. -/
def logFatal (node : Node) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  node.logger.fatal message function

/-- Run `act` with a node, destroying it afterwards even if it throws. -/
def with' (ctx : Context) (name : String) (namespace_ : String := "")
    (options : NodeOptions := {}) (act : Node → IO α) : IO α := do
  let node ← create ctx name namespace_ options
  try
    act node
  finally
    node.destroy

end Node

end Rcllean
