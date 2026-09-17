import Rcllean.ParameterService
import RosgraphMsgs

/-!
# Simulated time

A node with `use_sim_time` set follows the `/clock` topic instead of the wall,
so a simulator can run faster or slower than real time.  Timers in such a node
must be created on the node's ROS clock, not a steady one.  Setting the
parameter at run time switches the clock over.
-/

namespace Rcllean

/-- Drives a ROS clock from the `/clock` topic when `use_sim_time` is on. -/
structure TimeSource where
  node : Node
  /-- The clock handed to timers: the wall until sim time is enabled, then
  whatever `/clock` last said. -/
  clock : Clock .rosTime
  subscription : Subscription RosgraphMsgs.Msg.Clock
  /-- Whether sim time is currently in effect. -/
  enabled : IO.Ref Bool

namespace TimeSource

/-- Create a time source for a node.  The `/clock` subscription is best-effort
with a queue of one, matching what simulated-time publishers offer. -/
def create (node : Node) (clock : Clock .rosTime) : IO TimeSource := do
  let enabled ← IO.mkRef false
  let sub ← node.createSubscription RosgraphMsgs.Msg.Clock topic!"/clock"
    (fun msg => do
      if ← enabled.get then
        let nanos := Int64.ofInt (msg.clock.sec.toInt * 1000000000
                                  + msg.clock.nanosec.toNat)
        clock.setRosTimeOverride (Time.ofNanos nanos))
    (QoS.bestEffort 1)
  return { node, clock, subscription := sub, enabled }

/-- Turn simulated time on or off: the clock follows `/clock` while on and the
wall while off. -/
def setEnabled (ts : TimeSource) (on : Bool) : IO Unit := do
  if (← ts.enabled.get) == on then
    return
  ts.enabled.set on
  ts.clock.enableRosTimeOverride on

/-- Follow a node's `use_sim_time` parameter, now and whenever it changes, so
`--ros-args -p use_sim_time:=true` takes effect. -/
def followParameter (ts : TimeSource) (params : ParameterServer) : IO Unit := do
  match (← params.get "use_sim_time").asBool? with
  | some on => ts.setEnabled on
  | none => pure ()
  params.addOnSetCallback fun updates => do
    for p in updates do
      if p.name == "use_sim_time" then
        if let some on := p.value.asBool? then
          ts.setEnabled on
    return SetResult.ok

/-- Register the `/clock` subscription with an executor. -/
def addToExecutor (ts : TimeSource) (ex : Executor) : IO Unit :=
  ex.addSubscription ts.subscription

def destroy (ts : TimeSource) : IO Unit :=
  ts.subscription.destroy

end TimeSource

end Rcllean
