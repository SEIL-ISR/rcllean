import Rcllean.Time

/-!
# Clocks

A `Clock ct` reads one ROS time source.  The source is carried in the type,
so the `Time ct` values it produces cannot be mixed with another source's.
-/

namespace Rcllean.FFI

-- C bindings

private opaque ClockPointed : NonemptyType
/-- An `rcl_clock_t`. -/
def Clock : Type := ClockPointed.type
instance : Nonempty Clock := ClockPointed.property

/-- `rcl_clock_init`.  The code is the `rcl_clock_type_t` value. -/
@[extern "rcllean_clock_create"]
opaque clockCreate (clockType : UInt8) : IO Clock

/-- Nanoseconds since the clock's epoch. -/
@[extern "rcllean_clock_now"]
opaque clockNow (clock : @& Clock) : IO Int64

@[extern "rcllean_clock_type"]
opaque clockType (clock : @& Clock) : IO UInt8

@[extern "rcllean_clock_is_valid"]
opaque clockIsValid (clock : @& Clock) : IO Bool

@[extern "rcllean_clock_enable_ros_time_override"]
opaque clockEnableRosTimeOverride (clock : @& Clock) (enable : Bool) : IO Unit

@[extern "rcllean_clock_set_ros_time_override"]
opaque clockSetRosTimeOverride (clock : @& Clock) (nanos : Int64) : IO Unit

@[extern "rcllean_clock_ros_time_override_is_enabled"]
opaque clockRosTimeOverrideIsEnabled (clock : @& Clock) : IO Bool

end Rcllean.FFI

namespace Rcllean

/-- A clock reading a particular time source. -/
structure Clock (ct : ClockType) where
  /-- The underlying `rcl_clock_t`.  Internal. -/
  handle : FFI.Clock

namespace Clock

/-- Create a clock for the given time source. -/
def create (ct : ClockType) : IO (Clock ct) := do
  return ⟨← FFI.clockCreate ct.toUInt8⟩

/-- A monotonic clock, unaffected by system clock changes. -/
def steady : IO (Clock .steadyTime) := create .steadyTime

/-- A wall-clock time source. -/
def system : IO (Clock .systemTime) := create .systemTime

/-- A simulation-aware clock; reports wall time until a time source binds it
to `/clock`. -/
def ros : IO (Clock .rosTime) := create .rosTime

/-- The current time. -/
def now (clock : Clock ct) : IO (Time ct) := do
  return ⟨← FFI.clockNow clock.handle⟩

/-- Whether the clock can produce times. -/
def isValid (clock : Clock ct) : IO Bool :=
  FFI.clockIsValid clock.handle

/-- Put a ROS clock under external control, so `now` reports the last
`setRosTimeOverride` value.  `use_sim_time` turns this on. -/
def enableRosTimeOverride (clock : Clock .rosTime) (enable : Bool := true) :
    IO Unit :=
  FFI.clockEnableRosTimeOverride clock.handle enable

/-- Set the time a ROS clock reports while the override is enabled. -/
def setRosTimeOverride (clock : Clock .rosTime) (t : Time .rosTime) : IO Unit :=
  FFI.clockSetRosTimeOverride clock.handle t.nanos

/-- Whether this clock is currently driven by an external time source. -/
def rosTimeOverrideIsEnabled (clock : Clock .rosTime) : IO Bool :=
  FFI.clockRosTimeOverrideIsEnabled clock.handle

end Clock

/-- Sleep for a duration; non-positive durations return immediately.

Wall-clock only: ignores simulated time and is not interrupted by shutdown.
Use an executor wait for anything that must react to Ctrl-C. -/
def sleepFor (d : Duration) : IO Unit := do
  if d.nanos > 0 then
    let millis := d.nanos / 1000000
    IO.sleep (UInt32.ofNat millis.toInt.toNat)

end Rcllean
