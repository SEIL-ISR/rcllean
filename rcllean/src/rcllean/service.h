// A service server on a node: the generated service record, and the buffer
// requests are taken into.

#ifndef RCLLEAN_SERVICE_H
#define RCLLEAN_SERVICE_H

#include <lean/lean.h>

#include <rcl/service.h>
#include <rosidl_runtime_lean/type_support.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // parent: the node
  rcl_service_t service;
  // Static storage in the interface package; not owned.
  const rosidl_runtime_lean_service_type_t *type;
  // Requests are taken on one thread, so one buffer serves; responses may be
  // sent from several and get a buffer each.
  void *request_buffer;
} rcllean_service_t;

static inline rcllean_service_t *rcllean_to_service(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_service_t, o);
}

#endif // RCLLEAN_SERVICE_H
