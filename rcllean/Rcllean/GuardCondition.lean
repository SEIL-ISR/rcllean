import Rcllean.Destroyable
import Rcllean.Context

/-!
# Guard conditions

A guard condition wakes a wait set on demand: from another thread, or from a
signal handler.  `rcl_shutdown` does not interrupt a blocked `rcl_wait`, so an
executor registers one as its context's shutdown guard.
-/

namespace Rcllean.FFI

-- C bindings

private opaque GuardConditionPointed : NonemptyType
def GuardCondition : Type := GuardConditionPointed.type
instance : Nonempty GuardCondition := GuardConditionPointed.property

@[extern "rcllean_guard_condition_create"]
opaque guardConditionCreate (ctx : @& Context) : IO GuardCondition

@[extern "rcllean_guard_condition_trigger"]
opaque guardConditionTrigger (gc : @& GuardCondition) : IO Unit

/-- Register a guard condition to be triggered when the context shuts down.

`rcl_shutdown` does not interrupt an already blocked wait, so without this an
executor with no timer stays in `rcl_wait` after Ctrl-C. -/
@[extern "rcllean_context_add_shutdown_guard"]
opaque contextAddShutdownGuard (ctx : @& Context) (gc : @& GuardCondition) :
    IO Unit

end Rcllean.FFI

namespace Rcllean

/-- Wakes a wait set on demand, interrupting a blocked executor from another
thread or a signal handler. -/
structure GuardCondition where
  /-- The underlying `rcl_guard_condition_t`.  Internal. -/
  handle : FFI.GuardCondition

namespace GuardCondition

def create (ctx : Context) : IO GuardCondition :=
  return ⟨← FFI.guardConditionCreate ctx.handle⟩

/-- Wake anything waiting on this condition. -/
def trigger (gc : GuardCondition) : IO Unit :=
  FFI.guardConditionTrigger gc.handle

/-- Whether the guard condition has not been destroyed. -/
def isValid (gc : GuardCondition) : IO Bool :=
  FFI.handleIsValid gc.handle

end GuardCondition

end Rcllean
