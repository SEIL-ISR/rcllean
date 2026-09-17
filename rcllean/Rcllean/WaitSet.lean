import Rcllean.Subscription
import Rcllean.Timer
import Rcllean.GuardCondition
import Rcllean.Service
import Rcllean.Client
import Rcllean.EventHandle

/-!
# Wait sets

A wait set is the one place an rcllean program blocks: fill it with entities,
wait, then ask which are ready.  Executors are built on it.

rcl's wait set holds only pointers into the entities added to it, so the Lean
wait set holds the entities themselves from `add` until `clear`; otherwise one
could be collected, and its rcl object freed, before the wait reads it.
-/

namespace Rcllean.FFI

-- C bindings

private opaque WaitSetPointed : NonemptyType
def WaitSet : Type := WaitSetPointed.type
instance : Nonempty WaitSet := WaitSetPointed.property

@[extern "rcllean_wait_set_create"]
opaque waitSetCreate (ctx : @& Context) (subscriptions : UInt64)
    (guardConditions : UInt64) (timers : UInt64) (clients : UInt64)
    (services : UInt64) (events : UInt64) : IO WaitSet

@[extern "rcllean_wait_set_resize"]
opaque waitSetResize (ws : @& WaitSet) (subscriptions : UInt64)
    (guardConditions : UInt64) (timers : UInt64) (clients : UInt64)
    (services : UInt64) (events : UInt64) : IO Unit

@[extern "rcllean_wait_set_clear"]
opaque waitSetClear (ws : @& WaitSet) : IO Unit

/-- Block until something is ready.  A negative timeout waits forever, zero
polls.  Returns `false` on timeout, which is not an error. -/
@[extern "rcllean_wait_set_wait"]
opaque waitSetWait (ws : @& WaitSet) (timeoutNs : Int64) : IO Bool

/-- Each `add` returns the slot to query readiness with after the wait.  Slots
are valid only for the wait that produced them. -/
@[extern "rcllean_wait_set_add_subscription"]
opaque waitSetAddSubscription (ws : @& WaitSet) (sub : @& Subscription) :
    IO UInt64

@[extern "rcllean_wait_set_add_timer"]
opaque waitSetAddTimer (ws : @& WaitSet) (timer : @& Timer) : IO UInt64

@[extern "rcllean_wait_set_add_guard_condition"]
opaque waitSetAddGuardCondition (ws : @& WaitSet) (gc : @& GuardCondition) :
    IO UInt64

@[extern "rcllean_wait_set_add_service"]
opaque waitSetAddService (ws : @& WaitSet) (svc : @& Service) : IO UInt64

@[extern "rcllean_wait_set_add_client"]
opaque waitSetAddClient (ws : @& WaitSet) (cli : @& Client) : IO UInt64

@[extern "rcllean_wait_set_add_event"]
opaque waitSetAddEvent (ws : @& WaitSet) (ev : @& Event) : IO UInt64

@[extern "rcllean_wait_set_subscription_ready"]
opaque waitSetSubscriptionReady (ws : @& WaitSet) (index : UInt64) : IO Bool

@[extern "rcllean_wait_set_timer_ready"]
opaque waitSetTimerReady (ws : @& WaitSet) (index : UInt64) : IO Bool

@[extern "rcllean_wait_set_guard_condition_ready"]
opaque waitSetGuardConditionReady (ws : @& WaitSet) (index : UInt64) : IO Bool

@[extern "rcllean_wait_set_service_ready"]
opaque waitSetServiceReady (ws : @& WaitSet) (index : UInt64) : IO Bool

@[extern "rcllean_wait_set_client_ready"]
opaque waitSetClientReady (ws : @& WaitSet) (index : UInt64) : IO Bool

@[extern "rcllean_wait_set_event_ready"]
opaque waitSetEventReady (ws : @& WaitSet) (index : UInt64) : IO Bool

end Rcllean.FFI

namespace Rcllean

open RosidlRuntimeLean

/-- Entities a wait set can hold, counted by kind. -/
structure WaitSetCapacity where
  subscriptions : Nat := 0
  guardConditions : Nat := 0
  timers : Nat := 0
  clients : Nat := 0
  services : Nat := 0
  events : Nat := 0
deriving Repr, Inhabited, BEq

/-- A handle the wait set is holding a pointer to. -/
inductive Held where
  | subscription (h : FFI.Subscription)
  | timer (h : FFI.Timer)
  | guardCondition (h : FFI.GuardCondition)
  | service (h : FFI.Service)
  | client (h : FFI.Client)
  | event (h : FFI.Event)

