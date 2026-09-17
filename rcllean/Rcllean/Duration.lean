/-!
# Durations

`Duration` is a signed nanosecond count, matching `rcl_duration_value_t`.
-/

namespace Rcllean

/-- A signed span of time in nanoseconds. -/
structure Duration where
  nanos : Int64
deriving DecidableEq, Repr, Inhabited, BEq

namespace Duration

def zero : Duration := ⟨0⟩

def ofNanos (n : Int64) : Duration := ⟨n⟩
def ofMicros (n : Int64) : Duration := ⟨n * 1000⟩
def ofMillis (n : Int64) : Duration := ⟨n * 1000000⟩
def ofSeconds (n : Int64) : Duration := ⟨n * 1000000000⟩

/-- Build a duration from a fractional number of seconds. -/
def ofFloatSeconds (s : Float) : Duration := ⟨(s * 1e9).toInt64⟩

def toNanos (d : Duration) : Int64 := d.nanos
def toFloatSeconds (d : Duration) : Float := d.nanos.toFloat / 1e9

instance : Add Duration := ⟨fun a b => ⟨a.nanos + b.nanos⟩⟩
instance : Sub Duration := ⟨fun a b => ⟨a.nanos - b.nanos⟩⟩
instance : Neg Duration := ⟨fun a => ⟨-a.nanos⟩⟩
instance : LT Duration := ⟨fun a b => a.nanos < b.nanos⟩
instance : LE Duration := ⟨fun a b => a.nanos ≤ b.nanos⟩
instance (a b : Duration) : Decidable (a < b) :=
  inferInstanceAs (Decidable (a.nanos < b.nanos))
instance (a b : Duration) : Decidable (a ≤ b) :=
  inferInstanceAs (Decidable (a.nanos ≤ b.nanos))

instance : ToString Duration := ⟨fun d => s!"{d.toFloatSeconds}s"⟩

@[simp] theorem add_nanos (a b : Duration) : (a + b).nanos = a.nanos + b.nanos := rfl
@[simp] theorem sub_nanos (a b : Duration) : (a - b).nanos = a.nanos - b.nanos := rfl
@[simp] theorem zero_nanos : Duration.zero.nanos = 0 := rfl

end Duration

end Rcllean
