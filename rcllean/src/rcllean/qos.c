// Building an rmw QoS profile out of the scalars the Lean structure crosses
// the boundary as.

#include "qos.h"

#include <stdint.h>

#include "exceptions.h"

// A QoS handle owns nothing beyond its own struct.
static void rcllean_qos_fini(void *self) { (void)self; }

// Zero means "leave it to the middleware", as RMW_QOS_DEADLINE_DEFAULT and
// friends are encoded.
static rmw_time_t rcllean_time_of_nanos(int64_t nanos) {
  rmw_time_t t;
  if (nanos <= 0) {
    t.sec = 0;
    t.nsec = 0;
    return t;
  }
  t.sec = (uint64_t)(nanos / 1000000000);
  t.nsec = (uint64_t)(nanos % 1000000000);
  return t;
}

// Rcllean.FFI.qosCreate : UInt8 -> UInt64 -> UInt8 -> UInt8 -> Int64 ->
// Int64 -> UInt8 -> Int64 -> Bool -> IO QoS
//
// Every policy crosses as a scalar; the Lean layout is not assumed here.
LEAN_EXPORT lean_object *rcllean_qos_create(
    uint8_t history, uint64_t depth, uint8_t reliability, uint8_t durability,
    uint64_t deadline_ns, uint64_t lifespan_ns, uint8_t liveliness,
    uint64_t lease_ns, uint8_t avoid_ros_conventions) {
  lean_object *obj =
      rcllean_alloc_handle(sizeof(rcllean_qos_t), NULL, rcllean_qos_fini);
  if (obj == NULL) {
    RCLLEAN_FAIL("qosCreate", "out of memory");
  }
  rcllean_qos_t *h = rcllean_to_qos(obj);
  h->qos.history = (enum rmw_qos_history_policy_e)history;
  h->qos.depth = (size_t)depth;
  h->qos.reliability = (enum rmw_qos_reliability_policy_e)reliability;
  h->qos.durability = (enum rmw_qos_durability_policy_e)durability;
  h->qos.deadline = rcllean_time_of_nanos((int64_t)deadline_ns);
  h->qos.lifespan = rcllean_time_of_nanos((int64_t)lifespan_ns);
  h->qos.liveliness = (enum rmw_qos_liveliness_policy_e)liveliness;
  h->qos.liveliness_lease_duration = rcllean_time_of_nanos((int64_t)lease_ns);
  h->qos.avoid_ros_namespace_conventions = avoid_ros_conventions != 0;
  return lean_io_result_mk_ok(obj);
}
