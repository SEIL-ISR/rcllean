// The parts of the shim that belong to no one rcl entity: string, byte and
// argv conversions, the rmw implementation name, and stripping the ROS
// section off a command line.

#include "utils.h"

#include <stdlib.h>
#include <string.h>

#include <rcl/allocator.h>
#include <rcl/arguments.h>
#include <rmw/rmw.h>

#include "exceptions.h"

// Strings, argv and the two entry points that stand on their own.

lean_object *rcllean_mk_string(const char *s) {
  return lean_mk_string(s == NULL ? "" : s);
}

lean_object *rcllean_mk_string_n(const char *s, size_t len) {
  // lean_mk_string_from_bytes validates and repairs the bytes.
  return lean_mk_string_from_bytes(s == NULL ? "" : s, s == NULL ? 0 : len);
}

char const **rcllean_argv_of(b_lean_obj_arg args, size_t *out_argc) {
  size_t argc = lean_array_size(args);
  *out_argc = argc;
  if (argc == 0) {
    return NULL;
  }
  char const **argv = (char const **)calloc(argc + 1, sizeof(char *));
  if (argv == NULL) {
    return NULL;
  }
  for (size_t i = 0; i < argc; ++i) {
    argv[i] = lean_string_cstr(lean_array_get_core(args, i));
  }
  return argv;
}

// Rcllean.FFI.rmwImplementationIdentifier : IO String
LEAN_EXPORT lean_object *rcllean_rmw_implementation_identifier(void) {
  const char *id = rmw_get_implementation_identifier();
  if (id == NULL) {
    RCLLEAN_FAIL("rmw_get_implementation_identifier",
                 "no rmw implementation loaded");
  }
  return lean_io_result_mk_ok(rcllean_mk_string(id));
}

// Rcllean.FFI.removeRosArguments : Array String -> IO (Array String)
//
// Returns the arguments with the `--ros-args ... --` section removed.
LEAN_EXPORT lean_object *rcllean_remove_ros_arguments(b_lean_obj_arg args) {
  rcl_allocator_t allocator = rcl_get_default_allocator();
  size_t argc = 0;
  char const **argv = rcllean_argv_of(args, &argc);
  if (argc > 0 && argv == NULL) {
    RCLLEAN_FAIL("rcl_parse_arguments", "out of memory");
  }

  rcl_arguments_t parsed = rcl_get_zero_initialized_arguments();
  rcl_ret_t ret = rcl_parse_arguments((int)argc, argv, allocator, &parsed);
  if (ret != RCL_RET_OK) {
    free((void *)argv);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_parse_arguments", ret));
  }

  // rcl_remove_ros_arguments copies out of the original argv, so it has to
  // stay alive across this call.
  int nonros_argc = 0;
  const char **nonros_argv = NULL;
  ret = rcl_remove_ros_arguments(argv, &parsed, allocator, &nonros_argc,
                                 &nonros_argv);
  free((void *)argv);
  if (rcl_arguments_fini(&parsed) != RCL_RET_OK) {
    rcl_reset_error();
  }
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(
        rcllean_mk_error("rcl_remove_ros_arguments", ret));
  }

  lean_object *out = lean_alloc_array((size_t)nonros_argc, (size_t)nonros_argc);
  for (int i = 0; i < nonros_argc; ++i) {
    lean_array_set_core(out, (size_t)i, rcllean_mk_string(nonros_argv[i]));
  }
  if (nonros_argv != NULL) {
    allocator.deallocate((void *)nonros_argv, allocator.state);
  }
  return lean_io_result_mk_ok(out);
}

lean_object *rcllean_mk_raw_bytes(const uint8_t *data, size_t len) {
  lean_object *arr = lean_alloc_sarray(1, len, len);
  if (len > 0 && data != NULL) {
    memcpy(lean_sarray_cptr(arr), data, len);
  }
  return arr;
}
