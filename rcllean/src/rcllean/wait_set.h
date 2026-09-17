// The wait set an executor blocks on: the entities it watches and which of
// them came back ready.

#ifndef RCLLEAN_WAIT_SET_H
#define RCLLEAN_WAIT_SET_H

#include <lean/lean.h>

#include <rcl/wait.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // parent: the context
  rcl_wait_set_t wait_set;
} rcllean_wait_set_t;

static inline rcllean_wait_set_t *rcllean_to_wait_set(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_wait_set_t, o);
}

#endif // RCLLEAN_WAIT_SET_H
