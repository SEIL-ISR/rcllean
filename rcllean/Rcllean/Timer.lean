import Rcllean.Destroyable
import Rcllean.Clock
import Rcllean.Context

/-!
# Timers

A timer fires on a period measured by a clock.  Under simulated time that
clock follows `/clock`, so timers track the simulation rather than the wall.

No callback is registered with rcl: the executor sees a ready timer and calls
the Lean callback itself.
-/

namespace Rcllean.FFI

-- C bindings

private opaque TimerPointed : NonemptyType
def Timer : Type := TimerPointed.type
instance : Nonempty Timer := TimerPointed.property

@[extern "rcllean_timer_create"]
opaque timerCreate (ctx : @& Context) (clock : @& Clock) (periodNs : Int64)
    (autostart : Bool) : IO Timer

@[extern "rcllean_timer_is_ready"]
opaque timerIsReady (timer : @& Timer) : IO Bool

/-- Mark the timer as fired.  Returns `false` if it was cancelled. -/
@[extern "rcllean_timer_call"]
opaque timerCall (timer : @& Timer) : IO Bool

@[extern "rcllean_timer_time_until_next_call"]
opaque timerTimeUntilNextCall (timer : @& Timer) : IO Int64

@[extern "rcllean_timer_cancel"]
opaque timerCancel (timer : @& Timer) : IO Unit

@[extern "rcllean_timer_reset"]
opaque timerReset (timer : @& Timer) : IO Unit

@[extern "rcllean_timer_is_canceled"]
opaque timerIsCanceled (timer : @& Timer) : IO Bool

/-- Set a new period, returning the old one in nanoseconds. -/
@[extern "rcllean_timer_set_period"]
opaque timerSetPeriod (timer : @& Timer) (periodNs : Int64) : IO Int64

@[extern "rcllean_timer_destroy"]
opaque timerDestroy (timer : @& Timer) : IO Unit

end Rcllean.FFI

namespace Rcllean

/-- Runs a callback on a period. -/
structure Timer where
  /-- The underlying `rcl_timer_t`.  Internal. -/
  handle : FFI.Timer
  /-- What to run when the period elapses. -/
  callback : IO Unit

namespace Timer

/-- Create a timer on a clock.  `autostart := false` creates it cancelled, to
be started later with `reset`.

The timer holds both the context and the clock: rcl reads the clock while the
timer lives, and tearing the context down destroys the timer first. -/
def create (ctx : Context) (clock : Clock ct) (period : Duration)
    (callback : IO Unit) (autostart : Bool := true) : IO Timer := do
  let handle ← FFI.timerCreate ctx.handle clock.handle period.nanos autostart
  return ⟨handle, callback⟩

/-- Whether the period has elapsed. -/
def isReady (timer : Timer) : IO Bool :=
  FFI.timerIsReady timer.handle

/-- Run the callback and reset the period.  Does nothing if cancelled. -/
def call (timer : Timer) : IO Unit := do
  if ← FFI.timerCall timer.handle then
    timer.callback

/-- Time until the next firing; negative if overdue. -/
def timeUntilNextCall (timer : Timer) : IO Duration :=
  return ⟨← FFI.timerTimeUntilNextCall timer.handle⟩

/-- Stop the timer.  It stops being ready until `reset`. -/
def cancel (timer : Timer) : IO Unit :=
  FFI.timerCancel timer.handle

/-- Restart the timer, beginning a fresh period now. -/
def reset (timer : Timer) : IO Unit :=
  FFI.timerReset timer.handle

def isCanceled (timer : Timer) : IO Bool :=
  FFI.timerIsCanceled timer.handle

/-- Change the period, returning the old one. -/
def setPeriod (timer : Timer) (period : Duration) : IO Duration :=
  return ⟨← FFI.timerSetPeriod timer.handle period.nanos⟩

/-- Whether the timer has not been destroyed. -/
def isValid (timer : Timer) : IO Bool :=
  FFI.handleIsValid timer.handle

/-- Release the timer now rather than at collection.  Idempotent. -/
def destroy (timer : Timer) : IO Unit :=
  FFI.timerDestroy timer.handle

end Timer

end Rcllean
