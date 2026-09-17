/-!
# Destroyable handles

Every rcl object crosses the boundary as an opaque handle in `Rcllean.FFI`.
Release one by dropping the last reference (the C finalizer runs the matching `rcl_*_fini`) or by an
explicit, idempotent `destroy`.  Each handle holds a strong reference to its
parent and each parent lists its live children, so teardown runs child before
parent.
-/

namespace Rcllean.FFI

-- C bindings

/-- Whether a handle has not been destroyed.  Every handle type shares one
layout, so one entry point serves them all. -/
@[extern "rcllean_handle_is_valid"]
opaque handleIsValid {α : Type} (h : @& α) : IO Bool

end Rcllean.FFI
