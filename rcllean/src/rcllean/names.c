// The name oracles.  The validators return an empty string when the name is
// valid, the library's explanation when it is not.  Lean implements the same
// rules; a test checks the two agree on a corpus.
//
// rcl validates a name as written and rmw validates one after expansion, so
// both are exposed: the Lean side has a predicate for each.

#include "names.h"

#include <stdio.h>

#include <lean/lean.h>

#include <rcl/expand_topic_name.h>
#include <rcl/validate_topic_name.h>
#include <rcutils/error_handling.h>
#include <rcutils/types/string_map.h>
#include <rmw/validate_full_topic_name.h>
#include <rmw/validate_namespace.h>
#include <rmw/validate_node_name.h>

#include "exceptions.h"

LEAN_EXPORT lean_object *rcllean_validate_full_topic_name(b_lean_obj_arg name) {
  int result = 0;
  size_t index = 0;
  rmw_ret_t ret =
      rmw_validate_full_topic_name(lean_string_cstr(name), &result, &index);
  if (ret != RMW_RET_OK) {
    return lean_io_result_mk_ok(lean_mk_string("validation failed"));
  }
  if (result == RMW_TOPIC_VALID) {
    return lean_io_result_mk_ok(lean_mk_string(""));
  }
  char buf[512];
  snprintf(buf, sizeof buf, "%s (at index %zu)",
           rmw_full_topic_name_validation_result_string(result), index);
  return lean_io_result_mk_ok(lean_mk_string(buf));
}

LEAN_EXPORT lean_object *rcllean_validate_topic_name_rcl(b_lean_obj_arg name) {
  int result = 0;
  size_t index = 0;
  rcl_ret_t ret =
      rcl_validate_topic_name(lean_string_cstr(name), &result, &index);
  if (ret != RCL_RET_OK) {
    rcutils_reset_error();
    return lean_io_result_mk_ok(lean_mk_string("validation failed"));
  }
  if (result == RCL_TOPIC_NAME_VALID) {
    return lean_io_result_mk_ok(lean_mk_string(""));
  }
  char buf[512];
  snprintf(buf, sizeof buf, "%s (at index %zu)",
           rcl_topic_name_validation_result_string(result), index);
  return lean_io_result_mk_ok(lean_mk_string(buf));
}

LEAN_EXPORT lean_object *rcllean_validate_node_name(b_lean_obj_arg name) {
  int result = 0;
  size_t index = 0;
  rmw_ret_t ret =
      rmw_validate_node_name(lean_string_cstr(name), &result, &index);
  if (ret != RMW_RET_OK) {
    return lean_io_result_mk_ok(lean_mk_string("validation failed"));
  }
  if (result == RMW_NODE_NAME_VALID) {
    return lean_io_result_mk_ok(lean_mk_string(""));
  }
  char buf[512];
  snprintf(buf, sizeof buf, "%s (at index %zu)",
           rmw_node_name_validation_result_string(result), index);
  return lean_io_result_mk_ok(lean_mk_string(buf));
}

LEAN_EXPORT lean_object *rcllean_validate_namespace(b_lean_obj_arg name) {
  int result = 0;
  size_t index = 0;
  rmw_ret_t ret =
      rmw_validate_namespace(lean_string_cstr(name), &result, &index);
  if (ret != RMW_RET_OK) {
    return lean_io_result_mk_ok(lean_mk_string("validation failed"));
  }
  if (result == RMW_NAMESPACE_VALID) {
    return lean_io_result_mk_ok(lean_mk_string(""));
  }
  char buf[512];
  snprintf(buf, sizeof buf, "%s (at index %zu)",
           rmw_namespace_validation_result_string(result), index);
  return lean_io_result_mk_ok(lean_mk_string(buf));
}

// The map is only ever local to one call, so a failed teardown has nothing to
// report; clear the error state so it does not leak into the next rcl call.
static void rcllean_fini_string_map(rcutils_string_map_t *map) {
  if (rcutils_string_map_fini(map) != RCUTILS_RET_OK) {
    rcutils_reset_error();
  }
}

LEAN_EXPORT lean_object *rcllean_expand_topic_name(b_lean_obj_arg topic,
                                                   b_lean_obj_arg node,
                                                   b_lean_obj_arg ns) {
  rcutils_allocator_t rcutils_allocator = rcutils_get_default_allocator();
  rcutils_string_map_t subs = rcutils_get_zero_initialized_string_map();
  if (rcutils_string_map_init(&subs, 0, rcutils_allocator) != RCUTILS_RET_OK) {
    rcutils_reset_error();
    RCLLEAN_FAIL("rcutils_string_map_init", "failed to make a string map");
  }
  if (rcl_get_default_topic_name_substitutions(&subs) != RCL_RET_OK) {
    rcllean_fini_string_map(&subs);
    RCLLEAN_FAIL("rcl_get_default_topic_name_substitutions",
                 "failed to read the default substitutions");
  }

  rcl_allocator_t allocator = rcl_get_default_allocator();
  char *expanded = NULL;
  rcl_ret_t ret =
      rcl_expand_topic_name(lean_string_cstr(topic), lean_string_cstr(node),
                            lean_string_cstr(ns), &subs, allocator, &expanded);
  rcllean_fini_string_map(&subs);
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(
        rcllean_mk_error("rcl_expand_topic_name", ret));
  }
  lean_object *out = lean_mk_string(expanded);
  allocator.deallocate(expanded, allocator.state);
  return lean_io_result_mk_ok(out);
}
