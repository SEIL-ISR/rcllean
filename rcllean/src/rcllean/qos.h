// An rmw QoS profile.  Passing it as a handle keeps the Lean structure's
// layout out of the C code.

#ifndef RCLLEAN_QOS_H
#define RCLLEAN_QOS_H

#include <lean/lean.h>

#include <rmw/types.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;
  rmw_qos_profile_t qos;
} rcllean_qos_t;

static inline rcllean_qos_t *rcllean_to_qos(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_qos_t, o);
}

#endif // RCLLEAN_QOS_H
