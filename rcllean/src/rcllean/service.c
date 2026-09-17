// The service server: taking a request with the header that identifies its
// caller, and sending the matching response back.

#include "service.h"

#include <stdlib.h>
#include <string.h>

#include "exceptions.h"
#include "node.h"
#include "qos.h"
#include "utils.h"

// rmw identifies a caller by a 16-byte writer GUID and a sequence number.
// Lean carries them as a ByteArray and an Int64.
static bool rcllean_request_header_of(b_lean_obj_arg guid, int64_t sequence,
                                      rmw_request_id_t *out) {
  memset(out, 0, sizeof *out);
  if (lean_sarray_size(guid) != sizeof out->writer_guid) {
    return false;
  }
  memcpy(out->writer_guid, lean_sarray_cptr(guid), sizeof out->writer_guid);
  out->sequence_number = sequence;
  return true;
}

static void rcllean_service_fini(void *self) {
  rcllean_service_t *s = (rcllean_service_t *)self;
  free(s->request_buffer);
  s->request_buffer = NULL;
  rcllean_node_t *n = rcllean_to_node(s->hdr.parent);
  if (rcl_service_fini(&s->service, &n->node) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

// Rcllean.FFI.serviceCreate :
//   Node -> ServiceType -> String -> QoS -> IO Service
LEAN_EXPORT lean_object *rcllean_service_create(b_lean_obj_arg node,
                                                b_lean_obj_arg type_obj,
                                                b_lean_obj_arg name,
                                                b_lean_obj_arg qos) {
  rcllean_node_t *n = rcllean_to_node(node);
  RCLLEAN_REQUIRE_VALID(n, "rcl_service_init");
  const rosidl_runtime_lean_service_type_t *type =
      rosidl_runtime_lean_service_type_of(type_obj);
  if (type == NULL) {
    RCLLEAN_FAIL("rcl_service_init", "not a generated service type record");
  }

  rcl_service_options_t options = rcl_service_get_default_options();
  options.qos = rcllean_to_qos(qos)->qos;

  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_service_t),
                                          (lean_object *)node,
                                          rcllean_service_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_service_init", "out of memory");
  }
  rcllean_service_t *s = rcllean_to_service(obj);
  s->service = rcl_get_zero_initialized_service();
  s->type = type;
  s->request_buffer = calloc(1, type->request->size);
  if (s->request_buffer == NULL) {
    lean_dec_ref(obj);
    RCLLEAN_FAIL("rcl_service_init", "out of memory");
  }

  rcl_ret_t ret = rcl_service_init(&s->service, &n->node, type->type_support,
                                   lean_string_cstr(name), &options);
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_service_init", ret));
  }
  return lean_io_result_mk_ok(obj);
}

// Rcllean.FFI.serviceTakeRequest :
// Service -> IO (Option (ByteArray × Int64 × α))
//
// An empty queue is `none`, not an error.
LEAN_EXPORT lean_object *rcllean_service_take_request(b_lean_obj_arg svc) {
  rcllean_service_t *s = rcllean_to_service(svc);
  RCLLEAN_REQUIRE_VALID(s, "rcl_take_request");
  const rosidl_runtime_lean_message_type_t *request = s->type->request;
  if (!request->init(s->request_buffer)) {
    RCLLEAN_FAIL("rcl_take_request", "message init failed");
  }
  rmw_service_info_t info;
  memset(&info, 0, sizeof info);
  rcl_ret_t ret = rcl_take_request_with_info(&s->service, &info,
                                             s->request_buffer);
  if (ret != RCL_RET_OK) {
    request->fini(s->request_buffer);
    if (ret == RCL_RET_SERVICE_TAKE_FAILED) {
      rcl_reset_error();
      return lean_io_result_mk_ok(rcllean_none());
    }
    return lean_io_result_mk_error(rcllean_mk_error("rcl_take_request", ret));
  }
  lean_object *res = request->to_lean(s->request_buffer);
  request->fini(s->request_buffer);
  if (lean_io_result_is_error(res)) {
    return res;
  }
  // ByteArray × (Int64 × α)
  const rmw_request_id_t *id = &info.request_id;
  lean_object *guid = rcllean_mk_raw_bytes((const uint8_t *)id->writer_guid,
                                           sizeof id->writer_guid);
  lean_object *seq = lean_box_uint64((uint64_t)id->sequence_number);
  return lean_io_result_mk_ok(rcllean_some(
      rcllean_pair(guid, rcllean_pair(seq, lean_io_result_take_value(res)))));
}

// Rcllean.FFI.serviceSendResponse :
// Service -> ByteArray -> Int64 -> α -> IO Unit
//
// Handlers may run concurrently under a reentrant callback group, so the
// response is converted into a buffer of its own.
LEAN_EXPORT lean_object *rcllean_service_send_response(b_lean_obj_arg svc,
                                                       b_lean_obj_arg guid,
                                                       int64_t sequence,
                                                       b_lean_obj_arg msg) {
  rcllean_service_t *s = rcllean_to_service(svc);
  RCLLEAN_REQUIRE_VALID(s, "rcl_send_response");
  rmw_request_id_t header;
  if (!rcllean_request_header_of(guid, sequence, &header)) {
    RCLLEAN_FAIL("rcl_send_response", "request header GUID must be 16 bytes");
  }
  const rosidl_runtime_lean_message_type_t *response = s->type->response;
  void *buf = calloc(1, response->size);
  if (buf == NULL) {
    RCLLEAN_FAIL("rcl_send_response", "out of memory");
  }
  if (!response->init(buf)) {
    free(buf);
    RCLLEAN_FAIL("rcl_send_response", "message init failed");
  }
  if (!response->from_lean(msg, buf)) {
    response->fini(buf);
    free(buf);
    RCLLEAN_FAIL("rcl_send_response", "converting the response failed");
  }
  rcl_ret_t ret = rcl_send_response(&s->service, &header, buf);
  response->fini(buf);
  free(buf);
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(rcllean_mk_error("rcl_send_response", ret));
  }
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_service_destroy(b_lean_obj_arg svc) {
  rcllean_handle_destroy(rcllean_to_service(svc));
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_service_name(b_lean_obj_arg svc) {
  rcllean_service_t *s = rcllean_to_service(svc);
  RCLLEAN_REQUIRE_VALID(s, "rcl_service_get_service_name");
  return lean_io_result_mk_ok(
      rcllean_mk_string(rcl_service_get_service_name(&s->service)));
}
