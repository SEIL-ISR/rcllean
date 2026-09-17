// The wait set: sizing it, blocking on it, and the two macro families that
// add an entity to a slot and read that slot back after a wait.

#include "wait_set.h"

#include "client.h"
#include "context.h"
#include "event_handle.h"
#include "exceptions.h"
#include "guard_condition.h"
#include "service.h"
#include "subscription.h"
#include "timer.h"
#include "utils.h"

static void rcllean_wait_set_fini(void *self) {
  rcllean_wait_set_t *ws = (rcllean_wait_set_t *)self;
  if (rcl_wait_set_fini(&ws->wait_set) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

// Rcllean.FFI.waitSetCreate : Context -> counts... -> IO WaitSet
LEAN_EXPORT lean_object *rcllean_wait_set_create(
    b_lean_obj_arg ctx, uint64_t n_subs, uint64_t n_guards, uint64_t n_timers,
    uint64_t n_clients, uint64_t n_services, uint64_t n_events) {
  rcllean_context_t *c = rcllean_to_context(ctx);
  RCLLEAN_REQUIRE_VALID(c, "rcl_wait_set_init");
  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_wait_set_t),
                                          (lean_object *)ctx,
                                          rcllean_wait_set_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_wait_set_init", "out of memory");
  }
  rcllean_wait_set_t *ws = rcllean_to_wait_set(obj);
  ws->wait_set = rcl_get_zero_initialized_wait_set();
  rcl_ret_t ret = rcl_wait_set_init(
      &ws->wait_set, (size_t)n_subs, (size_t)n_guards, (size_t)n_timers,
      (size_t)n_clients, (size_t)n_services, (size_t)n_events, &c->context,
      rcl_get_default_allocator());
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_wait_set_init", ret));
  }
  return lean_io_result_mk_ok(obj);
}

// Resize in place, so the executor reuses one wait set across iterations.
LEAN_EXPORT lean_object *rcllean_wait_set_resize(
    b_lean_obj_arg ws_obj, uint64_t n_subs, uint64_t n_guards,
    uint64_t n_timers, uint64_t n_clients, uint64_t n_services,
    uint64_t n_events) {
  rcllean_wait_set_t *ws = rcllean_to_wait_set(ws_obj);
  RCLLEAN_REQUIRE_VALID(ws, "rcl_wait_set_resize");
  RCLLEAN_TRY("rcl_wait_set_resize",
              rcl_wait_set_resize(&ws->wait_set, (size_t)n_subs,
                                  (size_t)n_guards, (size_t)n_timers,
                                  (size_t)n_clients, (size_t)n_services,
                                  (size_t)n_events));
  return rcllean_unit_ok();
}

LEAN_EXPORT lean_object *rcllean_wait_set_clear(b_lean_obj_arg ws_obj) {
  rcllean_wait_set_t *ws = rcllean_to_wait_set(ws_obj);
  RCLLEAN_REQUIRE_VALID(ws, "rcl_wait_set_clear");
  RCLLEAN_TRY("rcl_wait_set_clear", rcl_wait_set_clear(&ws->wait_set));
  return rcllean_unit_ok();
}

// Rcllean.FFI.waitSetWait : WaitSet -> Int64 -> IO Bool
//
// A negative timeout blocks until something is ready; zero polls.  A timeout
// returns false rather than raising.
LEAN_EXPORT lean_object *rcllean_wait_set_wait(b_lean_obj_arg ws_obj,
                                               int64_t timeout_ns) {
  rcllean_wait_set_t *ws = rcllean_to_wait_set(ws_obj);
  RCLLEAN_REQUIRE_VALID(ws, "rcl_wait");
  rcl_ret_t ret = rcl_wait(&ws->wait_set, timeout_ns);
  if (ret == RCL_RET_TIMEOUT) {
    rcl_reset_error();
    return lean_io_result_mk_ok(lean_box(0));
  }
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(rcllean_mk_error("rcl_wait", ret));
  }
  return lean_io_result_mk_ok(lean_box(1));
}

// Each add returns the slot index readiness is later queried by.  A destroyed
// entity is refused rather than handed to rcl.  `w` is the IO world token
// Lean passes to a non-`b_lean_obj_arg` entry point; it is never read.
#define RCLLEAN_WAIT_SET_ADD(fnname, rcl_fn, handle_t, to_handle, member)      \
  LEAN_EXPORT lean_object *fnname(b_lean_obj_arg ws_obj, b_lean_obj_arg h,     \
                                  lean_object *w) {                            \
    rcllean_wait_set_t *ws = rcllean_to_wait_set(ws_obj);                      \
    handle_t *e = to_handle(h);                                                \
    RCLLEAN_REQUIRE_VALID(ws, #rcl_fn);                                        \
    RCLLEAN_REQUIRE_VALID(e, #rcl_fn);                                         \
    size_t index = 0;                                                          \
    RCLLEAN_TRY(#rcl_fn, rcl_fn(&ws->wait_set, &e->member, &index));           \
    return lean_io_result_mk_ok(lean_box_uint64((uint64_t)index));             \
  }

RCLLEAN_WAIT_SET_ADD(rcllean_wait_set_add_subscription,
                     rcl_wait_set_add_subscription, rcllean_subscription_t,
                     rcllean_to_subscription, subscription)
RCLLEAN_WAIT_SET_ADD(rcllean_wait_set_add_timer, rcl_wait_set_add_timer,
                     rcllean_timer_t, rcllean_to_timer, timer)
RCLLEAN_WAIT_SET_ADD(rcllean_wait_set_add_guard_condition,
                     rcl_wait_set_add_guard_condition,
                     rcllean_guard_condition_t, rcllean_to_guard_condition,
                     guard_condition)
RCLLEAN_WAIT_SET_ADD(rcllean_wait_set_add_service, rcl_wait_set_add_service,
                     rcllean_service_t, rcllean_to_service, service)
RCLLEAN_WAIT_SET_ADD(rcllean_wait_set_add_client, rcl_wait_set_add_client,
                     rcllean_client_t, rcllean_to_client, client)
RCLLEAN_WAIT_SET_ADD(rcllean_wait_set_add_event, rcl_wait_set_add_event,
                     rcllean_event_t, rcllean_to_event, event)

// After a wait, a slot holds NULL for an entity that is not ready.
#define RCLLEAN_WAIT_SET_READY(fnname, field, count_field)                     \
  LEAN_EXPORT lean_object *fnname(b_lean_obj_arg ws_obj, uint64_t index,       \
                                  lean_object *w) {                            \
    rcllean_wait_set_t *ws = rcllean_to_wait_set(ws_obj);                      \
    bool ready = ws->hdr.valid && index < ws->wait_set.count_field &&          \
                 ws->wait_set.field[index] != NULL;                            \
    return lean_io_result_mk_ok(lean_box(ready ? 1 : 0));                      \
  }

RCLLEAN_WAIT_SET_READY(rcllean_wait_set_subscription_ready, subscriptions,
                       size_of_subscriptions)
RCLLEAN_WAIT_SET_READY(rcllean_wait_set_timer_ready, timers, size_of_timers)
RCLLEAN_WAIT_SET_READY(rcllean_wait_set_guard_condition_ready,
                       guard_conditions, size_of_guard_conditions)
RCLLEAN_WAIT_SET_READY(rcllean_wait_set_service_ready, services,
                       size_of_services)
RCLLEAN_WAIT_SET_READY(rcllean_wait_set_client_ready, clients, size_of_clients)
RCLLEAN_WAIT_SET_READY(rcllean_wait_set_event_ready, events, size_of_events)
