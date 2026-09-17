import Rcllean.Duration

/-!
# Quality of service

A `QoSProfile` is the contract between a publisher and a subscription: how
reliably messages are delivered, whether late joiners see old ones, how deep
the queue is, and what deadlines apply.  Profiles that do not match never
connect and say nothing about it; `QoS.compatible` states the DDS
request-versus-offer rules as a predicate to evaluate beforehand.
-/

namespace Rcllean.FFI

-- C bindings

private opaque QoSPointed : NonemptyType
/-- An `rmw_qos_profile_t`. -/
def QoS : Type := QoSPointed.type
instance : Nonempty QoS := QoSPointed.property

/-- Build an rmw QoS profile.  Durations of zero mean "middleware default",
which is how rmw encodes an absent deadline or lifespan. -/
@[extern "rcllean_qos_create"]
opaque qosCreate (history : UInt8) (depth : UInt64) (reliability : UInt8)
    (durability : UInt8) (deadlineNs : Int64) (lifespanNs : Int64)
    (liveliness : UInt8) (leaseNs : Int64)
    (avoidRosNamespaceConventions : Bool) : IO QoS

end Rcllean.FFI

namespace Rcllean

/-- How much history to keep.  Values match `rmw_qos_history_policy_e`. -/
inductive HistoryPolicy where
  | systemDefault | keepLast | keepAll | unknown
deriving DecidableEq, Repr, Inhabited, BEq

/-- Delivery guarantee.  Values match `rmw_qos_reliability_policy_e`. -/
inductive ReliabilityPolicy where
  | systemDefault
  /-- Retry until delivered. -/
  | reliable
  /-- Send once and move on. -/
  | bestEffort
  | unknown
  /-- Match whatever the other side offers. -/
  | bestAvailable
deriving DecidableEq, Repr, Inhabited, BEq

/-- Whether late-joining subscriptions receive previously published messages.
Values match `rmw_qos_durability_policy_e`. -/
inductive DurabilityPolicy where
  | systemDefault
  /-- The publisher keeps messages for subscriptions that join later. -/
  | transientLocal
  /-- Messages are gone once sent. -/
  | volatile
  | unknown
  | bestAvailable
deriving DecidableEq, Repr, Inhabited, BEq

/-- How liveliness is asserted.  Values match `rmw_qos_liveliness_policy_e`. -/
inductive LivelinessPolicy where
  | systemDefault
  /-- The middleware asserts liveliness on the node's behalf. -/
  | automatic
  /-- The publisher asserts liveliness itself. -/
  | manualByTopic
  | unknown
  | bestAvailable
deriving DecidableEq, Repr, Inhabited, BEq

namespace HistoryPolicy
def toUInt8 : HistoryPolicy → UInt8
  | .systemDefault => 0 | .keepLast => 1 | .keepAll => 2 | .unknown => 3
def ofUInt8? : UInt8 → Option HistoryPolicy
  | 0 => some .systemDefault | 1 => some .keepLast | 2 => some .keepAll
  | 3 => some .unknown | _ => none
@[simp] theorem ofUInt8?_toUInt8 (p : HistoryPolicy) :
    ofUInt8? p.toUInt8 = some p := by cases p <;> rfl
end HistoryPolicy

namespace ReliabilityPolicy
def toUInt8 : ReliabilityPolicy → UInt8
  | .systemDefault => 0 | .reliable => 1 | .bestEffort => 2
  | .unknown => 3 | .bestAvailable => 4
def ofUInt8? : UInt8 → Option ReliabilityPolicy
  | 0 => some .systemDefault | 1 => some .reliable | 2 => some .bestEffort
  | 3 => some .unknown | 4 => some .bestAvailable | _ => none
@[simp] theorem ofUInt8?_toUInt8 (p : ReliabilityPolicy) :
    ofUInt8? p.toUInt8 = some p := by cases p <;> rfl
end ReliabilityPolicy

namespace DurabilityPolicy
def toUInt8 : DurabilityPolicy → UInt8
  | .systemDefault => 0 | .transientLocal => 1 | .volatile => 2
  | .unknown => 3 | .bestAvailable => 4
def ofUInt8? : UInt8 → Option DurabilityPolicy
  | 0 => some .systemDefault | 1 => some .transientLocal | 2 => some .volatile
  | 3 => some .unknown | 4 => some .bestAvailable | _ => none
