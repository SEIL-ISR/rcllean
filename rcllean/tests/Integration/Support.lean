import Rcllean

/-!
The harness shared by the integration tests: a failure counter, `check`, and
waits that poll a condition against a deadline.  Discovery between endpoints is
asynchronous, so a fixed sleep is a race.
-/

namespace Rcllean.Test

/-- Failed checks so far, reported as the process exit code. -/
initialize failures : IO.Ref Nat ← IO.mkRef 0

def pass (name : String) : IO Unit := IO.println s!"  ok   {name}"

def fail (name detail : String) : IO Unit := do
  IO.println s!"  FAIL {name}: {detail}"
  failures.modify (· + 1)

def check (name : String) (ok : Bool) (detail : String := "") : IO Unit :=
  if ok then pass name else fail name detail

def checkEq [BEq α] [Repr α] (name : String) (actual expected : α) : IO Unit :=
  check name (actual == expected) s!"got {repr actual}, expected {repr expected}"

/-- Spin an executor until a condition holds, giving up after `limit`. -/
def spinUntil (ex : Executor) (cond : IO Bool)
    (limit : Duration := Duration.ofSeconds 10) : IO Bool := do
  let clock ← Clock.steady
  let deadline := (← clock.now) + limit
  while !(← cond) do
    if (← clock.now) > deadline then
      return false
    let _ ← ex.spinOnce (some (Duration.ofMillis 50))
  return true

/-- Poll a condition without an executor, giving up after `limit`. -/
def waitUntil (cond : IO Bool) (limit : Duration := Duration.ofSeconds 10) :
    IO Bool := do
  let clock ← Clock.steady
  let deadline := (← clock.now) + limit
  while !(← cond) do
    if (← clock.now) > deadline then
      return false
    sleepFor (Duration.ofMillis 20)
  return true

/-- Print the verdict and turn the failure count into an exit code. -/
def finish (suite : String) : IO UInt32 := do
  let n ← failures.get
  if n == 0 then
    IO.println s!"all {suite} tests passed"
    return 0
  IO.println s!"{n} {suite} test(s) failed"
  return 1

end Rcllean.Test
