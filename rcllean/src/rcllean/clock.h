// An rcl clock: system, steady or ROS time, the time source a timer reads.

#ifndef RCLLEAN_CLOCK_H
#define RCLLEAN_CLOCK_H

#include <lean/lean.h>

#include <rcl/time.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // no parent
  rcl_clock_t clock;
} rcllean_clock_t;

static inline rcllean_clock_t *rcllean_to_clock(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_clock_t, o);
}

#endif // RCLLEAN_CLOCK_H
