// A guard condition: the way to wake a blocked wait set by hand, and the
// registration that lets a context's shutdown do the waking.

#ifndef RCLLEAN_GUARD_CONDITION_H
#define RCLLEAN_GUARD_CONDITION_H

#include <lean/lean.h>

#include <rcl/guard_condition.h>

#include "context.h"
#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // parent: the context
  rcl_guard_condition_t guard_condition;
} rcllean_guard_condition_t;

static inline rcllean_guard_condition_t *rcllean_to_guard_condition(
    b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_guard_condition_t, o);
}

// Drop a guard condition from a context's shutdown list, before the rcl
// object it points at goes away.
void rcllean_context_remove_shutdown_guard(rcllean_context_t *c,
                                           const rcl_guard_condition_t *gc);

#endif // RCLLEAN_GUARD_CONDITION_H
