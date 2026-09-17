import RosidlRuntimeLean
import Rcllean.Destroyable
import Rcllean.Names
import Rcllean.Node
import Rcllean.QoS

/-!
# Subscriptions

A `Subscription α` receives values of a Lean type with a `RosMessage`
instance.  A wire value violating a field's bound raises instead of being
handed on: the bytes come from another process, possibly built against a
different version of the interface.
-/

namespace Rcllean.FFI

open RosidlRuntimeLean

-- C bindings

private opaque SubscriptionPointed : NonemptyType
def Subscription : Type := SubscriptionPointed.type
instance : Nonempty Subscription := SubscriptionPointed.property

@[extern "rcllean_subscription_create"]
opaque subscriptionCreate (node : @& Node) (type : @& MessageType)
    (topic : @& String) (qos : @& QoS) : IO Subscription

/-- Take one message, or `none` if the queue is empty. -/
@[extern "rcllean_subscription_take"]
opaque subscriptionTake {α : Type} (sub : @& Subscription) : IO (Option α)

@[extern "rcllean_subscription_destroy"]
opaque subscriptionDestroy (sub : @& Subscription) : IO Unit

@[extern "rcllean_subscription_publisher_count"]
opaque subscriptionPublisherCount (sub : @& Subscription) : IO UInt64

@[extern "rcllean_subscription_topic_name"]
opaque subscriptionTopicName (sub : @& Subscription) : IO String

end Rcllean.FFI

namespace Rcllean

open RosidlRuntimeLean

/-- Receives messages of type `α` from a topic.  The handle keeps the node
alive. -/
structure Subscription (α : Type) [RosMessage α] where
  /-- The underlying `rcl_subscription_t`.  Internal. -/
  handle : FFI.Subscription
  /-- What to run for each message that arrives.  The executor calls it. -/
  callback : α → IO Unit

namespace Subscription

variable {α : Type} [inst : RosMessage α]

/-- Take one message if the queue has one. -/
def take (sub : Subscription α) : IO (Option α) :=
  FFI.subscriptionTake (α := α) sub.handle

/-- How many publishers are currently matched. -/
def publisherCount (sub : Subscription α) : IO Nat :=
  return (← FFI.subscriptionPublisherCount sub.handle).toNat

/-- The topic name after remapping. -/
def topicName (sub : Subscription α) : IO String :=
  FFI.subscriptionTopicName sub.handle

/-- Whether the subscription has not been destroyed.  An executor drops a
destroyed one on its next pass. -/
def isValid (sub : Subscription α) : IO Bool :=
  FFI.handleIsValid sub.handle

/-- Release the subscription now rather than at collection.  Idempotent. -/
def destroy (sub : Subscription α) : IO Unit :=
  FFI.subscriptionDestroy sub.handle

end Subscription

namespace Node

/-- Create a subscription on `topic`.  The callback runs when an executor
processes the message; creating a subscription does not start anything. -/
def createSubscription (node : Node) (α : Type) [RosMessage α]
    (topic : TopicName) (callback : α → IO Unit)
    (qos : QoSProfile := QoS.default) : IO (Subscription α) := do
  let type ← RosMessage.typeSupport (α := α)
  let h ← FFI.subscriptionCreate node.handle type topic.toString (← qos.toFFI)
  return ⟨h, callback⟩

end Node

end Rcllean
