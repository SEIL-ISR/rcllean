// The rcl node: the parent of every publisher, subscription, service and
// client created on it.

#ifndef RCLLEAN_NODE_H
#define RCLLEAN_NODE_H

#include <lean/lean.h>
#include <stdbool.h>

#include <rcl/node.h>

#include "destroyable.h"

typedef struct {
  rcllean_hdr hdr;  // parent: the context
  rcl_node_t node;
  // Owns a /rosout publisher, torn down before rcl_node_fini.
  bool rosout_publisher;
} rcllean_node_t;

static inline rcllean_node_t *rcllean_to_node(b_lean_obj_arg o) {
  return RCLLEAN_TO(rcllean_node_t, o);
}

#endif // RCLLEAN_NODE_H
