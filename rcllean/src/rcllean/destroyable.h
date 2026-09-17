// The header every rcl entity starts with: a Lean external object in a
// parent/child tree, so teardown runs child before parent and stays
// idempotent.  rclpy calls the same idea Destroyable.

#ifndef RCLLEAN_DESTROYABLE_H
#define RCLLEAN_DESTROYABLE_H

#include <lean/lean.h>
#include <stdbool.h>
#include <stddef.h>

#include "exceptions.h"

typedef struct rcllean_hdr rcllean_hdr;

// Type-specific rcl teardown.  Runs once per handle, after its children and
// before its parent.  Must reset any rcl error it ignores.
typedef void (*rcllean_fini_fn)(void *self);

// Common prefix of every handle struct.
struct rcllean_hdr {
  // Strong reference to the owner (a node's context, a publisher's node), or
  // NULL.  Released last, after `fini`.
  lean_object *parent;
  rcllean_fini_fn fini;
  // Live children, torn down before this handle.
  rcllean_hdr *first_child;
  rcllean_hdr *next_sibling;
  rcllean_hdr *prev_sibling;
  // Cleared by the first teardown, so `destroy` is idempotent.
  bool valid;
};

// Allocate a zeroed handle of `size` bytes as a Lean external object, taking a
// reference to `parent` and registering the handle as its child.  NULL when
// out of memory.
lean_object *rcllean_alloc_handle(size_t size, lean_object *parent,
                                  rcllean_fini_fn fini);

// Tear a handle down now: its children first, then its own `fini`.
// Idempotent, and thread safe with respect to other teardowns.
void rcllean_handle_destroy(void *self);

#define RCLLEAN_HDR(p) ((rcllean_hdr *)(p))

#define RCLLEAN_TO(type, o) ((type *)lean_get_external_data(o))

// Refuse to touch an rcl struct that has already been torn down.
#define RCLLEAN_REQUIRE_VALID(h, fnname)                                       \
  do {                                                                         \
    if (!RCLLEAN_HDR(h)->valid) {                                              \
      RCLLEAN_FAIL(fnname, "handle has been destroyed");                       \
    }                                                                          \
  } while (0)

#endif // RCLLEAN_DESTROYABLE_H
