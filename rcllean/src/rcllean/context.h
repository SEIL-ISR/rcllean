// The rcl context: the root of every handle tree, and the owner of the guard
// conditions woken when it shuts down.

#ifndef RCLLEAN_CONTEXT_H
#define RCLLEAN_CONTEXT_H

#include <lean/lean.h>
#include <stdbool.h>

#include <rcl/context.h>
#include <rcl/guard_condition.h>
#include <rcl/init_options.h>

#include "destroyable.h"

#define RCLLEAN_MAX_SHUTDOWN_GUARDS 32

typedef struct {
  rcllean_hdr hdr;
  rcl_context_t context;
  rcl_init_options_t init_options;
  bool init_options_valid;
  // Guard conditions to trigger on shutdown.  rcl_shutdown does not interrupt
  // a blocked rcl_wait, so without these an executor with no timer stays
  // blocked after Ctrl-C.  Each guard is already a child of this context and
  // removes itself here in its own fini.
  rcl_guard_condition_t *shutdown_guards[RCLLEAN_MAX_SHUTDOWN_GUARDS];
  size_t shutdown_guard_count;
  // Parameter overrides from the command line: a copy this context owns,
  // fetched on first use.
  void *param_overrides;  // rcl_params_t *, or NULL
  bool param_overrides_fetched;
} rcllean_context_t;

static inline rcllean_context_t *rcllean_to_context(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_context_t, o);
}

// Every context's shutdown-guard list is covered by one lock: the shutdown
// paths here walk a list while guard_condition.c adds to and removes from it.
void rcllean_context_guards_lock(void);
void rcllean_context_guards_unlock(void);

// Shut a context down and wake everything registered for its shutdown.  The
// signal thread calls this; a context that is already down is left alone.
void rcllean_context_signal_shutdown(rcllean_context_t *c);

#endif // RCLLEAN_CONTEXT_H
