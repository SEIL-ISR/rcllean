import Rcllean
import Check

/-!
Unit tests.  These must never require a running ROS 2 network or a sourced ROS
install; anything that does belongs in `tests/Integration`.
-/

open Rcllean

def testDuration : IO Unit := do
  IO.println "Duration"
  checkEq "ofSeconds" (Duration.ofSeconds 2).nanos 2000000000
  checkEq "ofMillis" (Duration.ofMillis 250).nanos 250000000
  checkEq "ofMicros" (Duration.ofMicros 5).nanos 5000
  checkEq "add" (Duration.ofMillis 10 + Duration.ofMillis 5).nanos 15000000
  checkEq "sub" (Duration.ofMillis 10 - Duration.ofMillis 5).nanos 5000000
  checkEq "neg" (-Duration.ofMillis 10).nanos (-10000000)
  check "lt" (Duration.ofMillis 1 < Duration.ofMillis 2)
  check "le refl" (Duration.ofMillis 1 ≤ Duration.ofMillis 1)
  -- Float round-trip is approximate; check it lands within a nanosecond.
  let d := Duration.ofFloatSeconds 1.5
  check "ofFloatSeconds" ((d.toFloatSeconds - 1.5).abs < 1e-9)

def testTime : IO Unit := do
  IO.println "Time"
  let t : Time .steadyTime := Time.ofNanos 1000
  checkEq "add duration" (t + Duration.ofNanos 500).nanos 1500
  checkEq "sub duration" (t - Duration.ofNanos 500).nanos 500
  checkEq "diff" ((t + Duration.ofNanos 500) - t).nanos 500
  checkEq "diff self is zero" (t - t) Duration.zero
  check "lt" (t < t + Duration.ofNanos 1)

def testClockType : IO Unit := do
  IO.println "ClockType"
  for ct in [ClockType.uninitialized, .rosTime, .systemTime, .steadyTime] do
    checkEq s!"round-trip {repr ct}" (ClockType.ofUInt8? ct.toUInt8) (some ct)
  checkEq "rosTime code matches rcl_clock_type_t" ClockType.rosTime.toUInt8 1
  checkEq "unknown code" (ClockType.ofUInt8? 9) none

def testLogSeverity : IO Unit := do
  IO.println "LogSeverity"
  for s in [LogSeverity.unset, .debug, .info, .warn, .error, .fatal] do
    checkEq s!"round-trip {repr s}" (LogSeverity.ofUInt32? s.toUInt32) (some s)
  -- The numbers are rcutils' own; a mismatch would silently misfilter logs.
  checkEq "debug" LogSeverity.debug.toUInt32 10
  checkEq "info" LogSeverity.info.toUInt32 20
  checkEq "warn" LogSeverity.warn.toUInt32 30
  checkEq "error" LogSeverity.error.toUInt32 40
  checkEq "fatal" LogSeverity.fatal.toUInt32 50

def testQoS : IO Unit := do
  IO.println "QoS"
  -- The policy codes are rmw's own; a mismatch would silently create a profile
  -- other than the one asked for.
  checkEq "reliable code" ReliabilityPolicy.reliable.toUInt8 1
  checkEq "best effort code" ReliabilityPolicy.bestEffort.toUInt8 2
  checkEq "transient local code" DurabilityPolicy.transientLocal.toUInt8 1
  checkEq "volatile code" DurabilityPolicy.volatile.toUInt8 2
  checkEq "keep last code" HistoryPolicy.keepLast.toUInt8 1
  checkEq "keep all code" HistoryPolicy.keepAll.toUInt8 2
  -- rmw skips 2 for liveliness; the removed policy still occupies the slot.
  checkEq "manual by topic code" LivelinessPolicy.manualByTopic.toUInt8 3

  for p in [ReliabilityPolicy.systemDefault, .reliable, .bestEffort, .unknown,
            .bestAvailable] do
    checkEq s!"reliability round-trip {repr p}"
      (ReliabilityPolicy.ofUInt8? p.toUInt8) (some p)
  for p in [DurabilityPolicy.systemDefault, .transientLocal, .volatile,
            .unknown, .bestAvailable] do
    checkEq s!"durability round-trip {repr p}"
      (DurabilityPolicy.ofUInt8? p.toUInt8) (some p)
  for p in [LivelinessPolicy.systemDefault, .automatic, .manualByTopic,
            .unknown, .bestAvailable] do
    checkEq s!"liveliness round-trip {repr p}"
      (LivelinessPolicy.ofUInt8? p.toUInt8) (some p)

  -- The presets must match rmw's, or a Lean node will not connect to a C++ one
  -- that asked for the "same" profile.
  checkEq "default depth" QoS.default.depth 10
  checkEq "sensor data depth" QoS.sensorData.depth 5
  checkEq "sensor data is best effort" QoS.sensorData.reliability
    ReliabilityPolicy.bestEffort
  checkEq "parameters depth" QoS.parameters.depth 1000

  IO.println "QoS compatibility"
  check "identical profiles always match" (QoS.compatible QoS.default QoS.default)
  check "reliable publisher reaches best-effort subscription"
    (QoS.compatible (QoS.reliable 10) (QoS.bestEffort 10))
  check "best-effort publisher does not reach reliable subscription"
    (QoS.compatible (QoS.bestEffort 10) (QoS.reliable 10) == false)
  check "transient local publisher reaches volatile subscription"
    (QoS.compatible (QoS.transientLocal 1) QoS.default)
  check "volatile publisher does not satisfy a transient local subscription"
    (QoS.compatible QoS.default (QoS.transientLocal 1) == false)
  check "sensor data publisher does not reach a default subscription"
    (QoS.compatible QoS.sensorData QoS.default == false)
  -- A publisher promising a message every 100ms satisfies a request for one
  -- every 200ms, but not the other way round.
  check "a tighter deadline offer satisfies a looser request"
    (QoS.deadlineCompatible (some (Duration.ofMillis 100))
                            (some (Duration.ofMillis 200)))
  check "a looser deadline offer does not satisfy a tighter request"
    (QoS.deadlineCompatible (some (Duration.ofMillis 200))
                            (some (Duration.ofMillis 100)) == false)
  check "no deadline offered fails a deadline request"
    (QoS.deadlineCompatible none (some (Duration.ofMillis 100)) == false)
  check "no deadline requested accepts anything"
    (QoS.deadlineCompatible (some (Duration.ofMillis 100)) none)

