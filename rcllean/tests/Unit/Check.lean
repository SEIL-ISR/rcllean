
/-!
The unit tests' assertions.  Each prints a line and counts a failure; the count
becomes the process exit code.
-/

/-- Number of failed checks, reported as the process exit code. -/
initialize failures : IO.Ref Nat ← IO.mkRef 0

/-- Assert that a condition holds. -/
def check (name : String) (ok : Bool) : IO Unit := do
  if ok then
    IO.println s!"  ok   {name}"
  else
    IO.println s!"  FAIL {name}"
    failures.modify (· + 1)

/-- Assert that a value is the expected one, showing both when it is not. -/
def checkEq [BEq α] [Repr α] (name : String) (actual expected : α) : IO Unit := do
  if actual == expected then
    IO.println s!"  ok   {name}"
  else
    IO.println s!"  FAIL {name}: got {repr actual}, expected {repr expected}"
    failures.modify (· + 1)
