// Graph queries run against a node: the topics, services and nodes that are
// out there, and how many publishers or subscribers a topic has.

#include "graph.h"

#include <stdlib.h>
#include <string.h>

#include <rcl/graph.h>
#include <rcutils/format_string.h>

#include "exceptions.h"
#include "node.h"
#include "utils.h"

// Two parallel arrays: names, and each name's types joined by '\x1f' (unit
// separator), which cannot appear in a ROS type name.
static lean_object *rcllean_join_types(const rcutils_string_array_t *types) {
  size_t total = 0;
  for (size_t k = 0; k < types->size; ++k) {
    total += strlen(types->data[k]) + 1;
  }
  char *joined = (char *)malloc(total + 1);
  if (joined == NULL) {
    return lean_mk_string("");
  }
  size_t used = 0;
  for (size_t k = 0; k < types->size; ++k) {
    if (k > 0) {
      joined[used++] = '\x1f';
    }
    size_t len = strlen(types->data[k]);
    memcpy(joined + used, types->data[k], len);
    used += len;
  }
  lean_object *out = rcllean_mk_string_n(joined, used);
  free(joined);
  return out;
}

static lean_object *rcllean_names_and_types_to_lean(
    const rcl_names_and_types_t *nt) {
  size_t n = nt->names.size;
  lean_object *names = lean_alloc_array(n, n);
  lean_object *types = lean_alloc_array(n, n);
  for (size_t i = 0; i < n; ++i) {
    lean_array_set_core(names, i, rcllean_mk_string(nt->names.data[i]));
    lean_array_set_core(types, i, rcllean_join_types(&nt->types[i]));
  }
  return rcllean_pair(names, types);
}

#define RCLLEAN_GRAPH_QUERY(fnname, rcl_call)                                 \
  LEAN_EXPORT lean_object *fnname(b_lean_obj_arg node) {       \
    rcllean_node_t *n = rcllean_to_node(node);                                 \
    RCLLEAN_REQUIRE_VALID(n, #fnname);                                         \
    rcl_allocator_t allocator = rcl_get_default_allocator();                   \
    rcl_names_and_types_t nt = rcl_get_zero_initialized_names_and_types();     \
    rcl_ret_t ret = rcl_call;                                                  \
    if (ret != RCL_RET_OK) {                                                   \
      return lean_io_result_mk_error(rcllean_mk_error(#rcl_call, ret));        \
    }                                                                          \
    lean_object *out = rcllean_names_and_types_to_lean(&nt);                   \
    if (rcl_names_and_types_fini(&nt) != RCL_RET_OK) {                         \
      rcl_reset_error();                                                       \
    }                                                                          \
    return lean_io_result_mk_ok(out);                                          \
  }

RCLLEAN_GRAPH_QUERY(rcllean_graph_topic_names_and_types,
                    rcl_get_topic_names_and_types(&n->node, &allocator, false,
                                                  &nt))
RCLLEAN_GRAPH_QUERY(rcllean_graph_service_names_and_types,
                    rcl_get_service_names_and_types(&n->node, &allocator, &nt))

// Every node on the graph, as fully qualified names.
LEAN_EXPORT lean_object *rcllean_graph_node_names(b_lean_obj_arg node) {
  rcllean_node_t *n = rcllean_to_node(node);
  RCLLEAN_REQUIRE_VALID(n, "rcl_get_node_names");
  rcl_allocator_t allocator = rcl_get_default_allocator();
  rcutils_string_array_t names = rcutils_get_zero_initialized_string_array();
  rcutils_string_array_t namespaces = rcutils_get_zero_initialized_string_array();

  rcl_ret_t ret = rcl_get_node_names(&n->node, allocator, &names, &namespaces);
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(rcllean_mk_error("rcl_get_node_names", ret));
  }

  lean_object *out = lean_alloc_array(names.size, names.size);
  for (size_t i = 0; i < names.size; ++i) {
    // Joined as `ros2 node list` prints them.
    const char *ns = namespaces.data[i] == NULL ? "/" : namespaces.data[i];
    const char *nm = names.data[i] == NULL ? "" : names.data[i];
    char *full = rcutils_format_string(allocator, "%s%s%s", ns,
                                       strcmp(ns, "/") == 0 ? "" : "/", nm);
    lean_array_set_core(out, i, rcllean_mk_string(full));
    allocator.deallocate(full, allocator.state);
  }
  if (rcutils_string_array_fini(&names) != RCUTILS_RET_OK ||
      rcutils_string_array_fini(&namespaces) != RCUTILS_RET_OK) {
    rcutils_reset_error();
  }
  return lean_io_result_mk_ok(out);
}

LEAN_EXPORT lean_object *rcllean_graph_count_publishers(b_lean_obj_arg node,
                                                        b_lean_obj_arg topic) {
  rcllean_node_t *n = rcllean_to_node(node);
  RCLLEAN_REQUIRE_VALID(n, "rcl_count_publishers");
  size_t count = 0;
  RCLLEAN_TRY("rcl_count_publishers",
              rcl_count_publishers(&n->node, lean_string_cstr(topic), &count));
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)count));
}

LEAN_EXPORT lean_object *rcllean_graph_count_subscribers(b_lean_obj_arg node,
                                                         b_lean_obj_arg topic) {
  rcllean_node_t *n = rcllean_to_node(node);
  RCLLEAN_REQUIRE_VALID(n, "rcl_count_subscribers");
  size_t count = 0;
  RCLLEAN_TRY("rcl_count_subscribers",
              rcl_count_subscribers(&n->node, lean_string_cstr(topic), &count));
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)count));
}
