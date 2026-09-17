// Logging through rcutils: a call site captured by the Lean macro, and the
// logger-level getters and setters around it.

#include "logging.h"

#include <lean/lean.h>

#include <rcutils/logging.h>

#include "exceptions.h"
#include "utils.h"

// Rcllean.FFI.logAt :
// UInt32 -> String -> String -> String -> String -> UInt32 -> IO Unit
//
// severity, logger name, message, then the call site captured by the Lean
// macro.  The message is passed as a "%s" argument so stray `%` in user text
// is not interpreted.
LEAN_EXPORT lean_object *rcllean_log_at(uint32_t severity,
                                        b_lean_obj_arg logger_name,
                                        b_lean_obj_arg message,
                                        b_lean_obj_arg file_name,
                                        b_lean_obj_arg function_name,
                                        uint32_t line) {
  const char *name = lean_string_cstr(logger_name);
  if (!rcutils_logging_logger_is_enabled_for(name, (int)severity)) {
    return rcllean_unit_ok();
  }
  rcutils_log_location_t location = {
      lean_string_cstr(function_name),
      lean_string_cstr(file_name),
      (size_t)line,
  };
  rcutils_log(&location, (int)severity, name, "%s", lean_string_cstr(message));
  return rcllean_unit_ok();
}

// Rcllean.FFI.loggingInitialize : IO Unit
LEAN_EXPORT lean_object *rcllean_logging_initialize(void) {
  rcutils_ret_t ret = rcutils_logging_initialize();
  if (ret != RCUTILS_RET_OK) {
    return lean_io_result_mk_error(
        rcllean_mk_msg_error("rcutils_logging_initialize", "failed"));
  }
  return rcllean_unit_ok();
}

// Rcllean.FFI.setLoggerLevel : String -> UInt32 -> IO Unit
LEAN_EXPORT lean_object *rcllean_set_logger_level(b_lean_obj_arg logger_name,
                                                  uint32_t severity) {
  rcutils_ret_t ret =
      rcutils_logging_set_logger_level(lean_string_cstr(logger_name),
                                       (int)severity);
  if (ret != RCUTILS_RET_OK) {
    rcutils_reset_error();
    return lean_io_result_mk_error(
        rcllean_mk_msg_error("rcutils_logging_set_logger_level", "failed"));
  }
  return rcllean_unit_ok();
}

// Rcllean.FFI.getLoggerLevel : String -> IO UInt32
LEAN_EXPORT lean_object *rcllean_get_logger_level(b_lean_obj_arg logger_name) {
  int level =
      rcutils_logging_get_logger_effective_level(lean_string_cstr(logger_name));
  if (level < 0) {
    rcutils_reset_error();
    level = RCUTILS_LOG_SEVERITY_UNSET;
  }
  return lean_io_result_mk_ok(lean_box_uint32((uint32_t)level));
}
