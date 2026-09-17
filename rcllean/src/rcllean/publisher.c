// Creating a publisher on a node, publishing a converted message, and the few
// queries Lean asks of it.

#include "publisher.h"

#include <stdlib.h>

#include "exceptions.h"
#include "node.h"
#include "qos.h"
#include "utils.h"

static void rcllean_publisher_fini(void *self) {
  rcllean_publisher_t *p = (rcllean_publisher_t *)self;
  rcllean_node_t *n = rcllean_to_node(p->hdr.parent);
  if (rcl_publisher_fini(&p->publisher, &n->node) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

// Rcllean.FFI.publisherCreate :
//   Node -> MessageType -> String -> QoS -> IO Publisher
LEAN_EXPORT lean_object *rcllean_publisher_create(b_lean_obj_arg node,
                                                  b_lean_obj_arg type_obj,
                                                  b_lean_obj_arg topic,
                                                  b_lean_obj_arg qos) {
  rcllean_node_t *n = rcllean_to_node(node);
  RCLLEAN_REQUIRE_VALID(n, "rcl_publisher_init");
  const rosidl_runtime_lean_message_type_t *type =
      rosidl_runtime_lean_message_type_of(type_obj);
  if (type == NULL) {
    RCLLEAN_FAIL("rcl_publisher_init", "not a generated message type record");
  }

  rcl_publisher_options_t options = rcl_publisher_get_default_options();
  options.qos = rcllean_to_qos(qos)->qos;

  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_publisher_t),
                                          (lean_object *)node,
                                          rcllean_publisher_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_publisher_init", "out of memory");
  }
  rcllean_publisher_t *p = rcllean_to_publisher(obj);
  p->publisher = rcl_get_zero_initialized_publisher();
  p->type = type;

  rcl_ret_t ret = rcl_publisher_init(&p->publisher, &n->node,
                                     type->type_support,
                                     lean_string_cstr(topic), &options);
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_publisher_init", ret));
  }
  return lean_io_result_mk_ok(obj);
}

// Rcllean.FFI.publisherPublish : Publisher -> α -> IO Unit
LEAN_EXPORT lean_object *rcllean_publisher_publish(b_lean_obj_arg pub,
                                                   b_lean_obj_arg msg) {
  rcllean_publisher_t *p = rcllean_to_publisher(pub);
  RCLLEAN_REQUIRE_VALID(p, "rcl_publish");
  const rosidl_runtime_lean_message_type_t *type = p->type;
  // No buffer is cached on the publisher: publishing is allowed from several
  // threads at once, so each call converts into its own.
  void *buf = calloc(1, type->size);
  if (buf == NULL) {
    RCLLEAN_FAIL("rcl_publish", "out of memory");
  }
  if (!type->init(buf)) {
    free(buf);
    RCLLEAN_FAIL("rcl_publish", "message init failed");
  }
  if (!type->from_lean(msg, buf)) {
    type->fini(buf);
    free(buf);
    RCLLEAN_FAIL("rcl_publish", "converting the message failed");
  }
  rcl_ret_t ret = rcl_publish(&p->publisher, buf, NULL);
  type->fini(buf);
  free(buf);
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(rcllean_mk_error("rcl_publish", ret));
  }
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_publisher_destroy(b_lean_obj_arg pub) {
  rcllean_handle_destroy(rcllean_to_publisher(pub));
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_publisher_subscription_count(
    b_lean_obj_arg pub) {
  rcllean_publisher_t *p = rcllean_to_publisher(pub);
  RCLLEAN_REQUIRE_VALID(p, "rcl_publisher_get_subscription_count");
  size_t count = 0;
  RCLLEAN_TRY("rcl_publisher_get_subscription_count",
              rcl_publisher_get_subscription_count(&p->publisher, &count));
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)count));
}

LEAN_EXPORT lean_object *rcllean_publisher_topic_name(b_lean_obj_arg pub) {
  rcllean_publisher_t *p = rcllean_to_publisher(pub);
  RCLLEAN_REQUIRE_VALID(p, "rcl_publisher_get_topic_name");
  return lean_io_result_mk_ok(
      rcllean_mk_string(rcl_publisher_get_topic_name(&p->publisher)));
}
