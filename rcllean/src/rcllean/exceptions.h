// Turning an rcl failure into a Lean `IO` error, and the two macros that bail
// out of an entry point with one.

#ifndef RCLLEAN_EXCEPTIONS_H
#define RCLLEAN_EXCEPTIONS_H

#include <lean/lean.h>

#include <rcl/error_handling.h>
#include <rcl/types.h>

// IO error from an rcl return code, consuming and resetting the thread-local
// rcl error state.  `fn` names the failing call.
lean_object *rcllean_mk_error(const char *fn, int ret);

// IO error from a plain message; no rcl error state involved.
lean_object *rcllean_mk_msg_error(const char *fn, const char *msg);

// Bail out of an IO entry point when an rcl call fails.
#define RCLLEAN_TRY(fnname, expr)                                              \
  do {                                                                         \
    rcl_ret_t rcllean_try_ret_ = (expr);                                       \
    if (rcllean_try_ret_ != RCL_RET_OK) {                                      \
      return lean_io_result_mk_error(rcllean_mk_error(fnname, rcllean_try_ret_)); \
    }                                                                          \
  } while (0)

// Bail out of an IO entry point with a plain message.
#define RCLLEAN_FAIL(fnname, msg)                                              \
  return lean_io_result_mk_error(rcllean_mk_msg_error(fnname, msg))

#endif // RCLLEAN_EXCEPTIONS_H
