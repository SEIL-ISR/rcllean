import Rcllean.Duration

/-!
# Time

`Time` is indexed by the clock that produced it, so subtracting a system time
from a ROS time is a type error rather than a runtime exception.  `ClockType`
is that index; `Clock` is in `Rcllean.Clock`.
-/

namespace Rcllean

/-- Which time source a `Time` came from.  The numeric values match
`rcl_clock_type_t`. -/
inductive ClockType where
  /-- An uninitialized clock; `rcl_clock_get_now` on one fails. -/
  | uninitialized
  /-- Simulation-aware time: wall time until `use_sim_time` binds the clock
  to `/clock`. -/
  | rosTime
  /-- Wall-clock time, which can jump when the system clock is set. -/
  | systemTime
  /-- Monotonic time, suitable for measuring elapsed intervals. -/
  | steadyTime
deriving DecidableEq, Repr, Inhabited, BEq

namespace ClockType

def toUInt8 : ClockType → UInt8
  | .uninitialized => 0
  | .rosTime => 1
  | .systemTime => 2
  | .steadyTime => 3

def ofUInt8? : UInt8 → Option ClockType
  | 0 => some .uninitialized
  | 1 => some .rosTime
  | 2 => some .systemTime
  | 3 => some .steadyTime
  | _ => none

@[simp] theorem ofUInt8?_toUInt8 (c : ClockType) : ofUInt8? c.toUInt8 = some c := by
  cases c <;> rfl

end ClockType

/-- A point in time, tagged with the clock that produced it.  Values are
nanoseconds since that clock's epoch. -/
structure Time (ct : ClockType) where
  nanos : Int64
deriving DecidableEq, Repr, Inhabited, BEq

namespace Time

def zero : Time ct := ⟨0⟩

def ofNanos (n : Int64) : Time ct := ⟨n⟩
def toNanos (t : Time ct) : Int64 := t.nanos
def toFloatSeconds (t : Time ct) : Float := t.nanos.toFloat / 1e9

/-- Advance a time by a duration. -/
def add (t : Time ct) (d : Duration) : Time ct := ⟨t.nanos + d.nanos⟩

/-- Step a time back by a duration. -/
def subDuration (t : Time ct) (d : Duration) : Time ct := ⟨t.nanos - d.nanos⟩

/-- The span between two times.  The index enforces one clock for both. -/
def diff (a b : Time ct) : Duration := ⟨a.nanos - b.nanos⟩

instance : HAdd (Time ct) Duration (Time ct) := ⟨add⟩
instance : HSub (Time ct) Duration (Time ct) := ⟨subDuration⟩
instance : HSub (Time ct) (Time ct) Duration := ⟨diff⟩
instance : LT (Time ct) := ⟨fun a b => a.nanos < b.nanos⟩
instance : LE (Time ct) := ⟨fun a b => a.nanos ≤ b.nanos⟩
instance (a b : Time ct) : Decidable (a < b) :=
  inferInstanceAs (Decidable (a.nanos < b.nanos))
instance (a b : Time ct) : Decidable (a ≤ b) :=
  inferInstanceAs (Decidable (a.nanos ≤ b.nanos))

instance : ToString (Time ct) := ⟨fun t => s!"{t.toFloatSeconds}"⟩

@[simp] theorem add_nanos (t : Time ct) (d : Duration) :
    (t.add d).nanos = t.nanos + d.nanos := rfl

@[simp] theorem diff_nanos (a b : Time ct) : (a.diff b).nanos = a.nanos - b.nanos := rfl

/-- Adding a duration and then subtracting it again is the identity. -/
theorem add_subDuration (t : Time ct) (d : Duration) :
    (t.add d).subDuration d = t := by
  have : t.nanos + d.nanos - d.nanos = t.nanos := by
    simp [Int64.add_sub_cancel]
  simp [add, subDuration, this]

/-- The span from a time to itself is zero. -/
theorem diff_self (t : Time ct) : t.diff t = Duration.zero := by
  simp [diff, Duration.zero, Int64.sub_self]

end Time

end Rcllean
