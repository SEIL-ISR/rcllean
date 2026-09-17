import Rcllean.Service
import Rcllean.Future

/-!
# Service clients

Clients are asynchronous: `call` returns a `Future` at once, since the
response arrives only when an executor spins, usually on the calling thread.
-/

namespace Rcllean.FFI

open RosidlRuntimeLean

-- C bindings

private opaque ClientPointed : NonemptyType
def Client : Type := ClientPointed.type
instance : Nonempty Client := ClientPointed.property

@[extern "rcllean_client_create"]
opaque clientCreate (node : @& Node) (type : @& ServiceType) (name : @& String)
    (qos : @& QoS) : IO Client

/-- Send a request, returning its sequence number. -/
@[extern "rcllean_client_send_request"]
opaque clientSendRequest {α : Type} (cli : @& Client) (msg : @& α) : IO Int64

/-- Take a response along with the sequence number of the request it answers. -/
@[extern "rcllean_client_take_response"]
opaque clientTakeResponse {α : Type} (cli : @& Client) :
    IO (Option (Int64 × α))

@[extern "rcllean_client_service_is_available"]
opaque clientServiceIsAvailable (cli : @& Client) : IO Bool

@[extern "rcllean_client_destroy"]
opaque clientDestroy (cli : @& Client) : IO Unit

@[extern "rcllean_client_service_name"]
opaque clientServiceName (cli : @& Client) : IO String

end Rcllean.FFI

namespace Rcllean

open RosidlRuntimeLean

/-- Calls a service. -/
structure Client (S : Type) [RosService S] where
  /-- The underlying `rcl_client_t`.  Internal. -/
  handle : FFI.Client
  /-- Requests sent but not yet answered, by sequence number.  Several calls
  may be in flight; a response carries the number of its request. -/
  pending : IO.Ref (Array (Int64 × Future (RosService.Response S)))

namespace Client

variable {S : Type} [inst : RosService S]

/-- Send a request.  The future completes when an executor processes the
response, so something must be spinning. -/
def call (cli : Client S) (req : RosService.Request S) :
    IO (Future (RosService.Response S)) := do
  let seq ← FFI.clientSendRequest cli.handle req
  let fut ← Future.create
  cli.pending.modify (·.push (seq, fut))
  return fut

/-- Take one response if there is one, returning the completion of the future
waiting for it.  A response nobody is waiting for is dropped. -/
def takeResponse (cli : Client S) : IO (Option (IO Unit)) := do
  match ← FFI.clientTakeResponse (α := RosService.Response S) cli.handle with
  | none => return none
  | some (seq, resp) =>
    let waiting ← cli.pending.modifyGet fun pending =>
      ((pending.find? (·.1 == seq)).map (·.2), pending.filter (·.1 != seq))
    match waiting with
    | none => return some (pure ())
    | some fut => return some (fut.complete (.ok resp))

/-- Whether a server for this service is on the graph. -/
def serviceIsReady (cli : Client S) : IO Bool :=
  FFI.clientServiceIsAvailable cli.handle

/-- The service name after remapping. -/
def serviceName (cli : Client S) : IO String :=
  FFI.clientServiceName cli.handle

/-- Whether the client has not been destroyed. -/
def isValid (cli : Client S) : IO Bool :=
  FFI.handleIsValid cli.handle

/-- Release the client now rather than at collection.  Idempotent. -/
def destroy (cli : Client S) : IO Unit :=
  FFI.clientDestroy cli.handle

end Client

namespace Node

/-- Create a client for a service. -/
def createClient (node : Node) (S : Type) [RosService S] (name : TopicName)
    (qos : QoSProfile := QoS.servicesDefault) : IO (Client S) := do
  let type ← RosService.typeSupport (S := S)
  return ⟨← FFI.clientCreate node.handle type name.toString (← qos.toFFI),
    ← IO.mkRef #[]⟩

end Node

end Rcllean
