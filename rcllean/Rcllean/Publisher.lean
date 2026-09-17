import RosidlRuntimeLean
import Rcllean.Destroyable
import Rcllean.Names
import Rcllean.Node
import Rcllean.QoS

/-!
# Publishers

A `Publisher α` sends values of a Lean type with a `RosMessage` instance.  The
conversion to the C struct is the interface package's generated code, reached
through the boxed type record.
-/

namespace Rcllean.FFI

open RosidlRuntimeLean

-- C bindings

private opaque PublisherPointed : NonemptyType
def Publisher : Type := PublisherPointed.type
instance : Nonempty Publisher := PublisherPointed.property

@[extern "rcllean_publisher_create"]
opaque publisherCreate (node : @& Node) (type : @& MessageType)
    (topic : @& String) (qos : @& QoS) : IO Publisher

/-- The message crosses as a boxed object; the generated accessors read it. -/
@[extern "rcllean_publisher_publish"]
opaque publisherPublish {α : Type} (pub : @& Publisher) (msg : @& α) : IO Unit

@[extern "rcllean_publisher_destroy"]
opaque publisherDestroy (pub : @& Publisher) : IO Unit

@[extern "rcllean_publisher_subscription_count"]
opaque publisherSubscriptionCount (pub : @& Publisher) : IO UInt64

@[extern "rcllean_publisher_topic_name"]
opaque publisherTopicName (pub : @& Publisher) : IO String

end Rcllean.FFI

namespace Rcllean

open RosidlRuntimeLean

/-- Sends messages of type `α` on a topic.  The handle keeps the node alive. -/
structure Publisher (α : Type) [RosMessage α] where
  /-- The underlying `rcl_publisher_t`.  Internal. -/
  handle : FFI.Publisher

namespace Publisher

variable {α : Type} [inst : RosMessage α]

/-- Send a message. -/
def publish (pub : Publisher α) (msg : α) : IO Unit :=
  FFI.publisherPublish pub.handle msg

/-- How many subscriptions are currently matched.  Zero means nobody is
listening or the QoS profiles are incompatible; `QoS.compatible` settles
which. -/
def subscriptionCount (pub : Publisher α) : IO Nat :=
  return (← FFI.publisherSubscriptionCount pub.handle).toNat

/-- The topic name after remapping. -/
def topicName (pub : Publisher α) : IO String :=
  FFI.publisherTopicName pub.handle

/-- Whether the publisher has not been destroyed. -/
def isValid (pub : Publisher α) : IO Bool :=
  FFI.handleIsValid pub.handle

/-- Release the publisher now rather than at collection.  Idempotent. -/
def destroy (pub : Publisher α) : IO Unit :=
  FFI.publisherDestroy pub.handle

end Publisher

namespace Node

/-- Create a publisher on `topic`.  The message type is given explicitly:
`node.createPublisher RosgraphMsgs.Msg.Clock topic!"clock"`.  rcl expands the
name against the node, so a relative or `~/private` name is fine. -/
def createPublisher (node : Node) (α : Type) [RosMessage α]
    (topic : TopicName) (qos : QoSProfile := QoS.default) :
    IO (Publisher α) := do
  let type ← RosMessage.typeSupport (α := α)
  let h ← FFI.publisherCreate node.handle type topic.toString (← qos.toFFI)
  return ⟨h⟩

end Node

end Rcllean
