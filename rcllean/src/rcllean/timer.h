// A periodic timer, driven by a clock and polled by the executor.

#ifndef RCLLEAN_TIMER_H
#define RCLLEAN_TIMER_H

#include <lean/lean.h>

#include <rcl/timer.h>

#include "destroyable.h"

// rcl_timer_fini finalizes a guard condition that belongs to the context, so
// the context is the parent and tears the timer down first.  The clock, which
// rcl reads for as long as the timer lives, is held by a second reference
// released in the timer's fini.
typedef struct {
  rcllean_hdr hdr;  // parent: the context
  rcl_timer_t timer;
  lean_object *clock;
} rcllean_timer_t;

static inline rcllean_timer_t *rcllean_to_timer(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_timer_t, o);
}

#endif // RCLLEAN_TIMER_H