/-- A set of entities to wait on. -/
structure WaitSet where
  /-- The underlying `rcl_wait_set_t`.  Internal. -/
  handle : FFI.WaitSet
  /-- What the wait set is sized for, so it is resized only when the entity
  counts change. -/
  capacity : IO.Ref WaitSetCapacity
  /-- Everything added since the last `clear`.  rcl keeps only pointers into
  these entities, so Lean could otherwise collect one before the wait reads
  it. -/
  held : IO.Ref (Array Held)

namespace WaitSet

def create (ctx : Context) (cap : WaitSetCapacity := {}) : IO WaitSet := do
  let handle ← FFI.waitSetCreate ctx.handle
    (UInt64.ofNat cap.subscriptions) (UInt64.ofNat cap.guardConditions)
    (UInt64.ofNat cap.timers) (UInt64.ofNat cap.clients)
    (UInt64.ofNat cap.services) (UInt64.ofNat cap.events)
  return ⟨handle, ← IO.mkRef cap, ← IO.mkRef #[]⟩

/-- Keep a handle alive until the next `clear`, returning its slot. -/
private def hold (ws : WaitSet) (h : Held) (slot : UInt64) : IO Nat := do
  ws.held.modify (·.push h)
  return slot.toNat

/-- Resize only if the requested capacity differs from the current one. -/
def ensureCapacity (ws : WaitSet) (cap : WaitSetCapacity) : IO Unit := do
  if (← ws.capacity.get) != cap then
    FFI.waitSetResize ws.handle
      (UInt64.ofNat cap.subscriptions) (UInt64.ofNat cap.guardConditions)
      (UInt64.ofNat cap.timers) (UInt64.ofNat cap.clients)
      (UInt64.ofNat cap.services) (UInt64.ofNat cap.events)
    ws.capacity.set cap

/-- Remove every entity, keeping the allocated capacity. -/
def clear (ws : WaitSet) : IO Unit := do
  FFI.waitSetClear ws.handle
  ws.held.set #[]

/-- Add a subscription, returning the slot to query readiness with.  The wait
set keeps it alive until `clear`. -/
def addSubscription {α : Type} [RosMessage α] (ws : WaitSet)
    (sub : Subscription α) : IO Nat := do
  ws.hold (.subscription sub.handle) (← FFI.waitSetAddSubscription ws.handle sub.handle)

def addTimer (ws : WaitSet) (timer : Timer) : IO Nat := do
  ws.hold (.timer timer.handle) (← FFI.waitSetAddTimer ws.handle timer.handle)

def addGuardCondition (ws : WaitSet) (gc : GuardCondition) : IO Nat := do
  ws.hold (.guardCondition gc.handle) (← FFI.waitSetAddGuardCondition ws.handle gc.handle)

def addService {S : Type} [RosService S] (ws : WaitSet) (svc : Service S) :
    IO Nat := do
  ws.hold (.service svc.handle) (← FFI.waitSetAddService ws.handle svc.handle)

def addClient {S : Type} [RosService S] (ws : WaitSet) (cli : Client S) :
    IO Nat := do
  ws.hold (.client cli.handle) (← FFI.waitSetAddClient ws.handle cli.handle)

/-- Block until an entity is ready or the timeout expires.  `none` waits
indefinitely, `some 0` polls; `false` means the wait timed out. -/
def wait (ws : WaitSet) (timeout : Option Duration := none) : IO Bool :=
  FFI.waitSetWait ws.handle (timeout.map (·.nanos) |>.getD (-1))

/-- Whether the subscription in this slot has a message waiting.  Slots are
valid only for the wait that produced them. -/
def subscriptionReady (ws : WaitSet) (index : Nat) : IO Bool :=
  FFI.waitSetSubscriptionReady ws.handle (UInt64.ofNat index)

def timerReady (ws : WaitSet) (index : Nat) : IO Bool :=
  FFI.waitSetTimerReady ws.handle (UInt64.ofNat index)

def guardConditionReady (ws : WaitSet) (index : Nat) : IO Bool :=
  FFI.waitSetGuardConditionReady ws.handle (UInt64.ofNat index)

def serviceReady (ws : WaitSet) (index : Nat) : IO Bool :=
  FFI.waitSetServiceReady ws.handle (UInt64.ofNat index)

def clientReady (ws : WaitSet) (index : Nat) : IO Bool :=
  FFI.waitSetClientReady ws.handle (UInt64.ofNat index)

def addEvent (ws : WaitSet) (ev : QoSEvent) : IO Nat := do
  ws.hold (.event ev.handle) (← FFI.waitSetAddEvent ws.handle ev.handle)

def eventReady (ws : WaitSet) (index : Nat) : IO Bool :=
  FFI.waitSetEventReady ws.handle (UInt64.ofNat index)

end WaitSet

end Rcllean
