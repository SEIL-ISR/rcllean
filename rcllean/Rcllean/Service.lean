import RosidlRuntimeLean
import Rcllean.Destroyable
import Rcllean.Names
import Rcllean.Node
import Rcllean.QoS

/-!
# Services

A service is a request-response call.  `RosService` names the request and
response types together; `Rcllean.Client` is the calling side.
-/

namespace Rcllean.FFI

open RosidlRuntimeLean

-- C bindings

private opaque ServicePointed : NonemptyType
def Service : Type := ServicePointed.type
instance : Nonempty Service := ServicePointed.property

@[extern "rcllean_service_create"]
opaque serviceCreate (node : @& Node) (type : @& ServiceType)
    (name : @& String) (qos : @& QoS) : IO Service

/-- Take a pending request together with the header that routes its response
back: the caller's 16-byte writer GUID and the request's sequence number.
`none` when nothing is waiting. -/
@[extern "rcllean_service_take_request"]
opaque serviceTakeRequest {α : Type} (svc : @& Service) :
    IO (Option (ByteArray × Int64 × α))

/-- Answer the request identified by the header. -/
@[extern "rcllean_service_send_response"]
opaque serviceSendResponse {α : Type} (svc : @& Service) (guid : @& ByteArray)
    (sequence : Int64) (msg : @& α) : IO Unit

@[extern "rcllean_service_destroy"]
opaque serviceDestroy (svc : @& Service) : IO Unit

@[extern "rcllean_service_name"]
opaque serviceName (svc : @& Service) : IO String

end Rcllean.FFI

namespace Rcllean

open RosidlRuntimeLean

/-- Answers requests for a service. -/
structure Service (S : Type) [RosService S] where
  /-- The underlying `rcl_service_t`.  Internal. -/
  handle : FFI.Service
  /-- Computes a response from a request.  The executor runs it. -/
  handler : RosService.Request S → IO (RosService.Response S)

namespace Service

variable {S : Type} [inst : RosService S]

/-- The service name after remapping. -/
def name (svc : Service S) : IO String :=
  FFI.serviceName svc.handle

/-- Take one request if there is one, returning the work of answering it.

Conversion happens here, on the thread that waited; the handler and the
response are in the returned action, which an executor may run anywhere. -/
def takeRequest (svc : Service S) : IO (Option (IO Unit)) := do
  match ← FFI.serviceTakeRequest (α := RosService.Request S) svc.handle with
  | none => return none
  | some (guid, seq, req) => return some do
      let resp ← svc.handler req
      FFI.serviceSendResponse svc.handle guid seq resp

/-- Whether the service has not been destroyed. -/
def isValid (svc : Service S) : IO Bool :=
  FFI.handleIsValid svc.handle

/-- Release the service now rather than at collection.  Idempotent. -/
def destroy (svc : Service S) : IO Unit :=
  FFI.serviceDestroy svc.handle

end Service

namespace Node

/-- Offer a service.  The handler runs when an executor processes a request. -/
def createService (node : Node) (S : Type) [RosService S] (name : TopicName)
    (handler : RosService.Request S → IO (RosService.Response S))
    (qos : QoSProfile := QoS.servicesDefault) : IO (Service S) := do
  let type ← RosService.typeSupport (S := S)
  return ⟨← FFI.serviceCreate node.handle type name.toString (← qos.toFFI),
    handler⟩

end Node

end Rcllean
