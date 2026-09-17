// Creating a subscription on a node, taking a message out of its queue and
// converting it to a Lean value.

#include "subscription.h"

#include <stdlib.h>

#include "exceptions.h"
#include "node.h"
#include "qos.h"
#include "utils.h"

static void rcllean_subscription_fini(void *self) {
  rcllean_subscription_t *s = (rcllean_subscription_t *)self;
  free(s->buffer);
  s->buffer = NULL;
  rcllean_node_t *n = rcllean_to_node(s->hdr.parent);
  if (rcl_subscription_fini(&s->subscription, &n->node) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

LEAN_EXPORT lean_object *rcllean_subscription_create(b_lean_obj_arg node,
                                                     b_lean_obj_arg type_obj,
                                                     b_lean_obj_arg topic,
                                                     b_lean_obj_arg qos) {
  rcllean_node_t *n = rcllean_to_node(node);
  RCLLEAN_REQUIRE_VALID(n, "rcl_subscription_init");
  const rosidl_runtime_lean_message_type_t *type =
      rosidl_runtime_lean_message_type_of(type_obj);
  if (type == NULL) {
    RCLLEAN_FAIL("rcl_subscription_init",
                 "not a generated message type record");
  }

  rcl_subscription_options_t options = rcl_subscription_get_default_options();
  options.qos = rcllean_to_qos(qos)->qos;

  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_subscription_t),
                                          (lean_object *)node,
                                          rcllean_subscription_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_subscription_init", "out of memory");
  }
  rcllean_subscription_t *s = rcllean_to_subscription(obj);
  s->subscription = rcl_get_zero_initialized_subscription();
  s->type = type;
  s->buffer = calloc(1, type->size);
  if (s->buffer == NULL) {
    lean_dec_ref(obj);
    RCLLEAN_FAIL("rcl_subscription_init", "out of memory");
  }

  rcl_ret_t ret = rcl_subscription_init(&s->subscription, &n->node,
                                        type->type_support,
                                        lean_string_cstr(topic), &options);
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(
        rcllean_mk_error("rcl_subscription_init", ret));
  }
  return lean_io_result_mk_ok(obj);
}

// Rcllean.FFI.subscriptionTake : Subscription -> IO (Option α)
//
// An empty queue is `none`: rcl reports it as
// RCL_RET_SUBSCRIPTION_TAKE_FAILED, which is not an error.
LEAN_EXPORT lean_object *rcllean_subscription_take(b_lean_obj_arg sub) {
  rcllean_subscription_t *s = rcllean_to_subscription(sub);
  RCLLEAN_REQUIRE_VALID(s, "rcl_take");
  const rosidl_runtime_lean_message_type_t *type = s->type;
  if (!type->init(s->buffer)) {
    RCLLEAN_FAIL("rcl_take", "message init failed");
  }
  rcl_ret_t ret = rcl_take(&s->subscription, s->buffer, NULL, NULL);
  if (ret != RCL_RET_OK) {
    type->fini(s->buffer);
    if (ret == RCL_RET_SUBSCRIPTION_TAKE_FAILED) {
      rcl_reset_error();
      return lean_io_result_mk_ok(rcllean_none());
    }
    return lean_io_result_mk_error(rcllean_mk_error("rcl_take", ret));
  }
  // A wire value violating a field's bound comes back as an IO error.
  lean_object *res = type->to_lean(s->buffer);
  type->fini(s->buffer);
  if (lean_io_result_is_error(res)) {
    return res;
  }
  return lean_io_result_mk_ok(
      rcllean_some(lean_io_result_take_value(res)));
}

LEAN_EXPORT lean_object *rcllean_subscription_destroy(b_lean_obj_arg sub) {
  rcllean_handle_destroy(rcllean_to_subscription(sub));
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_subscription_publisher_count(
    b_lean_obj_arg sub) {
  rcllean_subscription_t *s = rcllean_to_subscription(sub);
  RCLLEAN_REQUIRE_VALID(s, "rcl_subscription_get_publisher_count");
  size_t count = 0;
  RCLLEAN_TRY("rcl_subscription_get_publisher_count",
              rcl_subscription_get_publisher_count(&s->subscription, &count));
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)count));
}

LEAN_EXPORT lean_object *rcllean_subscription_topic_name(b_lean_obj_arg sub) {
  rcllean_subscription_t *s = rcllean_to_subscription(sub);
  RCLLEAN_REQUIRE_VALID(s, "rcl_subscription_get_topic_name");
  return lean_io_result_mk_ok(
      rcllean_mk_string(rcl_subscription_get_topic_name(&s->subscription)));
}