@[simp] theorem ofUInt8?_toUInt8 (p : DurabilityPolicy) :
    ofUInt8? p.toUInt8 = some p := by cases p <;> rfl
end DurabilityPolicy

namespace LivelinessPolicy
/-- `manualByTopic` is 3, not 2: rmw reserves 2 for a policy that was removed. -/
def toUInt8 : LivelinessPolicy → UInt8
  | .systemDefault => 0 | .automatic => 1 | .manualByTopic => 3
  | .unknown => 4 | .bestAvailable => 5
def ofUInt8? : UInt8 → Option LivelinessPolicy
  | 0 => some .systemDefault | 1 => some .automatic | 3 => some .manualByTopic
  | 4 => some .unknown | 5 => some .bestAvailable | _ => none
@[simp] theorem ofUInt8?_toUInt8 (p : LivelinessPolicy) :
    ofUInt8? p.toUInt8 = some p := by cases p <;> rfl
end LivelinessPolicy

/-- A quality-of-service profile. -/
structure QoSProfile where
  history : HistoryPolicy := .keepLast
  /-- How many messages `keepLast` retains.  Ignored by `keepAll`. -/
  depth : Nat := 10
  reliability : ReliabilityPolicy := .reliable
  durability : DurabilityPolicy := .volatile
  /-- Maximum expected gap between messages.  `none` means no deadline. -/
  deadline : Option Duration := none
  /-- How long a published message stays valid.  `none` means forever. -/
  lifespan : Option Duration := none
  liveliness : LivelinessPolicy := .systemDefault
  /-- How long a publisher may go without asserting liveliness. -/
  livelinessLeaseDuration : Option Duration := none
  /-- Bypass the ROS topic name prefixing, to talk to native DDS peers. -/
  avoidRosNamespaceConventions : Bool := false
deriving Repr, Inhabited, BEq

/-- Turn a Lean profile into the rmw one the middleware wants. -/
def QoSProfile.toFFI (q : QoSProfile) : IO FFI.QoS :=
  FFI.qosCreate q.history.toUInt8 (UInt64.ofNat q.depth)
    q.reliability.toUInt8 q.durability.toUInt8
    (q.deadline.map (·.nanos) |>.getD 0)
    (q.lifespan.map (·.nanos) |>.getD 0)
    q.liveliness.toUInt8
    (q.livelinessLeaseDuration.map (·.nanos) |>.getD 0)
    q.avoidRosNamespaceConventions

namespace QoS

/-- The default profile: reliable, volatile, keep the last 10.  Matches
`rmw_qos_profile_default`. -/
def default : QoSProfile := {}

/-- For high-rate sensor streams, where a fresh message beats a complete
history.  Matches `rmw_qos_profile_sensor_data`. -/
def sensorData : QoSProfile :=
  { history := .keepLast, depth := 5, reliability := .bestEffort,
    durability := .volatile }

/-- The profile services use.  Matches `rmw_qos_profile_services_default`. -/
def servicesDefault : QoSProfile :=
  { history := .keepLast, depth := 10, reliability := .reliable,
    durability := .volatile }

/-- The profile parameter services use.  Matches `rmw_qos_profile_parameters`. -/
def parameters : QoSProfile :=
  { history := .keepLast, depth := 1000, reliability := .reliable,
    durability := .volatile }

/-- The profile `/parameter_events` uses. -/
def parameterEvents : QoSProfile :=
  { history := .keepLast, depth := 1000, reliability := .reliable,
    durability := .volatile }

/-- Defer every policy to the middleware's own defaults. -/
def systemDefault : QoSProfile :=
  { history := .systemDefault, depth := 10, reliability := .systemDefault,
    durability := .systemDefault, liveliness := .systemDefault }

/-- Keep the last `n` messages, reliably. -/
def keepLast (n : Nat) : QoSProfile := { default with depth := n }

/-- Reliable delivery with a queue of `n`. -/
def reliable (n : Nat := 10) : QoSProfile :=
  { default with reliability := .reliable, depth := n }

/-- Fire and forget, with a queue of `n`. -/
def bestEffort (n : Nat := 10) : QoSProfile :=
  { default with reliability := .bestEffort, depth := n }

/-- Reliable and durable: late joiners receive the last `n` messages.  Used by
latched topics such as `/map` and `/tf_static`. -/
def transientLocal (n : Nat := 1) : QoSProfile :=
  { default with durability := .transientLocal, depth := n }

