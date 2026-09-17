// Formatting rcl return codes and the thread-local rcl error state into the
// message a Lean `IO.userError` carries.

#include "exceptions.h"

#include <stdio.h>

// Name for the rcl return codes; unknown codes fall back to their number.
static const char *rcllean_ret_name(int ret) {
  switch (ret) {
    case RCL_RET_OK: return "RCL_RET_OK";
    case RCL_RET_ERROR: return "RCL_RET_ERROR";
    case RCL_RET_TIMEOUT: return "RCL_RET_TIMEOUT";
    case RCL_RET_BAD_ALLOC: return "RCL_RET_BAD_ALLOC";
    case RCL_RET_INVALID_ARGUMENT: return "RCL_RET_INVALID_ARGUMENT";
    case RCL_RET_UNSUPPORTED: return "RCL_RET_UNSUPPORTED";
    case RCL_RET_ALREADY_INIT: return "RCL_RET_ALREADY_INIT";
    case RCL_RET_NOT_INIT: return "RCL_RET_NOT_INIT";
    case RCL_RET_MISMATCHED_RMW_ID: return "RCL_RET_MISMATCHED_RMW_ID";
    case RCL_RET_TOPIC_NAME_INVALID: return "RCL_RET_TOPIC_NAME_INVALID";
    case RCL_RET_SERVICE_NAME_INVALID: return "RCL_RET_SERVICE_NAME_INVALID";
    case RCL_RET_UNKNOWN_SUBSTITUTION: return "RCL_RET_UNKNOWN_SUBSTITUTION";
    case RCL_RET_ALREADY_SHUTDOWN: return "RCL_RET_ALREADY_SHUTDOWN";
    case RCL_RET_NODE_INVALID: return "RCL_RET_NODE_INVALID";
    case RCL_RET_NODE_INVALID_NAME: return "RCL_RET_NODE_INVALID_NAME";
    case RCL_RET_NODE_INVALID_NAMESPACE: return "RCL_RET_NODE_INVALID_NAMESPACE";
    case RCL_RET_NODE_NAME_NON_EXISTENT: return "RCL_RET_NODE_NAME_NON_EXISTENT";
    case RCL_RET_PUBLISHER_INVALID: return "RCL_RET_PUBLISHER_INVALID";
    case RCL_RET_SUBSCRIPTION_INVALID: return "RCL_RET_SUBSCRIPTION_INVALID";
    case RCL_RET_SUBSCRIPTION_TAKE_FAILED: return "RCL_RET_SUBSCRIPTION_TAKE_FAILED";
    case RCL_RET_CLIENT_INVALID: return "RCL_RET_CLIENT_INVALID";
    case RCL_RET_CLIENT_TAKE_FAILED: return "RCL_RET_CLIENT_TAKE_FAILED";
    case RCL_RET_SERVICE_INVALID: return "RCL_RET_SERVICE_INVALID";
    case RCL_RET_SERVICE_TAKE_FAILED: return "RCL_RET_SERVICE_TAKE_FAILED";
    case RCL_RET_TIMER_INVALID: return "RCL_RET_TIMER_INVALID";
    case RCL_RET_TIMER_CANCELED: return "RCL_RET_TIMER_CANCELED";
    case RCL_RET_WAIT_SET_INVALID: return "RCL_RET_WAIT_SET_INVALID";
    case RCL_RET_WAIT_SET_EMPTY: return "RCL_RET_WAIT_SET_EMPTY";
    case RCL_RET_WAIT_SET_FULL: return "RCL_RET_WAIT_SET_FULL";
    case RCL_RET_INVALID_REMAP_RULE: return "RCL_RET_INVALID_REMAP_RULE";
    case RCL_RET_WRONG_LEXEME: return "RCL_RET_WRONG_LEXEME";
    case RCL_RET_INVALID_ROS_ARGS: return "RCL_RET_INVALID_ROS_ARGS";
    case RCL_RET_INVALID_PARAM_RULE: return "RCL_RET_INVALID_PARAM_RULE";
    case RCL_RET_INVALID_LOG_LEVEL_RULE: return "RCL_RET_INVALID_LOG_LEVEL_RULE";
    case RCL_RET_EVENT_INVALID: return "RCL_RET_EVENT_INVALID";
    case RCL_RET_EVENT_TAKE_FAILED: return "RCL_RET_EVENT_TAKE_FAILED";
    default: return NULL;
  }
}

lean_object *rcllean_mk_error(const char *fn, int ret) {
  const char *name = rcllean_ret_name(ret);
  char code[64];
  if (name != NULL) {
    snprintf(code, sizeof code, "%s (%d)", name, ret);
  } else {
    snprintf(code, sizeof code, "rcl error %d", ret);
  }
  char buf[2048];
  if (rcl_error_is_set()) {
    // The error string is a stack copy; format before resetting.
    rcl_error_string_t err = rcl_get_error_string();
    snprintf(buf, sizeof buf, "%s: %s: %s", fn, code, err.str);
    rcl_reset_error();
  } else {
    snprintf(buf, sizeof buf, "%s: %s", fn, code);
  }
  return lean_mk_io_user_error(lean_mk_string(buf));
}

lean_object *rcllean_mk_msg_error(const char *fn, const char *msg) {
  char buf[1024];
  snprintf(buf, sizeof buf, "%s: %s", fn, msg == NULL ? "unknown error" : msg);
  return lean_mk_io_user_error(lean_mk_string(buf));
}
