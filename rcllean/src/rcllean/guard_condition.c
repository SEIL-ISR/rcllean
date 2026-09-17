// Creating and triggering a guard condition, and registering one to be
// triggered when its context shuts down.  The registration lives here, not in
// context.c, because Lean declares it on GuardCondition for the same reason:
// the context cannot name the guard-condition handle type.

#include "guard_condition.h"

#include "context.h"
#include "exceptions.h"
#include "utils.h"

void rcllean_context_remove_shutdown_guard(rcllean_context_t *c,
                                           const rcl_guard_condition_t *gc) {
  rcllean_context_guards_lock();
  for (size_t i = 0; i < c->shutdown_guard_count; ++i) {
    if (c->shutdown_guards[i] == gc) {
      c->shutdown_guards[i] = c->shutdown_guards[c->shutdown_guard_count - 1];
      c->shutdown_guard_count--;
      break;
    }
  }
  rcllean_context_guards_unlock();
}

// Rcllean.FFI.contextAddShutdownGuard : Context -> GuardCondition -> IO Unit
//
// Executors register their wakeup here so Ctrl-C interrupts a blocking wait.
// The guard removes itself when torn down.
LEAN_EXPORT lean_object *rcllean_context_add_shutdown_guard(
    b_lean_obj_arg ctx, b_lean_obj_arg gc) {
  rcllean_context_t *c = rcllean_to_context(ctx);
  rcllean_guard_condition_t *g = rcllean_to_guard_condition(gc);
  RCLLEAN_REQUIRE_VALID(c, "contextAddShutdownGuard");
  RCLLEAN_REQUIRE_VALID(g, "contextAddShutdownGuard");
  if (g->hdr.parent != ctx) {
    RCLLEAN_FAIL("contextAddShutdownGuard",
                 "guard condition belongs to another context");
  }
  rcllean_context_guards_lock();
  bool room = c->shutdown_guard_count < RCLLEAN_MAX_SHUTDOWN_GUARDS;
  if (room) {
    c->shutdown_guards[c->shutdown_guard_count++] = &g->guard_condition;
  }
  rcllean_context_guards_unlock();
  if (!room) {
    RCLLEAN_FAIL("contextAddShutdownGuard", "too many registered guard conditions");
  }
  return rcllean_unit_ok();
}

static void rcllean_guard_condition_fini(void *self) {
  rcllean_guard_condition_t *g = (rcllean_guard_condition_t *)self;
  // The context may be triggering this guard on shutdown; take it out of that
  // list before the rcl object goes away.
  rcllean_context_remove_shutdown_guard(rcllean_to_context(g->hdr.parent),
                                        &g->guard_condition);
  if (rcl_guard_condition_fini(&g->guard_condition) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

// Rcllean.FFI.guardConditionCreate : Context -> IO GuardCondition
LEAN_EXPORT lean_object *rcllean_guard_condition_create(b_lean_obj_arg ctx) {
  rcllean_context_t *c = rcllean_to_context(ctx);
  RCLLEAN_REQUIRE_VALID(c, "rcl_guard_condition_init");
  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_guard_condition_t),
                                          (lean_object *)ctx,
                                          rcllean_guard_condition_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_guard_condition_init", "out of memory");
  }
  rcllean_guard_condition_t *g = rcllean_to_guard_condition(obj);
  g->guard_condition = rcl_get_zero_initialized_guard_condition();
  rcl_ret_t ret = rcl_guard_condition_init(
      &g->guard_condition, &c->context,
      rcl_guard_condition_get_default_options());
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(
        rcllean_mk_error("rcl_guard_condition_init", ret));
  }
  return lean_io_result_mk_ok(obj);
}

// Wake anything waiting on this guard.  Triggering a destroyed guard is a
// no-op.
LEAN_EXPORT lean_object *rcllean_guard_condition_trigger(b_lean_obj_arg gc) {
  rcllean_guard_condition_t *g = rcllean_to_guard_condition(gc);
  if (!g->hdr.valid) {
    return rcllean_unit_ok();
  }
  RCLLEAN_TRY("rcl_trigger_guard_condition",
              rcl_trigger_guard_condition(&g->guard_condition));
  return rcllean_unit_ok();
}
