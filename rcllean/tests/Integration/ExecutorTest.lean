import Rcllean
import Support
import RclInterfaces

/-!
Executor and lifetime tests: what happens when entities are destroyed while
registered, when a node is destroyed, and how service handlers are scheduled
under the multi-threaded executor.
-/

open Rcllean Rcllean.Test

/-- Records how many callbacks were running at once. -/
structure Overlap where
  current : IO.Ref Nat
  peak : IO.Ref Nat

def Overlap.create : IO Overlap :=
  return { current := ← IO.mkRef 0, peak := ← IO.mkRef 0 }

/-- Run `body` while recording concurrency.  The sleep gives an overlap a
chance to be seen. -/
def Overlap.observe (o : Overlap) (body : IO α) : IO α := do
  let n ← o.current.modifyGet fun n => (n + 1, n + 1)
  o.peak.modify (max · n)
  IO.sleep 200
  try body finally o.current.modify (· - 1)

def testDestroyedEntityIsDropped : IO Unit := do
  IO.println "a destroyed entity leaves the executor"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_executor_test_drop"
  let ex ← Executor.create ctx
  let gotA ← IO.mkRef 0
  let gotB ← IO.mkRef 0
  let subA ← node.createSubscription RclInterfaces.Msg.Log topic!"executor_a"
    fun _ => gotA.modify (· + 1)
  let subB ← node.createSubscription RclInterfaces.Msg.Log topic!"executor_b"
    fun _ => gotB.modify (· + 1)
  ex.addSubscription subA
  ex.addSubscription subB
  let pubA ← node.createPublisher RclInterfaces.Msg.Log topic!"executor_a"
  let pubB ← node.createPublisher RclInterfaces.Msg.Log topic!"executor_b"
  let matched ← spinUntil ex do
    return (← pubA.subscriptionCount) > 0 && (← pubB.subscriptionCount) > 0
  check "both subscriptions matched" matched "no match within 10s"

  pubA.publish { msg := "1" }
  pubB.publish { msg := "1" }
  let both ← spinUntil ex do return (← gotA.get) == 1 && (← gotB.get) == 1
  check "both callbacks ran" both s!"got {← gotA.get} and {← gotB.get}"

  subA.destroy
  check "a destroyed subscription reports invalid" (!(← subA.isValid))
  -- The dead entity is still registered; the next pass drops it rather than
  -- hand rcl a destroyed subscription.
  pubB.publish { msg := "2" }
  let again ← spinUntil ex do return (← gotB.get) == 2
  check "the executor keeps running once a registered entity is destroyed" again
    s!"got {← gotB.get} on the surviving subscription"

  let clock ← Clock.steady
  let ticks ← IO.mkRef 0
  let timer ← Timer.create ctx clock (Duration.ofMillis 10) (ticks.modify (· + 1))
  ex.addTimer timer
  let ticked ← spinUntil ex do return (← ticks.get) > 0
  check "a timer fires" ticked
  timer.destroy
  let before ← ticks.get
  let _ ← ex.spinOnce (some (Duration.ofMillis 50))
  let _ ← ex.spinOnce (some (Duration.ofMillis 50))
  check "a destroyed timer stops firing" ((← ticks.get) == before)

  node.destroy
  ctx.shutdown

