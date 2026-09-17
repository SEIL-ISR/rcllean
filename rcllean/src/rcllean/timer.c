// The periodic timer: creation against a clock and a context, readiness, and
// the period controls the executor drives it with.

#include "timer.h"

#include "clock.h"
#include "context.h"
#include "exceptions.h"
#include "utils.h"

static void rcllean_timer_fini(void *self) {
  rcllean_timer_t *t = (rcllean_timer_t *)self;
  if (rcl_timer_fini(&t->timer) != RCL_RET_OK) {
    rcl_reset_error();
  }
  // rcl is done with the clock only now.  A fini runs once per handle, so
  // this releases the reference exactly once.
  if (t->clock != NULL) {
    lean_dec_ref(t->clock);
    t->clock = NULL;
  }
}

// Rcllean.FFI.timerCreate : Context -> Clock -> Int64 -> Bool -> IO Timer
//
// No C callback is registered: the executor polls readiness and calls
// rcl_timer_call itself.
LEAN_EXPORT lean_object *rcllean_timer_create(b_lean_obj_arg ctx,
                                              b_lean_obj_arg clock,
                                              int64_t period_ns,
                                              uint8_t autostart) {
  rcllean_context_t *c = rcllean_to_context(ctx);
  rcllean_clock_t *cl = rcllean_to_clock(clock);
  RCLLEAN_REQUIRE_VALID(c, "rcl_timer_init2");
  RCLLEAN_REQUIRE_VALID(cl, "rcl_timer_init2");

  // The context is the parent: rcl_timer_init2 puts a guard condition of its
  // own inside the context, and rcl_timer_fini must run before the context
  // goes away.  The clock gets its own reference, released in the fini.
  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_timer_t),
                                          (lean_object *)ctx,
                                          rcllean_timer_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_timer_init2", "out of memory");
  }
  rcllean_timer_t *t = rcllean_to_timer(obj);
  lean_inc_ref((lean_object *)clock);
  t->clock = (lean_object *)clock;
  t->timer = rcl_get_zero_initialized_timer();
  rcl_ret_t ret = rcl_timer_init2(&t->timer, &cl->clock, &c->context, period_ns,
                                  NULL, rcl_get_default_allocator(),
                                  autostart != 0);
  if (ret != RCL_RET_OK) {
    // The fini releases the clock reference taken above.
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_timer_init2", ret));
  }
  return lean_io_result_mk_ok(obj);
}

LEAN_EXPORT lean_object *rcllean_timer_is_ready(b_lean_obj_arg timer) {
  rcllean_timer_t *t = rcllean_to_timer(timer);
  RCLLEAN_REQUIRE_VALID(t, "rcl_timer_is_ready");
  bool ready = false;
  RCLLEAN_TRY("rcl_timer_is_ready", rcl_timer_is_ready(&t->timer, &ready));
  return lean_io_result_mk_ok(lean_box(ready ? 1 : 0));
}

// Mark the timer as having fired, resetting it for the next period.  A
// cancelled timer reports `false` rather than failing.
LEAN_EXPORT lean_object *rcllean_timer_call(b_lean_obj_arg timer) {
  rcllean_timer_t *t = rcllean_to_timer(timer);
  RCLLEAN_REQUIRE_VALID(t, "rcl_timer_call");
  rcl_ret_t ret = rcl_timer_call(&t->timer);
  if (ret == RCL_RET_TIMER_CANCELED) {
    rcl_reset_error();
    return lean_io_result_mk_ok(lean_box(0));
  }
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(rcllean_mk_error("rcl_timer_call", ret));
  }
  return lean_io_result_mk_ok(lean_box(1));
}

// Nanoseconds until the next firing; negative if it is overdue.
LEAN_EXPORT lean_object *rcllean_timer_time_until_next_call(
    b_lean_obj_arg timer) {
  rcllean_timer_t *t = rcllean_to_timer(timer);
  RCLLEAN_REQUIRE_VALID(t, "rcl_timer_get_time_until_next_call");
  int64_t remaining = 0;
  RCLLEAN_TRY("rcl_timer_get_time_until_next_call",
              rcl_timer_get_time_until_next_call(&t->timer, &remaining));
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)remaining));
}

LEAN_EXPORT lean_object *rcllean_timer_cancel(b_lean_obj_arg timer) {
  rcllean_timer_t *t = rcllean_to_timer(timer);
  RCLLEAN_REQUIRE_VALID(t, "rcl_timer_cancel");
  RCLLEAN_TRY("rcl_timer_cancel", rcl_timer_cancel(&t->timer));
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_timer_reset(b_lean_obj_arg timer) {
  rcllean_timer_t *t = rcllean_to_timer(timer);
  RCLLEAN_REQUIRE_VALID(t, "rcl_timer_reset");
  RCLLEAN_TRY("rcl_timer_reset", rcl_timer_reset(&t->timer));
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_timer_is_canceled(b_lean_obj_arg timer) {
  rcllean_timer_t *t = rcllean_to_timer(timer);
  RCLLEAN_REQUIRE_VALID(t, "rcl_timer_is_canceled");
  bool canceled = false;
  RCLLEAN_TRY("rcl_timer_is_canceled",
              rcl_timer_is_canceled(&t->timer, &canceled));
  return lean_io_result_mk_ok(lean_box(canceled ? 1 : 0));
}

// Returns the previous period in nanoseconds.
LEAN_EXPORT lean_object *rcllean_timer_set_period(b_lean_obj_arg timer,
                                                  int64_t period_ns) {
  rcllean_timer_t *t = rcllean_to_timer(timer);
  RCLLEAN_REQUIRE_VALID(t, "rcl_timer_exchange_period");
  int64_t old = 0;
  RCLLEAN_TRY("rcl_timer_exchange_period",
              rcl_timer_exchange_period(&t->timer, period_ns, &old));
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)old));
}

LEAN_EXPORT lean_object *rcllean_timer_destroy(b_lean_obj_arg timer) {
  rcllean_handle_destroy(rcllean_to_timer(timer));
  return rcllean_unit_ok();
}
