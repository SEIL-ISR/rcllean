// Bringing a context up and down: rcl_init, rcl_shutdown, the domain id, and
// the list of guard conditions a shutdown triggers.

#include "context.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

#include <rcl/allocator.h>
#include <rcl/arguments.h>
#include <rcl/init.h>
#include <rcl/logging.h>
#include <rcl_yaml_param_parser/parser.h>

#include "exceptions.h"
#include "signal_handler.h"
#include "utils.h"

// Guards every context's list of shutdown guards, since the signal thread and
// guard_condition.c both reach into it.
static pthread_mutex_t g_ctx_mutex = PTHREAD_MUTEX_INITIALIZER;

void rcllean_context_guards_lock(void) { pthread_mutex_lock(&g_ctx_mutex); }

void rcllean_context_guards_unlock(void) { pthread_mutex_unlock(&g_ctx_mutex); }

// Wake everything registered for this context's shutdown.  rcl_shutdown
// invalidates the context but does not interrupt a blocked rcl_wait.  Caller
// holds g_ctx_mutex.
static void rcllean_trigger_shutdown_guards(rcllean_context_t *c) {
  for (size_t i = 0; i < c->shutdown_guard_count; ++i) {
    if (rcl_trigger_guard_condition(c->shutdown_guards[i]) != RCL_RET_OK) {
      rcl_reset_error();
    }
  }
}

void rcllean_context_signal_shutdown(rcllean_context_t *c) {
  rcllean_context_guards_lock();
  if (c->hdr.valid && rcl_context_is_valid(&c->context)) {
    if (rcl_shutdown(&c->context) != RCL_RET_OK) {
      rcl_reset_error();
    }
    rcllean_trigger_shutdown_guards(c);
  }
  rcllean_context_guards_unlock();
}

static void rcllean_context_fini(void *self) {
  rcllean_context_t *c = (rcllean_context_t *)self;
  rcllean_signal_unregister(c);
  if (c->param_overrides != NULL) {
    rcl_yaml_node_struct_fini((rcl_params_t *)c->param_overrides);
    c->param_overrides = NULL;
  }
  if (rcl_context_is_valid(&c->context)) {
    if (rcl_shutdown(&c->context) != RCL_RET_OK) {
      rcl_reset_error();
    }
  }
  if (rcl_context_fini(&c->context) != RCL_RET_OK) {
    rcl_reset_error();
  }
  if (c->init_options_valid) {
    if (rcl_init_options_fini(&c->init_options) != RCL_RET_OK) {
      rcl_reset_error();
    }
    c->init_options_valid = false;
  }
}

// Rcllean.FFI.contextInit :
// Array String -> Bool -> UInt64 -> Bool -> IO Context
//
// `args` is the full command line including argv[0].  The domain id crosses
// as a flag plus a value so the boundary carries only scalars.
// `installSignalHandlers` controls whether Ctrl-C shuts this context down.
LEAN_EXPORT lean_object *rcllean_context_init(b_lean_obj_arg args,
                                              uint8_t has_domain_id,
                                              uint64_t domain_id,
                                              uint8_t install_handlers) {
  rcl_allocator_t allocator = rcl_get_default_allocator();

  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_context_t), NULL,
                                          rcllean_context_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_init", "out of memory");
  }
  rcllean_context_t *c = rcllean_to_context(obj);
  c->context = rcl_get_zero_initialized_context();
  c->init_options = rcl_get_zero_initialized_init_options();

  rcl_ret_t ret = rcl_init_options_init(&c->init_options, allocator);
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_init_options_init", ret));
  }
  c->init_options_valid = true;

  if (has_domain_id) {
    ret = rcl_init_options_set_domain_id(&c->init_options, (size_t)domain_id);
    if (ret != RCL_RET_OK) {
      lean_dec_ref(obj);
      return lean_io_result_mk_error(
          rcllean_mk_error("rcl_init_options_set_domain_id", ret));
    }
  }

  size_t argc = 0;
  char const **argv = rcllean_argv_of(args, &argc);
  if (argc > 0 && argv == NULL) {
    lean_dec_ref(obj);
    RCLLEAN_FAIL("rcl_init", "out of memory building argv");
  }

  ret = rcl_init((int)argc, argv, &c->init_options, &c->context);
  free((void *)argv);
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_init", ret));
  }

  // Configure logging from --ros-args (--log-level, --log-file-name, ...).
  // Safe to call once per process; rcl guards repeat calls internally.
  ret = rcl_logging_configure(&c->context.global_arguments, &allocator);
  if (ret != RCL_RET_OK) {
    // Not fatal, but silence would leave /rosout mysteriously empty.
    fprintf(stderr, "rcllean: rcl_logging_configure failed (%d): %s\n", ret,
            rcl_error_is_set() ? rcl_get_error_string().str : "no detail");
    rcl_reset_error();
  }

  rcllean_signal_register(c);
  if (install_handlers) {
    rcllean_signal_install_handlers();
  }
  return lean_io_result_mk_ok(obj);
}

// Rcllean.FFI.contextShutdown : Context -> IO Unit.  Idempotent.
LEAN_EXPORT lean_object *rcllean_context_shutdown(b_lean_obj_arg ctx) {
  rcllean_context_t *c = rcllean_to_context(ctx);
  if (!c->hdr.valid || !rcl_context_is_valid(&c->context)) {
    return rcllean_unit_ok();
  }
  RCLLEAN_TRY("rcl_shutdown", rcl_shutdown(&c->context));
  rcllean_context_guards_lock();
  rcllean_trigger_shutdown_guards(c);
  rcllean_context_guards_unlock();
  return rcllean_unit_ok();
}

// Rcllean.FFI.contextOk : Context -> IO Bool
LEAN_EXPORT lean_object *rcllean_context_ok(b_lean_obj_arg ctx) {
  rcllean_context_t *c = rcllean_to_context(ctx);
  bool ok = c->hdr.valid && rcl_context_is_valid(&c->context);
  return lean_io_result_mk_ok(lean_box(ok ? 1 : 0));
}

// Rcllean.FFI.contextDomainId : Context -> IO UInt64
LEAN_EXPORT lean_object *rcllean_context_domain_id(b_lean_obj_arg ctx) {
  rcllean_context_t *c = rcllean_to_context(ctx);
  RCLLEAN_REQUIRE_VALID(c, "rcl_context_get_domain_id");
  size_t domain_id = 0;
  RCLLEAN_TRY("rcl_context_get_domain_id",
              rcl_context_get_domain_id(&c->context, &domain_id));
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)domain_id));
}
