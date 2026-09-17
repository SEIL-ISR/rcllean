// The service client: sending a request, matching the response that comes
// back by sequence number, and asking whether a server is there at all.

#include "client.h"

#include <stdlib.h>
#include <string.h>

#include <rcl/graph.h>

#include "exceptions.h"
#include "node.h"
#include "qos.h"
#include "utils.h"

static void rcllean_client_fini(void *self) {
  rcllean_client_t *c = (rcllean_client_t *)self;
  free(c->response_buffer);
  c->response_buffer = NULL;
  rcllean_node_t *n = rcllean_to_node(c->hdr.parent);
  if (rcl_client_fini(&c->client, &n->node) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

LEAN_EXPORT lean_object *rcllean_client_create(b_lean_obj_arg node,
                                               b_lean_obj_arg type_obj,
                                               b_lean_obj_arg name,
                                               b_lean_obj_arg qos) {
  rcllean_node_t *n = rcllean_to_node(node);
  RCLLEAN_REQUIRE_VALID(n, "rcl_client_init");
  const rosidl_runtime_lean_service_type_t *type =
      rosidl_runtime_lean_service_type_of(type_obj);
  if (type == NULL) {
    RCLLEAN_FAIL("rcl_client_init", "not a generated service type record");
  }

  rcl_client_options_t options = rcl_client_get_default_options();
  options.qos = rcllean_to_qos(qos)->qos;

  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_client_t),
                                          (lean_object *)node,
                                          rcllean_client_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_client_init", "out of memory");
  }
  rcllean_client_t *c = rcllean_to_client(obj);
  c->client = rcl_get_zero_initialized_client();
  c->type = type;
  c->response_buffer = calloc(1, type->response->size);
  if (c->response_buffer == NULL) {
    lean_dec_ref(obj);
    RCLLEAN_FAIL("rcl_client_init", "out of memory");
  }

  rcl_ret_t ret = rcl_client_init(&c->client, &n->node, type->type_support,
                                  lean_string_cstr(name), &options);
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_client_init", ret));
  }
  return lean_io_result_mk_ok(obj);
}

// Rcllean.FFI.clientSendRequest : Client -> α -> IO Int64
//
// Returns the sequence number identifying this call among others in flight.
LEAN_EXPORT lean_object *rcllean_client_send_request(b_lean_obj_arg cli,
                                                     b_lean_obj_arg msg) {
  rcllean_client_t *c = rcllean_to_client(cli);
  RCLLEAN_REQUIRE_VALID(c, "rcl_send_request");
  const rosidl_runtime_lean_message_type_t *request = c->type->request;
  void *buf = calloc(1, request->size);
  if (buf == NULL) {
    RCLLEAN_FAIL("rcl_send_request", "out of memory");
  }
  if (!request->init(buf)) {
    free(buf);
    RCLLEAN_FAIL("rcl_send_request", "message init failed");
  }
  if (!request->from_lean(msg, buf)) {
    request->fini(buf);
    free(buf);
    RCLLEAN_FAIL("rcl_send_request", "converting the request failed");
  }
  int64_t sequence = 0;
  rcl_ret_t ret = rcl_send_request(&c->client, buf, &sequence);
  request->fini(buf);
  free(buf);
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(rcllean_mk_error("rcl_send_request", ret));
  }
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)sequence));
}

// Rcllean.FFI.clientTakeResponse : Client -> IO (Option (Int64 × α))
//
// The sequence number says which request was answered.
LEAN_EXPORT lean_object *rcllean_client_take_response(b_lean_obj_arg cli) {
  rcllean_client_t *c = rcllean_to_client(cli);
  RCLLEAN_REQUIRE_VALID(c, "rcl_take_response");
  const rosidl_runtime_lean_message_type_t *response = c->type->response;
  if (!response->init(c->response_buffer)) {
    RCLLEAN_FAIL("rcl_take_response", "message init failed");
  }
  rmw_service_info_t info;
  memset(&info, 0, sizeof info);
  rcl_ret_t ret = rcl_take_response_with_info(&c->client, &info,
                                              c->response_buffer);
  if (ret != RCL_RET_OK) {
    response->fini(c->response_buffer);
    if (ret == RCL_RET_CLIENT_TAKE_FAILED) {
      rcl_reset_error();
      return lean_io_result_mk_ok(rcllean_none());
    }
    return lean_io_result_mk_error(rcllean_mk_error("rcl_take_response", ret));
  }
  lean_object *res = response->to_lean(c->response_buffer);
  response->fini(c->response_buffer);
  if (lean_io_result_is_error(res)) {
    return res;
  }
  return lean_io_result_mk_ok(rcllean_some(rcllean_pair(
      lean_box_uint64((uint64_t)info.request_id.sequence_number),
      lean_io_result_take_value(res))));
}

LEAN_EXPORT lean_object *rcllean_client_service_is_available(
    b_lean_obj_arg cli) {
  rcllean_client_t *c = rcllean_to_client(cli);
  RCLLEAN_REQUIRE_VALID(c, "rcl_service_server_is_available");
  rcllean_node_t *n = rcllean_to_node(c->hdr.parent);
  bool available = false;
  RCLLEAN_TRY("rcl_service_server_is_available",
              rcl_service_server_is_available(&n->node, &c->client, &available));
  return lean_io_result_mk_ok(lean_box(available ? 1 : 0));
}

LEAN_EXPORT lean_object *rcllean_client_destroy(b_lean_obj_arg cli) {
  rcllean_handle_destroy(rcllean_to_client(cli));
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_client_service_name(b_lean_obj_arg cli) {
  rcllean_client_t *c = rcllean_to_client(cli);
  RCLLEAN_REQUIRE_VALID(c, "rcl_client_get_service_name");
  return lean_io_result_mk_ok(
      rcllean_mk_string(rcl_client_get_service_name(&c->client)));
}
