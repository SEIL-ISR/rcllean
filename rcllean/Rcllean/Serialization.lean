import RosidlRuntimeLean

/-!
# Serialization

CDR bytes, the form a message takes on the wire.  Used for recording and
replay, and for anything that moves a message outside rcl.
-/

namespace Rcllean.FFI

open RosidlRuntimeLean

-- C bindings

/-- Serialize a message to the CDR bytes that go on the wire. -/
@[extern "rcllean_msg_serialize"]
opaque msgSerialize {α : Type} (type : @& MessageType) (msg : @& α) :
    IO ByteArray

/-- Turn CDR bytes back into a message. -/
@[extern "rcllean_msg_deserialize"]
opaque msgDeserialize {α : Type} (type : @& MessageType)
    (bytes : @& ByteArray) : IO α

end Rcllean.FFI

namespace Rcllean

open RosidlRuntimeLean

/-- Serialize a message to the bytes that go on the wire. -/
def serialize {α : Type} [RosMessage α] (msg : α) : IO ByteArray := do
  FFI.msgSerialize (← RosMessage.typeSupport (α := α)) msg

/-- Read a message back from wire bytes.  A value violating a field's bound
raises. -/
def deserialize (α : Type) [RosMessage α] (bytes : ByteArray) : IO α := do
  FFI.msgDeserialize (α := α) (← RosMessage.typeSupport (α := α)) bytes

end Rcllean
