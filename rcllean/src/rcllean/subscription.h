// A subscription on a node, with the generated type record its messages
// convert through and the buffer they are taken into.

#ifndef RCLLEAN_SUBSCRIPTION_H
#define RCLLEAN_SUBSCRIPTION_H

#include <lean/lean.h>

#include <rcl/subscription.h>
#include <rosidl_runtime_lean/type_support.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // parent: the node
  rcl_subscription_t subscription;
  // Static storage in the interface package; not owned.
  const rosidl_runtime_lean_message_type_t *type;
  // Reused across takes; `init` and `fini` bracket each one.
  void *buffer;
} rcllean_subscription_t;

static inline rcllean_subscription_t *rcllean_to_subscription(
    b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_subscription_t, o);
}

#endif // RCLLEAN_SUBSCRIPTION_H
