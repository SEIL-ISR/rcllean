// A service client on a node: the generated service record, and the buffer
// responses are taken into.

#ifndef RCLLEAN_CLIENT_H
#define RCLLEAN_CLIENT_H

#include <lean/lean.h>

#include <rcl/client.h>
#include <rosidl_runtime_lean/type_support.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // parent: the node
  rcl_client_t client;
  // Static storage in the interface package; not owned.
  const rosidl_runtime_lean_service_type_t *type;
  void *response_buffer;
} rcllean_client_t;

static inline rcllean_client_t *rcllean_to_client(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_client_t, o);
}

#endif // RCLLEAN_CLIENT_H
