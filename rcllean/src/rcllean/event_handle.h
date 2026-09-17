// A QoS event on a publisher or subscription.  The kind is stored because rcl
// reports every kind through one buffer whose layout differs per kind.

#ifndef RCLLEAN_EVENT_HANDLE_H
#define RCLLEAN_EVENT_HANDLE_H

#include <lean/lean.h>
#include <stdbool.h>
#include <stdint.h>

#include <rcl/event.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // parent: the publisher or subscription
  rcl_event_t event;
  bool on_publisher;
  uint8_t kind;  // rcl_publisher_event_type_t or rcl_subscription_event_type_t
} rcllean_event_t;

static inline rcllean_event_t *rcllean_to_event(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_event_t, o);
}

#endif // RCLLEAN_EVENT_HANDLE_H
