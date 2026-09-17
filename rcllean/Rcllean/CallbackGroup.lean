import Rcllean.Time

/-!
# Callback groups

A callback group says whether the callbacks of the entities in it may run at
the same time.  A **mutually exclusive** group (the default) runs one at a
time, so its callbacks can share state without locking; a **reentrant** group
lets them overlap, which suits blocking work.

Groups only matter under a multi-threaded executor.
-/

namespace Rcllean

/-- How the callbacks in a group may be scheduled. -/
inductive CallbackGroupKind where
  /-- One callback at a time.  Safe to share state between them. -/
  | mutuallyExclusive
  /-- Callbacks may overlap.  Shared state needs its own protection. -/
  | reentrant
deriving DecidableEq, Repr, Inhabited, BEq

/-- A group of entities scheduled together.

`canRun` and `enter` both run on the executor's waiting thread, so the check
and the increment cannot interleave; only `leave` runs on a worker. -/
structure CallbackGroup where
  kind : CallbackGroupKind
  /-- Callbacks currently running.  A mutually exclusive group refuses to
  start another while this is above zero. -/
  running : IO.Ref Nat

namespace CallbackGroup

def mutuallyExclusive : IO CallbackGroup :=
  return { kind := .mutuallyExclusive, running := ← IO.mkRef 0 }

def reentrant : IO CallbackGroup :=
  return { kind := .reentrant, running := ← IO.mkRef 0 }

/-- Whether a callback from this group may start now. -/
def canRun (g : CallbackGroup) : IO Bool := do
  match g.kind with
  | .reentrant => return true
  | .mutuallyExclusive => return (← g.running.get) == 0

/-- Record that a callback has started. -/
def enter (g : CallbackGroup) : IO Unit :=
  g.running.modify (· + 1)

/-- Record that a callback has finished. -/
def leave (g : CallbackGroup) : IO Unit :=
  g.running.modify (· - 1)

/-- Run `act` as a member of the group; the count is restored if it throws. -/
def withMembership (g : CallbackGroup) (act : IO Unit) : IO Unit := do
  g.enter
  try act finally g.leave

end CallbackGroup

end Rcllean
