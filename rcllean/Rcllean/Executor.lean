import Rcllean.WaitSet
import Rcllean.CallbackGroup

/-!
# Executors

An executor turns incoming messages, service requests and elapsed timers into
callback calls; rcl is asked what is ready and never holds a callback.  Each
pass waits, takes the data of every ready entity on the waiting thread, then
hands the callback to a dispatch function: `spin` runs it inline,
`spinMultiThreaded` on its own task under the entity's group.  Entities are
added explicitly; a destroyed one is dropped on the next pass.
-/

namespace Rcllean

open RosidlRuntimeLean

/-- Which kind of wait set slot an entity occupies.  A wait set is sized per
kind, so the breakdown matters, not just the total. -/
inductive WaitableKind where
  | subscription | timer | guardCondition | client | service | event
deriving DecidableEq, Repr, Inhabited, BEq

/-- Something an executor can wait on and run.

rcl entities are not thread safe, so taking is separate from running: `take`
runs on the thread that waited and returns the user's callback with its data
already in hand.  Entities of different message types are different Lean
types, so this holds closures rather than a sum type. -/
structure Waitable where
  kind : WaitableKind
  /-- Which callbacks this one may overlap with. -/
  group : CallbackGroup
  /-- Whether the entity still exists.  A destroyed one is dropped. -/
  isValid : IO Bool
  /-- Register in a wait set, returning the slot index. -/
  add : WaitSet → IO Nat
  /-- If the slot is ready, take the data and return the callback to run.
  Called only on the waiting thread. -/
  takeIfReady : WaitSet → Nat → IO (Option (IO Unit))

namespace Waitable

/-- Wrap a subscription.  One message per readiness, so a busy topic cannot
starve the rest of the executor. -/
def ofSubscription {α : Type} [RosMessage α] (sub : Subscription α)
    (group : CallbackGroup) : Waitable :=
  { kind := .subscription, group
    isValid := sub.isValid
    add := fun ws => ws.addSubscription sub
    takeIfReady := fun ws idx => do
      if ← ws.subscriptionReady idx then
        if let some msg ← sub.take then
          return some (sub.callback msg)
      return none }

/-- Wrap a timer: call it when its period has elapsed. -/
def ofTimer (timer : Timer) (group : CallbackGroup) : Waitable :=
  { kind := .timer, group
    isValid := timer.isValid
    add := fun ws => ws.addTimer timer
    takeIfReady := fun ws idx => do
      if ← ws.timerReady idx then
        -- rcl_timer_call resets the period and must run on the waiting
        -- thread; only the user's callback is dispatched.
        if ← FFI.timerCall timer.handle then
          return some timer.callback
      return none }

/-- Wrap a service: take one request and hand back the work of answering it. -/
def ofService {S : Type} [RosService S] (svc : Service S)
    (group : CallbackGroup) : Waitable :=
  { kind := .service, group
    isValid := svc.isValid
    add := fun ws => ws.addService svc
    takeIfReady := fun ws idx => do
      if ← ws.serviceReady idx then
        return ← svc.takeRequest
      return none }

/-- Wrap a client: take one response and complete the future waiting on it. -/
def ofClient {S : Type} [RosService S] (cli : Client S)
    (group : CallbackGroup) : Waitable :=
  { kind := .client, group
    isValid := cli.isValid
    add := fun ws => ws.addClient cli
    takeIfReady := fun ws idx => do
      if ← ws.clientReady idx then
        return ← cli.takeResponse
      return none }

/-- Wrap a quality of service event. -/
def ofEvent (ev : QoSEvent) (group : CallbackGroup) : Waitable :=
  { kind := .event, group
    isValid := ev.isValid
    add := fun ws => ws.addEvent ev
    takeIfReady := fun ws idx => do
      if ← ws.eventReady idx then
        if let some status ← ev.take then
          return some (ev.callback status)
      return none }

/-- Wrap a guard condition: run an action when it is triggered. -/
def ofGuardCondition (gc : GuardCondition) (action : IO Unit)
    (group : CallbackGroup) : Waitable :=
  { kind := .guardCondition, group
    isValid := gc.isValid
    add := fun ws => ws.addGuardCondition gc
    takeIfReady := fun ws idx => do
      if ← ws.guardConditionReady idx then
        return some action
      return none }

