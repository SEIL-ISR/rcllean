// The rcl clock: creation per time source, reading it, and the ROS time
// override a simulation drives.

#include "clock.h"

#include "exceptions.h"
#include "utils.h"

static void rcllean_clock_fini(void *self) {
  rcllean_clock_t *c = (rcllean_clock_t *)self;
  if (rcl_clock_fini(&c->clock) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

// Rcllean.FFI.clockCreate : UInt8 -> IO Clock
// 1 = ROS time, 2 = system time, 3 = steady time.
LEAN_EXPORT lean_object *rcllean_clock_create(uint8_t clock_type) {
  rcl_allocator_t allocator = rcl_get_default_allocator();
  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_clock_t), NULL,
                                          rcllean_clock_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("rcl_clock_init", "out of memory");
  }
  rcllean_clock_t *c = rcllean_to_clock(obj);
  rcl_ret_t ret = rcl_clock_init((rcl_clock_type_t)clock_type, &c->clock,
                                 &allocator);
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_clock_init", ret));
  }
  return lean_io_result_mk_ok(obj);
}

// Rcllean.FFI.clockNow : Clock -> IO Int64  (nanoseconds since the epoch)
LEAN_EXPORT lean_object *rcllean_clock_now(b_lean_obj_arg clock) {
  rcllean_clock_t *c = rcllean_to_clock(clock);
  RCLLEAN_REQUIRE_VALID(c, "rcl_clock_get_now");
  rcl_time_point_value_t now = 0;
  RCLLEAN_TRY("rcl_clock_get_now", rcl_clock_get_now(&c->clock, &now));
  return lean_io_result_mk_ok(lean_box_uint64((uint64_t)now));
}

// Rcllean.FFI.clockType : Clock -> IO UInt8
LEAN_EXPORT lean_object *rcllean_clock_type(b_lean_obj_arg clock) {
  rcllean_clock_t *c = rcllean_to_clock(clock);
  return lean_io_result_mk_ok(lean_box((uint8_t)c->clock.type));
}

// Rcllean.FFI.clockIsValid : Clock -> IO Bool
LEAN_EXPORT lean_object *rcllean_clock_is_valid(b_lean_obj_arg clock) {
  rcllean_clock_t *c = rcllean_to_clock(clock);
  bool ok = c->hdr.valid && rcl_clock_valid(&c->clock);
  return lean_io_result_mk_ok(lean_box(ok ? 1 : 0));
}

// Rcllean.FFI.clockEnableRosTimeOverride : Clock -> Bool -> IO Unit
LEAN_EXPORT lean_object *rcllean_clock_enable_ros_time_override(
    b_lean_obj_arg clock, uint8_t enable) {
  rcllean_clock_t *c = rcllean_to_clock(clock);
  RCLLEAN_REQUIRE_VALID(c, "rcl_enable_ros_time_override");
  if (enable) {
    RCLLEAN_TRY("rcl_enable_ros_time_override",
                rcl_enable_ros_time_override(&c->clock));
  } else {
    RCLLEAN_TRY("rcl_disable_ros_time_override",
                rcl_disable_ros_time_override(&c->clock));
  }
  return rcllean_unit_ok();
}

// Rcllean.FFI.clockSetRosTimeOverride : Clock -> Int64 -> IO Unit
LEAN_EXPORT lean_object *rcllean_clock_set_ros_time_override(
    b_lean_obj_arg clock, int64_t nanos) {
  rcllean_clock_t *c = rcllean_to_clock(clock);
  RCLLEAN_REQUIRE_VALID(c, "rcl_set_ros_time_override");
  RCLLEAN_TRY("rcl_set_ros_time_override",
              rcl_set_ros_time_override(&c->clock, (rcl_time_point_value_t)nanos));
  return rcllean_unit_ok();
}

// Rcllean.FFI.clockRosTimeOverrideIsEnabled : Clock -> IO Bool
LEAN_EXPORT lean_object *rcllean_clock_ros_time_override_is_enabled(
    b_lean_obj_arg clock) {
  rcllean_clock_t *c = rcllean_to_clock(clock);
  RCLLEAN_REQUIRE_VALID(c, "rcl_is_enabled_ros_time_override");
  bool enabled = false;
  RCLLEAN_TRY("rcl_is_enabled_ros_time_override",
              rcl_is_enabled_ros_time_override(&c->clock, &enabled));
  return lean_io_result_mk_ok(lean_box(enabled ? 1 : 0));
}
