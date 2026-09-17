import Rcllean
import Support
import LifecycleMsgs
import RclInterfaces

/-!
Service and client tests, in one process.
-/

open Rcllean Rcllean.Test

def testRoundTrip : IO Unit := do
  IO.println "request and response"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_service_test"
  let calls ← IO.mkRef 0

  let svc ← node.createService RclInterfaces.Srv.GetParameters
    topic!"test_get_params"
    fun req => do
      calls.modify (· + 1)
      return { values := req.names.map fun n =>
        { type := 4, string_value := n.toUpper } }
  let cli ← node.createClient RclInterfaces.Srv.GetParameters
    topic!"test_get_params"
  let ex ← Executor.create ctx
  ex.addService svc
  ex.addClient cli

  let ready ← spinUntil ex cli.serviceIsReady (Duration.ofSeconds 10)
  check "the client sees the server" ready "no server within 10s"

  let fut ← cli.call { names := #["answer"] }
  match ← ex.spinUntilComplete fut (some (Duration.ofSeconds 10)) with
  | none => fail "the response arrives" "no response within 10s"
  | some resp =>
    check "the response arrives" true
    check "the handler's answer comes back"
      (resp.values.map (·.string_value) == #["ANSWER"])
      s!"got {repr (resp.values.map (·.string_value))}"

  check "the handler ran exactly once" ((← calls.get) == 1)
    s!"ran {← calls.get} times"

  svc.destroy
  cli.destroy
  node.destroy
  ctx.shutdown

/-- Several calls in flight must each get their own answer.  A response carries
the sequence number of its request, and the client completes that future. -/
def testConcurrentCalls : IO Unit := do
  IO.println "several calls in flight"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_service_concurrent"

  let svc ← node.createService RclInterfaces.Srv.GetParameters
    topic!"test_get_params2"
    fun req => return { values := req.names.map fun n =>
      { type := 4, string_value := n ++ "!" } }
  let cli ← node.createClient RclInterfaces.Srv.GetParameters
    topic!"test_get_params2"
  let ex ← Executor.create ctx
  ex.addService svc
  ex.addClient cli
  let ready ← spinUntil ex cli.serviceIsReady (Duration.ofSeconds 10)
  check "the client sees the server" ready "no server within 10s"

  let mut futures := #[]
  for i in [0:5] do
    futures := futures.push (i, ← cli.call { names := #[s!"p{i}"] })

  let mut wrong := 0
  for (i, fut) in futures do
    match ← ex.spinUntilComplete fut (some (Duration.ofSeconds 10)) with
    | none => wrong := wrong + 1
    | some resp =>
      if resp.values.map (·.string_value) != #[s!"p{i}!"] then
        wrong := wrong + 1
  check "each call gets its own answer" (wrong == 0)
    s!"{wrong} of 5 answers were wrong or missing"

  svc.destroy
  cli.destroy
  node.destroy
  ctx.shutdown

/-- A service with an empty request still works: rosidl gives such a message a
placeholder member, and the converters have to account for it. -/
def testEmptyRequest : IO Unit := do
  IO.println "empty request types"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_service_empty"
  let svc ← node.createService LifecycleMsgs.Srv.GetState topic!"test_get_state"
    fun _ => return { current_state := { id := 1, label := "unconfigured" } }
  let cli ← node.createClient LifecycleMsgs.Srv.GetState topic!"test_get_state"
  let ex ← Executor.create ctx
  ex.addService svc
  ex.addClient cli

  let ready ← spinUntil ex cli.serviceIsReady (Duration.ofSeconds 10)
  check "the client sees the server" ready "no server within 10s"
  let fut ← cli.call {}
  match ← ex.spinUntilComplete fut (some (Duration.ofSeconds 10)) with
  | none => fail "an empty exchange completes" "no response within 10s"
  | some _ => pass "an empty exchange completes"

  svc.destroy
  cli.destroy
  node.destroy
  ctx.shutdown

def main : IO UInt32 := do
  IO.println "service tests"
  testRoundTrip
  testConcurrentCalls
  testEmptyRequest
  finish "service"