end Waitable

/-- Runs callbacks for a set of entities. -/
structure Executor where
  context : Context
  /-- Everything being waited on, each under a registration number so a
  destroyed entity can be dropped without disturbing concurrent additions. -/
  waitables : IO.Ref (Array (Nat × Waitable))
  nextId : IO.Ref Nat
  /-- The group entities join when none is given; mutually exclusive. -/
  defaultGroup : CallbackGroup
  /-- The wait set, reused across passes and resized only when the entity
  counts change. -/
  waitSet : WaitSet
  /-- Triggered when the entity set changes, when a callback group frees up,
  and on context shutdown, so a blocked wait returns instead of hanging. -/
  wakeup : GuardCondition

namespace Executor

/-- Tally the wait set slots a set of entities needs, plus one guard condition
for the executor's own wakeup. -/
def capacityFor (waitables : Array Waitable) : WaitSetCapacity := Id.run do
  let mut cap : WaitSetCapacity := { guardConditions := 1 }
  for w in waitables do
    cap := match w.kind with
      | .subscription => { cap with subscriptions := cap.subscriptions + 1 }
      | .timer => { cap with timers := cap.timers + 1 }
      | .guardCondition => { cap with guardConditions := cap.guardConditions + 1 }
      | .client => { cap with clients := cap.clients + 1 }
      | .service => { cap with services := cap.services + 1 }
      | .event => { cap with events := cap.events + 1 }
  return cap

/-- Create an executor with no entities. -/
def create (ctx : Context) : IO Executor := do
  let wakeup ← GuardCondition.create ctx
  -- rcl_shutdown alone does not wake a blocking wait, and an executor with no
  -- timer waits indefinitely.
  FFI.contextAddShutdownGuard ctx.handle wakeup.handle
  return { context := ctx
           waitables := ← IO.mkRef #[]
           nextId := ← IO.mkRef 0
           defaultGroup := ← CallbackGroup.mutuallyExclusive
           waitSet := ← WaitSet.create ctx
           wakeup }

/-- Add something to run.  Wakes a blocked wait so the addition takes effect
immediately. -/
def add (ex : Executor) (w : Waitable) : IO Unit := do
  let id ← ex.nextId.modifyGet fun n => (n, n + 1)
  ex.waitables.modify (·.push (id, w))
  ex.wakeup.trigger

def addSubscription {α : Type} [RosMessage α] (ex : Executor)
    (sub : Subscription α) (group : Option CallbackGroup := none) : IO Unit :=
  ex.add (Waitable.ofSubscription sub (group.getD ex.defaultGroup))

def addTimer (ex : Executor) (timer : Timer)
    (group : Option CallbackGroup := none) : IO Unit :=
  ex.add (Waitable.ofTimer timer (group.getD ex.defaultGroup))

def addService {S : Type} [RosService S] (ex : Executor) (svc : Service S)
    (group : Option CallbackGroup := none) : IO Unit :=
  ex.add (Waitable.ofService svc (group.getD ex.defaultGroup))

def addClient {S : Type} [RosService S] (ex : Executor) (cli : Client S)
    (group : Option CallbackGroup := none) : IO Unit :=
  ex.add (Waitable.ofClient cli (group.getD ex.defaultGroup))

def addEvent (ex : Executor) (ev : QoSEvent)
    (group : Option CallbackGroup := none) : IO Unit :=
  ex.add (Waitable.ofEvent ev (group.getD ex.defaultGroup))

/-- The registered entities that still exist, forgetting the rest. -/
private def liveWaitables (ex : Executor) : IO (Array Waitable) := do
  let all ← ex.waitables.get
  let dead ← all.filterMapM fun (id, w) =>
    return if ← w.isValid then none else some id
  if !dead.isEmpty then
    ex.waitables.modify (·.filter fun (id, _) => !dead.contains id)
  return all.filterMap fun (id, w) => if dead.contains id then none else some w