def testNames : IO Unit := do
  IO.println "names"
  -- The rules as Lean states them; the integration suite checks the same
  -- predicates against rcl's and rmw's on a corpus of awkward names.
  -- Expanded names, the rmw rules.
  check "an absolute topic is a valid expanded name"
    (isValidFullTopicName "/robot/cmd_vel")
  check "a hidden topic is valid" (isValidFullTopicName "/_hidden")
  check "a relative topic is not expanded" (!isValidFullTopicName "cmd_vel")
  check "a trailing slash is not" (!isValidFullTopicName "/cmd_vel/")
  check "an empty token is not" (!isValidFullTopicName "/a//b")
  check "a leading digit is not" (!isValidFullTopicName "/1abc")
  check "the root is a namespace" (isValidNamespace "/")
  check "the root is not a topic" (!isValidFullTopicName "/")
  check "a node name has no slashes" (!isValidNodeName "/foo")

  -- Names as written, the rcl rules.
  check "a relative name is what a user writes" (isValidTopicName "cmd_vel")
  check "a private name is fine" (isValidTopicName "~/status")
  check "a bare tilde is fine" (isValidTopicName "~")
  check "an absolute name is fine" (isValidTopicName "/cmd_vel")
  check "a node substitution is fine" (isValidTopicName "{node}/state")
  check "a trailing slash is not" (!isValidTopicName "cmd_vel/")
  check "a dash is not" (!isValidTopicName "/has-dash")
  check "a tilde in the middle is not" (!isValidTopicName "a/~/b")
  check "a tilde must be followed by a slash" (!isValidTopicName "~foo")
  check "an unmatched brace is not" (!isValidTopicName "{node")
  check "a doubled slash is not" (!isValidTopicName "a//b")
  check "only {node} expands, so only {node} is accepted"
    (!isValidTopicName "{ns}/x")

  checkEq "ofString? accepts a good name"
    ((TopicName.ofString? "chatter").map (·.toString)) (some "chatter")
  checkEq "ofString? rejects a bad name"
    ((TopicName.ofString? "chatter/").map (·.toString)) none
  checkEq "FullTopicName.ofString? wants an absolute name"
    ((FullTopicName.ofString? "chatter").map (·.toString)) none

  -- Expansion, which the integration suite also checks against rcl.
  checkEq "a relative name expands against the namespace"
    ((topic!"chatter".expand node!"talker" ns!"/robot").toString)
    "/robot/chatter"
  checkEq "the root namespace does not double the slash"
    ((topic!"chatter".expand node!"talker" Namespace.root).toString)
    "/chatter"
  checkEq "a private name expands to the node"
    ((topic!"~/status".expand node!"talker" Namespace.root).toString)
    "/talker/status"
  checkEq "a bare tilde is the node itself"
    ((topic!"~".expand node!"talker" ns!"/robot").toString) "/robot/talker"
  checkEq "an absolute name is left alone"
    ((topic!"/clock".expand node!"talker" ns!"/robot").toString) "/clock"
  checkEq "{node} becomes the node name"
    ((topic!"a{node}b/x".expand node!"talker" Namespace.root).toString)
    "/atalkerb/x"

def testLifecycle : IO Unit := do
  IO.println "lifecycle state machine"
  checkEq "configure from unconfigured"
    (Lifecycle.step .unconfigured .configure) (some .inactive)
  checkEq "activate from inactive" (Lifecycle.step .inactive .activate)
    (some .active)
  checkEq "activate from unconfigured is refused"
    (Lifecycle.step .unconfigured .activate) none
  checkEq "nothing leaves finalized" (Lifecycle.available .finalized) []
  for s in Lifecycle.PrimaryState.all do
    for t in [Lifecycle.TransitionId.configure, .cleanup, .activate,
              .deactivate, .shutdown] do
      checkEq s!"available and step agree on {t} from {s}"
        (Lifecycle.step s t).isSome ((Lifecycle.available s).contains t)
  -- Wire codes are lifecycle_msgs's own.
  checkEq "shutdown from active is code 7"
    (Lifecycle.TransitionId.shutdown.toUInt8 .active) 7
  checkEq "code 3 is activate" (Lifecycle.TransitionId.ofUInt8? 3)
    (some .activate)

def main : IO UInt32 := do
  IO.println "unit tests"
  testDuration
  testTime
  testClockType
  testLogSeverity
  testQoS
  testNames
  testLifecycle
  let n ← failures.get
  if n == 0 then
    IO.println "all unit tests passed"
    return 0
  else
    IO.println s!"{n} unit test(s) failed"
    return 1
