import Rcllean
import Support
import RclInterfaces

/-!
In-process topic, timer and clock tests.  These need a working middleware but
no external processes: a publisher and a subscription in one node still go
through the full DDS path.
-/

open Rcllean Rcllean.Test

def testPubSub : IO Unit := do
  IO.println "publish and subscribe in one process"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_topic_test"
  let received ← IO.mkRef (#[] : Array String)

  let sub ← node.createSubscription RclInterfaces.Msg.Log topic!"test_chatter"
    fun msg =>
    received.modify (·.push msg.msg)
  let pub ← node.createPublisher RclInterfaces.Msg.Log topic!"test_chatter"

  let ex ← Executor.create ctx
  ex.addSubscription sub

  -- Discovery is asynchronous: publishing before the subscription matches
  -- drops the message.
  let matched ← spinUntil ex
    (do return (← pub.subscriptionCount) > 0) (Duration.ofSeconds 10)
  check "publisher and subscription match" matched
    "no subscription matched within 10s"

  for i in [0:5] do
    pub.publish { msg := s!"msg {i}" }

  let got ← spinUntil ex
    (do return (← received.get).size ≥ 5) (Duration.ofSeconds 10)
  check "all five messages arrive" got
    s!"only received {(← received.get).size}"

  let msgs ← received.get
  check "messages arrive in order and intact"
    (msgs.toList.take 5 == (List.range 5).map fun i => s!"msg {i}")
    s!"got {msgs.toList}"

  check "subscription reports its publisher"
    ((← sub.publisherCount) > 0) "publisher count was zero"

  sub.destroy
  pub.destroy
  node.destroy
  ctx.shutdown

def testTimerRate : IO Unit := do
  IO.println "timer rate"
  let ctx ← Context.init
  let clock ← Clock.steady
  let ticks ← IO.mkRef 0
  let timer ← Timer.create ctx clock (Duration.ofMillis 100) do
    ticks.modify (· + 1)
  let ex ← Executor.create ctx
  ex.addTimer timer

  let start ← clock.now
  let _ ← spinUntil ex (do return (← ticks.get) ≥ 10)
    (Duration.ofSeconds 5)
  let elapsed := (← clock.now) - start
  let n ← ticks.get

  -- Ten ticks at 100ms take about a second; the slack is for a loaded
  -- machine.
  let seconds := elapsed.toFloatSeconds
  check "ten 100ms ticks take roughly one second"
    (n ≥ 10 && seconds > 0.9 && seconds < 2.0)
    s!"{n} ticks in {seconds}s"

  timer.cancel
  check "a cancelled timer reports itself cancelled" (← timer.isCanceled)
  timer.reset
  check "a reset timer is no longer cancelled" !(← timer.isCanceled)

  ctx.shutdown

/-- Create a context, a clock and a timer on them, and return only the timer.
Both locals go out of scope here, so the timer's own references are all that
keep the rcl context and clock alive. -/
def timerOutlivingItsLocals : IO Timer := do
  let ctx ← Rcllean.init
  let clock ← Clock.steady
  Timer.create ctx clock (Duration.ofMillis 50) (pure ())

def testTimerOutlivesItsLocals : IO Unit := do
  IO.println "a timer keeps its context and clock alive"
  let timer ← timerOutlivingItsLocals
  check "the timer survives the locals it was created from" (← timer.isValid)

  -- Reads the clock and the timer's guard condition; both belong to state
  -- freed already if the context had been finalized first.
  let _ ← timer.timeUntilNextCall
  timer.cancel
  check "a timer whose creator returned still cancels" (← timer.isCanceled)

  timer.destroy
  check "destroy invalidates the handle" !(← timer.isValid)
  timer.destroy
  check "a second destroy is a no-op" !(← timer.isValid)
  let failed ← try
      let _ ← timer.timeUntilNextCall
      pure false
    catch _ => pure true
  check "an operation on a destroyed timer fails cleanly" failed

def testSimTime : IO Unit := do
  IO.println "simulated time"
  let clock ← Clock.ros
  check "a ROS clock starts out following the wall"
    !(← clock.rosTimeOverrideIsEnabled)

  clock.enableRosTimeOverride
  check "the override can be enabled" (← clock.rosTimeOverrideIsEnabled)

  clock.setRosTimeOverride (Time.ofNanos 1234567890)
  let t ← clock.now
  check "the clock reports the time it was given"
    (t.nanos == 1234567890) s!"got {t.nanos}"

  -- Under simulated time the clock moves only when it is told to.
  clock.setRosTimeOverride (Time.ofNanos 2000000000)
  let t2 ← clock.now
  check "time advances only when set" (t2.nanos == 2000000000) s!"got {t2.nanos}"

  let delta := t2 - t
  check "durations between simulated times are exact"
    (delta.nanos == 765432110) s!"got {delta.nanos}"

def testQoSMismatch : IO Unit := do
  IO.println "QoS compatibility predicts what actually connects"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_qos_test"

  -- best effort publisher, reliable subscription: incompatible, and the
  -- predicate says so before anything is created.
  check "predicate rejects best-effort publisher with reliable subscription"
    (QoS.compatible (QoS.bestEffort 10) (QoS.reliable 10) == false)

  let pub ← node.createPublisher RclInterfaces.Msg.Log topic!"qos_topic"
    (QoS.bestEffort 10)
  let sub ← node.createSubscription RclInterfaces.Msg.Log topic!"qos_topic"
    (fun _ => pure ())
    (QoS.reliable 10)
  let ex ← Executor.create ctx
  ex.addSubscription sub

  -- Give discovery time to fail to match.
  let matched ← spinUntil ex
    (do return (← pub.subscriptionCount) > 0) (Duration.ofSeconds 3)
  check "incompatible profiles do not connect" (matched == false)
    "they matched, which contradicts the DDS rules"

  sub.destroy
  pub.destroy
  node.destroy
  ctx.shutdown

/-- Round-trip a message with nested fields and arrays of messages through a
real publish and subscribe, so the generated converters are exercised on the
wire. -/
def testGeneratedTypes : IO Unit := do
  IO.println "generated message types over a real topic"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_generated_test"
  let got ← IO.mkRef (none : Option RclInterfaces.Msg.ParameterEvent)

  let sub ← node.createSubscription RclInterfaces.Msg.ParameterEvent
    topic!"test_event" fun msg => got.set (some msg)
  let pub ← node.createPublisher RclInterfaces.Msg.ParameterEvent
    topic!"test_event"
  let ex ← Executor.create ctx
  ex.addSubscription sub

  let matched ← spinUntil ex
    (do return (← pub.subscriptionCount) > 0) (Duration.ofSeconds 10)
  check "event publisher and subscription match" matched "no match within 10s"

  let sent : RclInterfaces.Msg.ParameterEvent :=
    { stamp := { sec := 7, nanosec := 250000000 }
      node := "/generated"
      new_parameters :=
        #[{ name := "rate", value := { type := 3, double_value := 10.5 } },
          { name := "tags", value := { type := 9,
                                       string_array_value := #["a", "b"] } }]
      changed_parameters := #[]
      deleted_parameters := #[{ name := "gone", value := { type := 0 } }] }
  pub.publish sent

  let arrived ← spinUntil ex (do return (← got.get).isSome)
    (Duration.ofSeconds 10)
  check "the event arrives" arrived "nothing received within 10s"

  match ← got.get with
  | none => fail "event contents" "nothing received"
  | some r =>
    check "nested scalar fields survive the round trip"
      (r.stamp.sec == 7 && r.stamp.nanosec == 250000000 &&
       r.node == "/generated")
      s!"got sec={r.stamp.sec} nanosec={r.stamp.nanosec} node={r.node}"
    check "an array of nested messages survives"
      (r.new_parameters.size == 2 &&
       r.new_parameters[0]!.value.double_value == 10.5 &&
       r.new_parameters[1]!.value.string_array_value == #["a", "b"] &&
       r.deleted_parameters.map (·.name) == #["gone"])
      s!"got {repr r.new_parameters}"

  sub.destroy
  pub.destroy
  node.destroy
  ctx.shutdown

/-- Byte payloads are the performance-sensitive path: `uint8[]` is one buffer,
not an array of boxed bytes. -/
def testBytePayload : IO Unit := do
  IO.println "byte payloads"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_bytes_test"
  let got ← IO.mkRef (none : Option RclInterfaces.Msg.ParameterValue)

  let sub ← node.createSubscription RclInterfaces.Msg.ParameterValue
    topic!"test_bytes" fun msg => got.set (some msg)
  let pub ← node.createPublisher RclInterfaces.Msg.ParameterValue
    topic!"test_bytes"
  let ex ← Executor.create ctx
  ex.addSubscription sub
  let matched ← spinUntil ex
    (do return (← pub.subscriptionCount) > 0) (Duration.ofSeconds 10)
  check "byte publisher and subscription match" matched "no match within 10s"

  let payload := ByteArray.mk (Array.range 4096 |>.map fun i => UInt8.ofNat (i % 256))
  pub.publish { type := 5, byte_array_value := payload,
                string_value := "blob" }

  let arrived ← spinUntil ex (do return (← got.get).isSome)
    (Duration.ofSeconds 10)
  check "the payload arrives" arrived "nothing received within 10s"
  match ← got.get with
  | none => fail "payload contents" "nothing received"
  | some r =>
    check "the payload survives byte for byte"
      (r.byte_array_value.toList == payload.toList && r.string_value == "blob"
       && r.type == 5)
      s!"got {r.byte_array_value.size} bytes, string {r.string_value}"

  sub.destroy
  pub.destroy
  node.destroy
  ctx.shutdown

/-- A publisher and subscription whose profiles do not match never connect.
The middleware reports it through a quality of service event; without the
event, an incompatible pair is simply silent. -/
def testQoSEvents : IO Unit := do
  IO.println "incompatible QoS is reported as an event"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_qos_event_test"
  let reported ← IO.mkRef (none : Option EventStatus)

  -- Best effort offered, reliable requested: incompatible, so the two should
  -- not connect and the subscription should be told why.
  let sub ← node.createSubscription RclInterfaces.Msg.Log topic!"qos_event_topic"
    (fun _ => pure ()) (QoS.reliable 10)
  let ev ← QoSEvent.onSubscription sub .requestedIncompatibleQos
    fun status => reported.set (some status)
  let ex ← Executor.create ctx
  ex.addSubscription sub
  ex.addEvent ev

  let pub ← node.createPublisher RclInterfaces.Msg.Log topic!"qos_event_topic"
    (QoS.bestEffort 10)

  let fired ← spinUntil ex (do return (← reported.get).isSome)
    (Duration.ofSeconds 15)
  check "the subscription is told its request cannot be met" fired
    "no incompatible-QoS event within 15s"
  match ← reported.get with
  | none => pure ()
  | some status =>
    check "the event counts the incompatible peer" (status.totalCount ≥ 1)
      s!"total was {status.totalCount}"

  ev.destroy
  pub.destroy
  sub.destroy
  node.destroy
  ctx.shutdown

def main : IO UInt32 := do
  IO.println "topic and timer integration tests"
  testPubSub
  testTimerRate
  testTimerOutlivesItsLocals
  testSimTime
  testQoSMismatch
  testGeneratedTypes
  testBytePayload
  testQoSEvents
  finish "topic"