def testNodeDestroyTearsDownEntities : IO Unit := do
  IO.println "destroying a node destroys its entities"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_executor_test_node"
  let pub ← node.createPublisher RclInterfaces.Msg.Log topic!"executor_node"
  let sub ← node.createSubscription RclInterfaces.Msg.Log topic!"executor_node"
    fun _ => pure ()
  let svc ← node.createService RclInterfaces.Srv.GetParameters
    topic!"executor_node_get" fun _ => return { values := #[] }
  let cli ← node.createClient RclInterfaces.Srv.GetParameters
    topic!"executor_node_get"
  let ev ← QoSEvent.onSubscription sub .requestedIncompatibleQos fun _ => pure ()
  let allValid : IO Bool := do
    return (← pub.isValid) && (← sub.isValid) && (← svc.isValid)
      && (← cli.isValid) && (← ev.isValid)
  check "entities start valid" (← allValid)

  node.destroy
  check "the node reports invalid" (!(← node.isValid))
  check "the publisher went with it" (!(← pub.isValid))
  check "the subscription went with it" (!(← sub.isValid))
  check "the service went with it" (!(← svc.isValid))
  check "the client went with it" (!(← cli.isValid))
  check "the event went with it" (!(← ev.isValid))

  -- Using a destroyed entity is an error, not a crash.
  let refused ← try pub.publish { msg := "late" }; pure false
                catch _ => pure true
  check "publishing on a destroyed publisher raises" refused
  node.destroy
  pub.destroy
  check "destroying twice is harmless" true
  ctx.shutdown

/-- Two calls in flight on one service, with the handler recording overlap. -/
def measureServiceOverlap (kind : CallbackGroupKind) :
    IO (Nat × Option String × Option String) := do
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_executor_test_mt"
  let ex ← Executor.create ctx
  let group ← match kind with
    | .reentrant => CallbackGroup.reentrant
    | .mutuallyExclusive => CallbackGroup.mutuallyExclusive
  let o ← Overlap.create
  let svc ← node.createService RclInterfaces.Srv.GetParameters
    topic!"executor_mt_get"
    fun r => o.observe (return { values := r.names.map fun n =>
      { type := 4, string_value := n } })
  let cli ← node.createClient RclInterfaces.Srv.GetParameters
    topic!"executor_mt_get"
  ex.addService svc (some group)
  ex.addClient cli
  let ready ← spinUntil ex cli.serviceIsReady
  check "the client sees the server" ready "no server within 10s"

  let spinner ← IO.asTask (prio := Task.Priority.dedicated) ex.spinMultiThreaded
  let f1 ← cli.call { names := #["one"] }
  let f2 ← cli.call { names := #["two"] }
  let done ← waitUntil (do return (← f1.isDone) && (← f2.isDone))
  check "both responses arrive" done
  ctx.shutdown
  let _ ← IO.wait spinner
  let r1 ← (do return some (← f1.get)) <|> pure none
  let r2 ← (do return some (← f2.get)) <|> pure none
  node.destroy
  let answer (r : RclInterfaces.Srv.GetParameters_Response) : String :=
    String.intercalate "," (r.values.map (·.string_value)).toList
  return (← o.peak.get, r1.map answer, r2.map answer)

def testServicesUnderMultiThreadedExecutor : IO Unit := do
  IO.println "service handlers under the multi-threaded executor"
  let (peak, r1, r2) ← measureServiceOverlap .reentrant
  check "handlers in a reentrant group overlap" (peak == 2)
    s!"peak concurrency was {peak}"
  check "responses are routed to the right call"
    (r1 == some "one" && r2 == some "two")
    s!"got {r1} and {r2}"
  let (peak, _, _) ← measureServiceOverlap .mutuallyExclusive
  check "handlers in a mutually exclusive group never overlap" (peak == 1)
    s!"peak concurrency was {peak}"

def testSpinUntilCompleteTimeout : IO Unit := do
  IO.println "spinUntilComplete honours its timeout"
  let ctx ← Context.init
  let ex ← Executor.create ctx
  let fut : Future Nat ← Future.create
  let clock ← Clock.steady
  let start ← clock.now
  let result ← ex.spinUntilComplete fut (some (Duration.ofMillis 200))
  let elapsed := ((← clock.now) - start).toFloatSeconds
  check "a future that never completes times out" result.isNone
  check "and the timeout is honoured, not polled past"
    (elapsed ≥ 0.15 && elapsed < 2.0) s!"took {elapsed}s"
  ctx.shutdown

def testAddWakesBlockedWait : IO Unit := do
  IO.println "adding an entity wakes a blocked executor"
  let ctx ← Context.init
  let ex ← Executor.create ctx
  -- Nothing registered: the spinner blocks in the wait with no timer to save it.
  let spinner ← IO.asTask (prio := Task.Priority.dedicated) ex.spin
  let fired ← IO.mkRef false
  let clock ← Clock.steady
  let timer ← Timer.create ctx clock (Duration.ofMillis 10) (fired.set true)
  ex.addTimer timer
  check "a timer added from another thread runs" (← waitUntil fired.get)
  ctx.shutdown
  let outcome ← IO.wait spinner
  check "spin returns after shutdown" outcome.toOption.isSome

def main : IO UInt32 := do
  IO.println "executor tests"
  testDestroyedEntityIsDropped
  testNodeDestroyTearsDownEntities
  testServicesUnderMultiThreadedExecutor
  testSpinUntilCompleteTimeout
  testAddWakesBlockedWait
  finish "executor"
