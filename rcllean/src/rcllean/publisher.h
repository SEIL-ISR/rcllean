// A publisher on a node, with the generated type record its messages convert
// through.

#ifndef RCLLEAN_PUBLISHER_H
#define RCLLEAN_PUBLISHER_H

#include <lean/lean.h>

#include <rcl/publisher.h>
#include <rosidl_runtime_lean/type_support.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // parent: the node
  rcl_publisher_t publisher;
  // Static storage in the interface package; not owned.
  const rosidl_runtime_lean_message_type_t *type;
} rcllean_publisher_t;

static inline rcllean_publisher_t *rcllean_to_publisher(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_publisher_t, o);
}

#endif // RCLLEAN_PUBLISHER_H
