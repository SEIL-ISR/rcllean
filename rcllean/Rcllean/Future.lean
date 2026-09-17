import Rcllean.Time

/-!
# Futures

A `Future` is a value that arrives later, such as a service response.

Nothing here blocks: the thread that would wait is usually the one that has to
spin the executor for the answer to arrive.  Wait with
`Executor.spinUntilComplete`.
-/

namespace Rcllean

/-- The value once it has arrived, and what to run when it does.  One
reference, so completing and registering a callback cannot interleave. -/
structure Future.State (α : Type) where
  value : Option (Except IO.Error α) := none
  callbacks : Array (Except IO.Error α → IO Unit) := #[]

/-- A value that will be supplied later. -/
structure Future (α : Type) where
  state : IO.Ref (Future.State α)

namespace Future

def create : IO (Future α) :=
  return ⟨← IO.mkRef {}⟩

/-- Whether the value has arrived, successfully or not. -/
def isDone (f : Future α) : IO Bool :=
  return (← f.state.get).value.isSome

/-- The value if it has arrived. -/
def peek (f : Future α) : IO (Option (Except IO.Error α)) :=
  return (← f.state.get).value

/-- Supply the value, running any callbacks.  A second completion is ignored,
so a late duplicate response cannot overwrite the first. -/
def complete (f : Future α) (value : Except IO.Error α) : IO Unit := do
  let callbacks ← f.state.modifyGet fun s =>
    if s.value.isSome then (#[], s)
    else (s.callbacks, { value := some value })
  for cb in callbacks do
    cb value

/-- The value; raises if it has not arrived.  Call after `isDone`. -/
def get (f : Future α) : IO α := do
  match ← f.peek with
  | none => throw (IO.userError "future is not complete yet")
  | some (.ok v) => return v
  | some (.error e) => throw e

/-- Run an action when the value arrives, or now if it already has. -/
def onComplete (f : Future α) (cb : Except IO.Error α → IO Unit) : IO Unit := do
  let arrived ← f.state.modifyGet fun s =>
    match s.value with
    | some v => (some v, s)
    | none => (none, { s with callbacks := s.callbacks.push cb })
  if let some v := arrived then
    cb v

/-- Complete the future with a failure; how a timed-out call is reported. -/
def fail (f : Future α) (message : String) : IO Unit :=
  f.complete (.error (IO.userError message))

end Future

end Rcllean
