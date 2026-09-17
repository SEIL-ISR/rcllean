import Rcllean
import Support
import RclInterfaces
import RosgraphMsgs

/-!
Parameter tests: declaration, constraints, callbacks and simulated time.
-/

open Rcllean Rcllean.Test

def testDeclareAndSet : IO Unit := do
  IO.println "declaring and setting"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_param_test"
  let params ← ParameterServer.create node

  let rate ← params.declare "rate" (.double 1.0)
    { floatingPointRange := some (0.1, 10.0) }
  check "a declared parameter takes its default"
    (rate.asFloat? == some 1.0) s!"got {rate}"

  check "setting within range succeeds"
    (← params.set #[("rate", .double 5.0)]).successful
  check "the new value is read back"
    ((← params.get "rate").asFloat? == some 5.0) s!"got {← params.get "rate"}"

  let outOfRange ← params.set #[("rate", .double 500.0)]
  check "setting outside the range is refused" (!outOfRange.successful)
  check "the refusal says why" (outOfRange.reason.length > 0) "empty reason"
  check "a refused set leaves the value alone"
    ((← params.get "rate").asFloat? == some 5.0) s!"got {← params.get "rate"}"

  let wrongType ← params.set #[("rate", .string "fast")]
  check "setting the wrong type is refused" (!wrongType.successful)

  let _ ← params.declare "fixed" (.integer 42) { readOnly := true }
  check "setting a read-only parameter is refused"
    (!(← params.set #[("fixed", .integer 7)]).successful)

  let undeclared ← params.set #[("never_declared", .integer 1)]
  check "setting an undeclared parameter is refused" (!undeclared.successful)

  match ← params.store.getParameter? "rate" with
  | none => fail "the descriptor is kept" "parameter not found"
  | some p =>
    check "the descriptor is kept"
      (p.descriptor.floatingPointRange == some (0.1, 10.0))
      "range was not stored"

  params.destroy
  node.destroy
  ctx.shutdown

def testCallbackVeto : IO Unit := do
  IO.println "on-set callbacks"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_param_callback"
  let params ← ParameterServer.create node
  let _ ← params.declare "greeting" (.string "hello")
  let seen ← IO.mkRef 0

  params.addOnSetCallback fun updates => do
    seen.modify (· + 1)
    for p in updates do
      if p.name == "greeting" then
        if let .string s := p.value then
          if s.isEmpty then
            return SetResult.refuse "greeting must not be empty"
    return SetResult.ok

  check "a callback can refuse a change"
    (!(← params.set #[("greeting", .string "")]).successful)
  check "a refused change is not applied"
    ((← params.get "greeting").asString? == some "hello")
    s!"got {← params.get "greeting"}"
  check "an allowed change goes through"
    (← params.set #[("greeting", .string "hi")]).successful
  check "the callback ran for both attempts" ((← seen.get) == 2)
    s!"ran {← seen.get} times"

  params.destroy
  node.destroy
  ctx.shutdown

/-- Setting several parameters at once is all or nothing: if any one of them is
rejected, none of them changes. -/
def testAtomicSet : IO Unit := do
  IO.println "atomic multi-parameter set"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_param_atomic"
  let params ← ParameterServer.create node
  let _ ← params.declare "a" (.integer 1)
  let _ ← params.declare "b" (.integer 2) { integerRange := some (0, 10) }

  let result ← params.set #[("a", .integer 100), ("b", .integer 999)]
  check "a batch with one bad value is refused" (!result.successful)
  check "the good value in a refused batch is not applied"
    ((← params.get "a").asInt? == some 1) s!"got {← params.get "a"}"

  check "a batch where everything is valid succeeds"
    (← params.set #[("a", .integer 7), ("b", .integer 8)]).successful
  check "both values are applied"
    ((← params.get "a").asInt? == some 7 && (← params.get "b").asInt? == some 8)
    "one of the two did not change"

  params.destroy
  node.destroy
  ctx.shutdown

/-- With `use_sim_time` on, a node's clock follows `/clock` rather than the
wall. -/
def testSimTime : IO Unit := do
  IO.println "use_sim_time drives the clock"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_sim_time"
  let params ← ParameterServer.create node
  let clock ← Clock.ros
  let ts ← TimeSource.create node clock
  ts.followParameter params

  let ex ← Executor.create ctx
  params.addToExecutor ex
  ts.addToExecutor ex

  check "sim time is off until the parameter says otherwise"
    (!(← clock.rosTimeOverrideIsEnabled))

  check "turning use_sim_time on succeeds"
    (← params.set #[("use_sim_time", .bool true)]).successful
  check "the clock switches to simulated time"
    (← clock.rosTimeOverrideIsEnabled)

  -- Publish a clock tick and check the node's clock follows it.
  let clockPub ← node.createPublisher RosgraphMsgs.Msg.Clock topic!"/clock"
    (QoS.bestEffort 1)
  let matched ← spinUntil ex
    (do return (← clockPub.subscriptionCount) > 0) (Duration.ofSeconds 10)
  check "the clock subscription matches" matched "no match within 10s"

  clockPub.publish { clock := { sec := 1234, nanosec := 5678 } }
  let followed ← spinUntil ex
    (do return (← clock.now).nanos == 1234000005678) (Duration.ofSeconds 10)
  check "the clock reports the published time" followed
    s!"clock reads {(← clock.now).nanos}"

  check "turning use_sim_time off succeeds"
    (← params.set #[("use_sim_time", .bool false)]).successful
  check "the clock returns to the wall"
    (!(← clock.rosTimeOverrideIsEnabled))

  clockPub.destroy
  ts.destroy
  params.destroy
  node.destroy
  ctx.shutdown

def main : IO UInt32 := do
  IO.println "parameter tests"
  testDeclareAndSet
  testCallbackVeto
  testAtomicSet
  testSimTime
  finish "parameter"
