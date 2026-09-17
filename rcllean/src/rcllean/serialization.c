// Turning a message into the CDR bytes that go on the wire, and reading those
// bytes back.

#include "serialization.h"

#include <stdlib.h>
#include <string.h>

#include <rcl/allocator.h>
#include <rmw/rmw.h>
#include <rmw/serialized_message.h>
#include <rosidl_runtime_lean/type_support.h>

#include "exceptions.h"
#include "utils.h"

// Rcllean.FFI.msgSerialize : MessageType -> α -> IO ByteArray
LEAN_EXPORT lean_object *rcllean_msg_serialize(b_lean_obj_arg type_obj,
                                               b_lean_obj_arg msg) {
  const rosidl_runtime_lean_message_type_t *type =
      rosidl_runtime_lean_message_type_of(type_obj);
  if (type == NULL) {
    RCLLEAN_FAIL("serialize", "not a generated message type record");
  }
  void *buf = calloc(1, type->size);
  if (buf == NULL) {
    RCLLEAN_FAIL("serialize", "out of memory");
  }
  if (!type->init(buf)) {
    free(buf);
    RCLLEAN_FAIL("serialize", "message init failed");
  }
  if (!type->from_lean(msg, buf)) {
    type->fini(buf);
    free(buf);
    RCLLEAN_FAIL("serialize", "converting the message failed");
  }

  rcl_serialized_message_t serialized =
      rmw_get_zero_initialized_serialized_message();
  rcl_allocator_t allocator = rcl_get_default_allocator();
  rcl_ret_t ret = rmw_serialized_message_init(&serialized, 0u, &allocator);
  if (ret != RCL_RET_OK) {
    type->fini(buf);
    free(buf);
    return lean_io_result_mk_error(
        rcllean_mk_error("rmw_serialized_message_init", ret));
  }
  ret = rmw_serialize(buf, type->type_support, &serialized);
  type->fini(buf);
  free(buf);
  if (ret != RCL_RET_OK) {
    if (rmw_serialized_message_fini(&serialized) != RCL_RET_OK) {
      rcl_reset_error();
    }
    return lean_io_result_mk_error(rcllean_mk_error("rmw_serialize", ret));
  }

  lean_object *out =
      rcllean_mk_raw_bytes(serialized.buffer, serialized.buffer_length);
  if (rmw_serialized_message_fini(&serialized) != RCL_RET_OK) {
    rcl_reset_error();
  }
  return lean_io_result_mk_ok(out);
}

// Rcllean.FFI.msgDeserialize : MessageType -> ByteArray -> IO α
LEAN_EXPORT lean_object *rcllean_msg_deserialize(b_lean_obj_arg type_obj,
                                                 b_lean_obj_arg bytes) {
  const rosidl_runtime_lean_message_type_t *type =
      rosidl_runtime_lean_message_type_of(type_obj);
  if (type == NULL) {
    RCLLEAN_FAIL("deserialize", "not a generated message type record");
  }
  size_t len = lean_sarray_size(bytes);

  rcl_serialized_message_t serialized =
      rmw_get_zero_initialized_serialized_message();
  rcl_allocator_t allocator = rcl_get_default_allocator();
  rcl_ret_t ret = rmw_serialized_message_init(&serialized, len, &allocator);
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(
        rcllean_mk_error("rmw_serialized_message_init", ret));
  }
  memcpy(serialized.buffer, lean_sarray_cptr(bytes), len);
  serialized.buffer_length = len;

  void *buf = calloc(1, type->size);
  if (buf != NULL && !type->init(buf)) {
    free(buf);
    buf = NULL;
  }
  if (buf == NULL) {
    if (rmw_serialized_message_fini(&serialized) != RCL_RET_OK) {
      rcl_reset_error();
    }
    RCLLEAN_FAIL("deserialize", "out of memory");
  }
  ret = rmw_deserialize(&serialized, type->type_support, buf);
  if (rmw_serialized_message_fini(&serialized) != RCL_RET_OK) {
    rcl_reset_error();
  }
  if (ret != RCL_RET_OK) {
    type->fini(buf);
    free(buf);
    return lean_io_result_mk_error(rcllean_mk_error("rmw_deserialize", ret));
  }

  // A wire value violating a field's bound comes back as an IO error.
  lean_object *res = type->to_lean(buf);
  type->fini(buf);
  free(buf);
  return res;
}