/-- One pass: wait for something to be ready, then hand each ready callback
to `dispatch` together with its group.  Returns `false` if the wait timed out
or the context shut down. -/
private def pass (ex : Executor) (timeout : Option Duration)
    (dispatch : CallbackGroup → IO Unit → IO Unit) : IO Bool := do
  -- An entity whose mutually exclusive group is busy stays out of the wait
  -- set; it would report ready on every pass until the callback finished.
  -- The group wakes the executor when it frees up.
  let eligible ← (← ex.liveWaitables).filterM (·.group.canRun)

  ex.waitSet.ensureCapacity (capacityFor eligible)
  ex.waitSet.clear
  let wakeupIdx ← ex.waitSet.addGuardCondition ex.wakeup
  let mut slots : Array Nat := Array.mkEmpty eligible.size
  for w in eligible do
    slots := slots.push (← w.add ex.waitSet)

  if !(← ex.waitSet.wait timeout) then
    return false
  -- The wait may have returned because the context shut down.  Every entity
  -- is invalid then, so dispatching would raise from rcl.
  if !(← ex.context.ok) then
    return false
  -- rcl clears a guard condition once the wait that observed it returns, so
  -- no draining is needed beyond this read.
  let _ ← ex.waitSet.guardConditionReady wakeupIdx

  -- Several entities of one group can be ready in one pass, so the group is
  -- rechecked before each take.
  for (w, slot) in eligible.zip slots do
    if ← w.group.canRun then
      if let some action ← w.takeIfReady ex.waitSet slot then
        dispatch w.group action
  return true

/-- Wait once and run whatever became ready, one callback at a time.

`none` blocks until something happens; `some 0` polls.  Returns `false` if the
wait timed out with nothing ready.  An exception in a callback propagates to
the caller. -/
def spinOnce (ex : Executor) (timeout : Option Duration := none) : IO Bool :=
  ex.pass timeout fun group action => group.withMembership action

/-- Run until the context shuts down, which Ctrl-C does. -/
partial def spin (ex : Executor) : IO Unit := do
  while ← ex.context.ok do
    let _ ← ex.spinOnce

/-- Run whatever is ready right now, without blocking. -/
def spinSome (ex : Executor) : IO Unit := do
  let _ ← ex.spinOnce (some Duration.zero)

/-- Spin until a future completes, then return its value; `none` on timeout or
shutdown.

A service response arrives only because the executor processes it, so the
waiting thread has to be the one spinning. -/
partial def spinUntilComplete (ex : Executor) (f : Future α)
    (timeout : Option Duration := none) : IO (Option α) := do
  let clock ← Clock.steady
  let deadline ← timeout.mapM fun d => return (← clock.now) + d
  while !(← f.isDone) do
    if !(← ex.context.ok) then
      return none
    let remaining ← deadline.mapM fun t => return t - (← clock.now)
    if remaining.any (·.nanos ≤ 0) then
      return none
    let _ ← ex.spinOnce remaining
  return some (← f.get)

/-- Spin with callbacks running on worker threads.

The wait and every take still run on this thread, so rcl entities are never
used from two threads at once.  A mutually exclusive group's callback is held
back while one of its callbacks runs; a reentrant group's are dispatched
immediately.  An exception in a callback is logged and does not stop the
executor. -/
partial def spinMultiThreaded (ex : Executor) : IO Unit := do
  let logger : Logger := ⟨"rcllean.executor"⟩
  -- Tasks are kept so the executor can wait for them at shutdown; finished
  -- ones are dropped on each pass.
  let running ← IO.mkRef (#[] : Array (Task (Except IO.Error Unit)))
  while ← ex.context.ok do
    let _ ← ex.pass none fun group action => do
      group.enter
      let task ← IO.asTask (prio := Task.Priority.dedicated) do
        try
          action
        catch e =>
          logger.error s!"callback failed: {e}"
        finally
          group.leave
          -- The group's entities were left out of the wait set while it
          -- was busy.
          ex.wakeup.trigger
      running.modify (·.push task)
    let stillRunning ← (← running.get).filterM fun t => return !(← IO.hasFinished t)
    running.set stillRunning
  -- Let callbacks already running finish before returning.
  for t in ← running.get do
    let _ ← IO.wait t

end Executor

end Rcllean