/-! ## Compatibility

DDS matches a publisher's offer against a subscription's request: they connect
only if the offer is at least as strong as the request, policy by policy.  A
`systemDefault` or `bestAvailable` policy is resolved by the middleware, so it
is treated as compatible here.
-/

/-- Whether a policy value is resolved by the middleware rather than fixed. -/
private def deferred (isSystemDefault isBestAvailable : Bool) : Bool :=
  isSystemDefault || isBestAvailable

/-- Reliable satisfies any request; best effort satisfies only best effort. -/
def reliabilityCompatible (offered requested : ReliabilityPolicy) : Bool :=
  match offered, requested with
  | .systemDefault, _ | _, .systemDefault => true
  | .bestAvailable, _ | _, .bestAvailable => true
  | .unknown, _ | _, .unknown => true
  | .reliable, _ => true
  | .bestEffort, .bestEffort => true
  | .bestEffort, .reliable => false

/-- Transient local satisfies any request; volatile satisfies only volatile. -/
def durabilityCompatible (offered requested : DurabilityPolicy) : Bool :=
  match offered, requested with
  | .systemDefault, _ | _, .systemDefault => true
  | .bestAvailable, _ | _, .bestAvailable => true
  | .unknown, _ | _, .unknown => true
  | .transientLocal, _ => true
  | .volatile, .volatile => true
  | .volatile, .transientLocal => false

/-- A deadline offer must be no longer than the request: a message every 100ms
satisfies a request for one every 200ms, not the reverse.  An offered `none` is
no promise and satisfies only a request of `none`. -/
def deadlineCompatible (offered requested : Option Duration) : Bool :=
  match requested, offered with
  | none, _ => true
  | some _, none => false
  | some r, some o => o.nanos ≤ r.nanos

/-- Manual liveliness satisfies an automatic request, but not the reverse. -/
def livelinessCompatible (offered requested : LivelinessPolicy) : Bool :=
  match offered, requested with
  | .systemDefault, _ | _, .systemDefault => true
  | .bestAvailable, _ | _, .bestAvailable => true
  | .unknown, _ | _, .unknown => true
  | .manualByTopic, _ => true
  | .automatic, .automatic => true
  | .automatic, .manualByTopic => false

/-- Whether a publisher with profile `pub` will connect to a subscription with
profile `sub`. -/
def compatible (pub sub : QoSProfile) : Bool :=
  reliabilityCompatible pub.reliability sub.reliability &&
  durabilityCompatible pub.durability sub.durability &&
  deadlineCompatible pub.deadline sub.deadline &&
  livelinessCompatible pub.liveliness sub.liveliness &&
  deadlineCompatible pub.livelinessLeaseDuration sub.livelinessLeaseDuration

/-! ### What the rules guarantee -/

/-- A publisher and subscription with the same profile always connect. -/
theorem compatible_self (q : QoSProfile) : compatible q q = true := by
  cases q with | mk h d rel dur dl ls liv lease avoid =>
  simp only [compatible, reliabilityCompatible, durabilityCompatible,
             deadlineCompatible, livelinessCompatible]
  cases rel <;> cases dur <;> cases liv <;>
    cases dl <;> cases lease <;> simp

/-- A reliable publisher connects to a best-effort subscription. -/
theorem reliable_offers_bestEffort :
    reliabilityCompatible .reliable .bestEffort = true := rfl

/-- A best-effort publisher does not connect to a reliable subscription; the
most common silent-topic bug in ROS 2. -/
theorem bestEffort_refuses_reliable :
    reliabilityCompatible .bestEffort .reliable = false := rfl

/-- Sensor-data publishers do not reach default subscriptions: the default
requests reliable delivery, sensor data offers best effort. -/
theorem sensorData_pub_default_sub_incompatible :
    compatible sensorData default = false := rfl

/-- A default publisher does reach a sensor-data subscription. -/
theorem default_pub_sensorData_sub_compatible :
    compatible default sensorData = true := rfl

/-- A transient-local publisher reaches a volatile subscription. -/
theorem transientLocal_pub_default_sub_compatible :
    compatible (transientLocal 1) default = true := rfl

/-- A volatile publisher does not satisfy a subscription that asks for history. -/
theorem volatile_pub_transientLocal_sub_incompatible :
    compatible default (transientLocal 1) = false := rfl

end QoS

end Rcllean
