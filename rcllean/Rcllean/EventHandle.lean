import Rcllean.Destroyable
import Rcllean.Publisher
import Rcllean.Subscription

/-!
# Quality of service events

The middleware reports changes to a publisher's or subscription's contract:
a missed deadline, an incompatible peer profile, lost messages.

Mismatched profiles never connect and are otherwise silent.  `QoS.compatible`
predicts that before anything is created; these events report it afterwards,
including against nodes from other packages.
-/

namespace Rcllean.FFI

-- C bindings

private opaque EventPointed : NonemptyType
def Event : Type := EventPointed.type
instance : Nonempty Event := EventPointed.property

@[extern "rcllean_publisher_event_create"]
opaque publisherEventCreate (pub : @& Publisher) (eventType : UInt8) : IO Event

@[extern "rcllean_subscription_event_create"]
opaque subscriptionEventCreate (sub : @& Subscription) (eventType : UInt8) :
    IO Event

/-- Take an event's status: the running count and the change since it was last
read.  `none` when nothing has happened. -/
@[extern "rcllean_event_take"]
opaque eventTake (ev : @& Event) : IO (Option (Int32 × Int32))

@[extern "rcllean_event_destroy"]
opaque eventDestroy (ev : @& Event) : IO Unit

end Rcllean.FFI

namespace Rcllean

open RosidlRuntimeLean

/-- What a publisher can be told about.  Values match
`rcl_publisher_event_type_t`. -/
inductive PublisherEvent where
  /-- The publisher promised a message every so often and did not deliver. -/
  | offeredDeadlineMissed
  /-- The publisher failed to assert liveliness in time. -/
  | livelinessLost
  /-- A subscription asked for something this publisher does not offer, so the
  two did not connect. -/
  | offeredIncompatibleQos
  /-- A peer expects a different message type on this topic. -/
  | incompatibleType
  /-- A subscription connected or disconnected. -/
  | matched
deriving DecidableEq, Repr, Inhabited, BEq

/-- What a subscription can be told about.  Values match
`rcl_subscription_event_type_t`. -/
inductive SubscriptionEvent where
  /-- No message arrived within the deadline this subscription asked for. -/
  | requestedDeadlineMissed
  /-- A matched publisher's liveliness changed. -/
  | livelinessChanged
  /-- A publisher offers something this subscription cannot accept, so the two
  did not connect. -/
  | requestedIncompatibleQos
  /-- The middleware dropped messages before they reached this subscription. -/
  | messageLost
  | incompatibleType
  | matched
deriving DecidableEq, Repr, Inhabited, BEq

def PublisherEvent.toUInt8 : PublisherEvent → UInt8
  | .offeredDeadlineMissed => 0 | .livelinessLost => 1
  | .offeredIncompatibleQos => 2 | .incompatibleType => 3 | .matched => 4

def SubscriptionEvent.toUInt8 : SubscriptionEvent → UInt8
  | .requestedDeadlineMissed => 0 | .livelinessChanged => 1
  | .requestedIncompatibleQos => 2 | .messageLost => 3
  | .incompatibleType => 4 | .matched => 5

/-- A running count and how much of it is new since the last read.  For a
liveliness change the count is the number of live publishers. -/
structure EventStatus where
  totalCount : Int32
  totalCountChange : Int32
deriving Repr, Inhabited, BEq

/-- A subscription to one kind of quality of service event. -/
structure QoSEvent where
  /-- The underlying `rcl_event_t`.  Internal. -/
  handle : FFI.Event
  /-- What to run when the event fires. -/
  callback : EventStatus → IO Unit

namespace QoSEvent

/-- Watch for an event on a publisher. -/
def onPublisher {α : Type} [RosMessage α] (pub : Publisher α)
    (event : PublisherEvent) (callback : EventStatus → IO Unit) : IO QoSEvent := do
  return ⟨← FFI.publisherEventCreate pub.handle event.toUInt8, callback⟩

/-- Watch for an event on a subscription. -/
def onSubscription {α : Type} [RosMessage α] (sub : Subscription α)
    (event : SubscriptionEvent) (callback : EventStatus → IO Unit) :
    IO QoSEvent := do
  return ⟨← FFI.subscriptionEventCreate sub.handle event.toUInt8, callback⟩

/-- Take the event's status if it has fired. -/
def take (ev : QoSEvent) : IO (Option EventStatus) := do
  match ← FFI.eventTake ev.handle with
  | none => return none
  | some (total, change) => return some ⟨total, change⟩

/-- Whether the event has not been destroyed. -/
def isValid (ev : QoSEvent) : IO Bool :=
  FFI.handleIsValid ev.handle

/-- Release the event now rather than at collection.  Idempotent. -/
def destroy (ev : QoSEvent) : IO Unit :=
  FFI.eventDestroy ev.handle

end QoSEvent

end Rcllean
