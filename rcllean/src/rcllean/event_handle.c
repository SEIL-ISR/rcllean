// QoS events on a publisher or subscription: one handle per event kind, and
// the reduction of whatever status rcl reports to a count and a change.

#include "event_handle.h"

#include <string.h>

#include <rmw/events_statuses/events_statuses.h>

#include "exceptions.h"
#include "publisher.h"
#include "subscription.h"
#include "utils.h"

static void rcllean_event_fini(void *self) {
  rcllean_event_t *e = (rcllean_event_t *)self;
  if (rcl_event_fini(&e->event) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

static lean_object *rcllean_event_create(lean_object *parent, bool on_publisher,
                                         uint8_t kind, const char *fn) {
  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_event_t), parent,
                                          rcllean_event_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL(fn, "out of memory");
  }
  rcllean_event_t *e = rcllean_to_event(obj);
  e->event = rcl_get_zero_initialized_event();
  e->on_publisher = on_publisher;
  e->kind = kind;
  rcl_ret_t ret =
      on_publisher
          ? rcl_publisher_event_init(&e->event,
                                     &rcllean_to_publisher(parent)->publisher,
                                     (rcl_publisher_event_type_t)kind)
          : rcl_subscription_event_init(
                &e->event, &rcllean_to_subscription(parent)->subscription,
                (rcl_subscription_event_type_t)kind);
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error(fn, ret));
  }
  return lean_io_result_mk_ok(obj);
}

// Rcllean.FFI.publisherEventCreate : Publisher -> UInt8 -> IO Event
LEAN_EXPORT lean_object *rcllean_publisher_event_create(b_lean_obj_arg pub,
                                                        uint8_t kind) {
  RCLLEAN_REQUIRE_VALID(rcllean_to_publisher(pub), "rcl_publisher_event_init");
  return rcllean_event_create((lean_object *)pub, true, kind,
                              "rcl_publisher_event_init");
}

// Rcllean.FFI.subscriptionEventCreate : Subscription -> UInt8 -> IO Event
LEAN_EXPORT lean_object *rcllean_subscription_event_create(b_lean_obj_arg sub,
                                                           uint8_t kind) {
  RCLLEAN_REQUIRE_VALID(rcllean_to_subscription(sub),
                        "rcl_subscription_event_init");
  return rcllean_event_create((lean_object *)sub, false, kind,
                              "rcl_subscription_event_init");
}

// Rcllean.FFI.eventTake : Event -> IO (Option (Int32 × Int32))
//
// Each status reduces to a running count and the change since the last read;
// the rest of the struct is not exposed.  rcl writes the struct for this
// event's kind into a buffer big enough for any of them.
LEAN_EXPORT lean_object *rcllean_event_take(b_lean_obj_arg ev) {
  rcllean_event_t *e = rcllean_to_event(ev);
  RCLLEAN_REQUIRE_VALID(e, "rcl_take_event");
  union {
    rmw_offered_deadline_missed_status_t offered_deadline;
    rmw_liveliness_lost_status_t liveliness_lost;
    rmw_offered_qos_incompatible_event_status_t offered_incompatible;
    rmw_incompatible_type_status_t incompatible_type;
    rmw_matched_status_t matched;
    rmw_requested_deadline_missed_status_t requested_deadline;
    rmw_liveliness_changed_status_t liveliness_changed;
    rmw_requested_qos_incompatible_event_status_t requested_incompatible;
    rmw_message_lost_status_t lost;
  } s;
  memset(&s, 0, sizeof s);

  rcl_ret_t ret = rcl_take_event(&e->event, &s);
  if (ret == RCL_RET_EVENT_TAKE_FAILED) {
    rcl_reset_error();
    return lean_io_result_mk_ok(rcllean_none());
  }
  if (ret != RCL_RET_OK) {
    return lean_io_result_mk_error(rcllean_mk_error("rcl_take_event", ret));
  }

  int32_t total = 0, change = 0;
  if (e->on_publisher) {
    switch ((rcl_publisher_event_type_t)e->kind) {
      case RCL_PUBLISHER_OFFERED_DEADLINE_MISSED:
        total = s.offered_deadline.total_count;
        change = s.offered_deadline.total_count_change;
        break;
      case RCL_PUBLISHER_LIVELINESS_LOST:
        total = s.liveliness_lost.total_count;
        change = s.liveliness_lost.total_count_change;
        break;
      case RCL_PUBLISHER_OFFERED_INCOMPATIBLE_QOS:
        total = s.offered_incompatible.total_count;
        change = s.offered_incompatible.total_count_change;
        break;
      case RCL_PUBLISHER_INCOMPATIBLE_TYPE:
        total = s.incompatible_type.total_count;
        change = s.incompatible_type.total_count_change;
        break;
      case RCL_PUBLISHER_MATCHED:
        total = (int32_t)s.matched.total_count;
        change = (int32_t)s.matched.total_count_change;
        break;
    }
  } else {
    switch ((rcl_subscription_event_type_t)e->kind) {
      case RCL_SUBSCRIPTION_REQUESTED_DEADLINE_MISSED:
        total = s.requested_deadline.total_count;
        change = s.requested_deadline.total_count_change;
        break;
      case RCL_SUBSCRIPTION_LIVELINESS_CHANGED:
        total = s.liveliness_changed.alive_count;
        change = s.liveliness_changed.alive_count_change;
        break;
      case RCL_SUBSCRIPTION_REQUESTED_INCOMPATIBLE_QOS:
        total = s.requested_incompatible.total_count;
        change = s.requested_incompatible.total_count_change;
        break;
      case RCL_SUBSCRIPTION_MESSAGE_LOST:
        total = (int32_t)s.lost.total_count;
        change = (int32_t)s.lost.total_count_change;
        break;
      case RCL_SUBSCRIPTION_INCOMPATIBLE_TYPE:
        total = s.incompatible_type.total_count;
        change = s.incompatible_type.total_count_change;
        break;
      case RCL_SUBSCRIPTION_MATCHED:
        total = (int32_t)s.matched.total_count;
        change = (int32_t)s.matched.total_count_change;
        break;
    }
  }
  return lean_io_result_mk_ok(rcllean_some(rcllean_pair(
      lean_box_uint32((uint32_t)total), lean_box_uint32((uint32_t)change))));
}

LEAN_EXPORT lean_object *rcllean_event_destroy(b_lean_obj_arg ev) {
  rcllean_handle_destroy(rcllean_to_event(ev));
  return rcllean_unit_ok();
}
