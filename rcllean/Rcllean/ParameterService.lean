import Rcllean.ParameterStore
import Rcllean.Publisher
import Rcllean.Service
import Rcllean.Client
import Rcllean.Executor
import RclInterfaces

/-!
# Parameter services

A ROS 2 node exposes its parameters over six services and one topic, which
`ros2 param list`, `get`, `set`, `describe` and `dump` talk to.  The
conversions between the Lean parameter types and the `rcl_interfaces` messages
are `ParameterValue.toWire` and friends in `Rcllean.Parameter`.
-/

namespace Rcllean

open RosidlRuntimeLean

/-- The parameter services and event topic a node exposes.  Add it to an
executor for the services to be answered. -/
structure ParameterServer where
  store : ParameterStore
  node : Node
  getParams : Service RclInterfaces.Srv.GetParameters
  getTypes : Service RclInterfaces.Srv.GetParameterTypes
  setParams : Service RclInterfaces.Srv.SetParameters
  setAtomically : Service RclInterfaces.Srv.SetParametersAtomically
  describe : Service RclInterfaces.Srv.DescribeParameters
  list : Service RclInterfaces.Srv.ListParameters
  /-- Announces declarations and changes, so other nodes need not poll. -/
  events : Publisher RclInterfaces.Msg.ParameterEvent

namespace ParameterServer

/-- Publish a parameter event.  Failures are ignored; a node with a failing
event publisher still serves parameters. -/
private def publishEvent (srv : ParameterServer) (changed : Array Parameter)
    (isNew : Bool) : IO Unit := do
  if changed.isEmpty then return
  let clock ← Clock.ros
  let now ← clock.now
  let secs := now.nanos / 1000000000
  let nsecs := now.nanos % 1000000000
  let wire := changed.map fun p =>
    ({ name := p.name, value := p.value.toWire } : RclInterfaces.Msg.Parameter)
  let event : RclInterfaces.Msg.ParameterEvent :=
    { stamp := { sec := Int32.ofInt secs.toInt, nanosec := UInt32.ofNat nsecs.toInt.toNat }
      node := ← srv.node.fullyQualifiedName
      new_parameters := if isNew then wire else #[]
      changed_parameters := if isNew then #[] else wire }
  try srv.events.publish event catch _ => pure ()

/-- Declare a parameter and announce it. -/
def declare (srv : ParameterServer) (name : String)
    (defaultValue : ParameterValue := .notSet)
    (descriptor : ParameterDescriptor := {}) : IO ParameterValue := do
  let v ← srv.store.declare name defaultValue descriptor
  srv.publishEvent #[{ name, value := v, descriptor }] true
  return v

/-- Set parameters and announce whatever changed. -/
def set (srv : ParameterServer) (updates : Array (String × ParameterValue)) :
    IO SetResult := do
  let result ← srv.store.setAtomically updates
  if result.successful then
    let params ← srv.store.params.get
    srv.publishEvent (updates.filterMap fun (n, _) => params[n]?) false
  return result

/-- Create the parameter services on a node.  `use_sim_time`, which switches a
node's clock from the wall to `/clock`, is declared here as every ROS 2 node
has it. -/
def create (node : Node) (allowUndeclared : Bool := false) :
    IO ParameterServer := do
  let store ← ParameterStore.create node.context (← node.fullyQualifiedName)
    allowUndeclared
  let events ← node.createPublisher RclInterfaces.Msg.ParameterEvent
    topic!"/parameter_events" QoS.parameterEvents

  let getParams ← node.createService RclInterfaces.Srv.GetParameters
    topic!"~/get_parameters" fun req => do
      let mut values := #[]
      for name in req.names do
        let v ← try store.get name catch _ => pure ParameterValue.notSet
        values := values.push v.toWire
      return { values }

  let getTypes ← node.createService RclInterfaces.Srv.GetParameterTypes
    topic!"~/get_parameter_types" fun req => do
      let mut types := #[]
      for name in req.names do
        let v ← try store.get name catch _ => pure ParameterValue.notSet
        types := types.push v.type.toUInt8
      return { types := ByteArray.mk types }

  let describe ← node.createService RclInterfaces.Srv.DescribeParameters
    topic!"~/describe_parameters" fun req => do
      let mut descriptors := #[]
      for name in req.names do
        match ← store.getParameter? name with
        | some p => descriptors := descriptors.push p.descriptor.toWire
        | none => descriptors := descriptors.push { name }
      return { descriptors }

  let list ← node.createService RclInterfaces.Srv.ListParameters
    topic!"~/list_parameters" fun req => do
      let all ← store.all
      -- An empty prefix list means everything; `ros2 param list` sends
      -- that.
      let matching := all.filter fun p =>
        req.prefixes.isEmpty || req.prefixes.any fun pre =>
          p.name == pre || p.name.startsWith (pre ++ ".")
      return { result := { names := matching.map (·.name) } }

  -- The services close over the store, so the server is built after them and
  -- reached through this ref.
  let serverRef ← IO.mkRef (none : Option ParameterServer)

  let setParams ← node.createService RclInterfaces.Srv.SetParameters
    topic!"~/set_parameters" fun req => do
      let mut results := #[]
      -- `set_parameters` applies each one independently; one failure does
      -- not stop the rest.
      for p in req.parameters do
        let r ← match ← serverRef.get with
          | some srv => srv.set #[(p.name, ParameterValue.ofWire p.value)]
          | none => store.set p.name (ParameterValue.ofWire p.value)
        results := results.push { successful := r.successful, reason := r.reason }
      return { results }

  let setAtomically ← node.createService RclInterfaces.Srv.SetParametersAtomically
    topic!"~/set_parameters_atomically" fun req => do
      let updates := req.parameters.map fun p => (p.name, ParameterValue.ofWire p.value)
      let r ← match ← serverRef.get with
        | some srv => srv.set updates
        | none => store.setAtomically updates
      return { result := { successful := r.successful, reason := r.reason } }

  let srv : ParameterServer :=
    { store, node, getParams, getTypes, setParams, setAtomically, describe,
      list, events }
  serverRef.set (some srv)

  -- Every ROS 2 node declares this one.
  let _ ← srv.declare "use_sim_time" (.bool false)
  return srv

/-- Register the parameter services with an executor so they are answered. -/
def addToExecutor (srv : ParameterServer) (ex : Executor) : IO Unit := do
  ex.addService srv.getParams
  ex.addService srv.getTypes
  ex.addService srv.setParams
  ex.addService srv.setAtomically
  ex.addService srv.describe
  ex.addService srv.list

/-- The value of a parameter. -/
def get (srv : ParameterServer) (name : String) : IO ParameterValue :=
  srv.store.get name

/-- Refuse or accept changes before they take effect. -/
def addOnSetCallback (srv : ParameterServer)
    (cb : Array Parameter → IO SetResult) : IO Unit :=
  srv.store.addOnSetCallback cb

def destroy (srv : ParameterServer) : IO Unit := do
  srv.getParams.destroy
  srv.getTypes.destroy
  srv.setParams.destroy
  srv.setAtomically.destroy
  srv.describe.destroy
  srv.list.destroy
  srv.events.destroy

end ParameterServer

end Rcllean
