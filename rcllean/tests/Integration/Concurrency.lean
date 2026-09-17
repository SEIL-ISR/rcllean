import Rcllean
import Support
import RclInterfaces

/-!
Callback group tests: a reentrant group's callbacks may overlap, a mutually
exclusive group's never do.  Each callback records how many of its group's
callbacks were running while it ran.
-/

open Rcllean Rcllean.Test

/-- Tracks how many callbacks ran at once. -/
structure Overlap where
  current : IO.Ref Nat
  peak : IO.Ref Nat
  total : IO.Ref Nat

def Overlap.create : IO Overlap :=
  return { current := ← IO.mkRef 0, peak := ← IO.mkRef 0, total := ← IO.mkRef 0 }

/-- Run a body while recording concurrency.  The sleep gives an overlap a
chance to be seen; without it a callback finishes before the next one starts. -/
def Overlap.observe (o : Overlap) : IO Unit := do
  let n ← o.current.modifyGet fun n => (n + 1, n + 1)
  o.peak.modify (max · n)
  o.total.modify (· + 1)
  IO.sleep 200
  o.current.modify (· - 1)

/-- Publish several messages and let a multi-threaded executor process them,
returning the highest number that ran at once. -/
def measurePeak (groupKind : CallbackGroupKind) : IO (Nat × Nat) := do
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_concurrency_test"
  let o ← Overlap.create
  let ex ← Executor.create ctx
  let group ← match groupKind with
    | .reentrant => CallbackGroup.reentrant
    | .mutuallyExclusive => CallbackGroup.mutuallyExclusive

  -- Four subscriptions on four topics, all in the one group.
  let mut pubs := #[]
  let mut subs := #[]
  for i in [0:4] do
    let name := s!"concurrency_{i}"
    let some topic := TopicName.ofString? name
      | throw (IO.userError s!"'{name}' is not a valid topic name")
    let sub ← node.createSubscription RclInterfaces.Msg.Log topic
      (fun _ => o.observe)
    ex.addSubscription sub (some group)
    subs := subs.push sub
    pubs := pubs.push (← node.createPublisher RclInterfaces.Msg.Log topic)

  -- Wait for every subscription to be matched before publishing, or the
  -- messages go nowhere.
  let clock ← Clock.steady
  let start ← clock.now
  let mut matched := false
  while !matched && ((← clock.now) - start).toFloatSeconds < 10.0 do
    let mut all := true
    for p in pubs do
      if (← p.subscriptionCount) == 0 then all := false
    matched := all
    if !matched then
      let _ ← ex.spinOnce (some (Duration.ofMillis 50))

  let spinner ← IO.asTask (prio := Task.Priority.dedicated) ex.spinMultiThreaded
  for p in pubs do
    p.publish { msg := "go" }

  -- Wait for the work, not a fixed time: a mutually exclusive group runs the
  -- four callbacks one after another, which is slow under valgrind.
  let deadline ← clock.now
  while (← o.total.get) < 4 &&
        ((← clock.now) - deadline).toFloatSeconds < 60.0 do
    IO.sleep 50
  ctx.shutdown
  let _ ← IO.wait spinner

  let peak ← o.peak.get
  let total ← o.total.get
  -- Entities and the node go before the context: rcl keeps a process-wide
  -- table of rosout publishers keyed by logger name, and a node torn down
  -- after its context leaves a stale entry the next node of that name reads.
  for p in pubs do
    p.destroy
  for sub in subs do
    sub.destroy
  node.destroy
  return (peak, total)

def main : IO UInt32 := do
  IO.println "callback group tests"

  IO.println "reentrant groups"
  let (reentrantPeak, reentrantTotal) ← measurePeak .reentrant
  check "every message is handled" (reentrantTotal == 4)
    s!"handled {reentrantTotal} of 4"
  check "callbacks in a reentrant group overlap" (reentrantPeak > 1)
    s!"peak concurrency was {reentrantPeak}, so nothing overlapped"

  IO.println "mutually exclusive groups"
  let (exclusivePeak, exclusiveTotal) ← measurePeak .mutuallyExclusive
  check "every message is handled" (exclusiveTotal == 4)
    s!"handled {exclusiveTotal} of 4"
  check "callbacks in a mutually exclusive group never overlap"
    (exclusivePeak == 1)
    s!"peak concurrency was {exclusivePeak}, so two ran at once"

  finish "callback group"
