// The handle tree: allocation, the single external class every rcl entity
// shares, and the child-before-parent teardown its finalizer runs.

#include "destroyable.h"

#include <pthread.h>
#include <stdlib.h>

// One recursive lock guards every parent/child link: tearing a handle down
// re-enters here for its children, and finalizers run on whichever thread
// drops the last reference.
static pthread_mutex_t g_tree_mutex;
static pthread_once_t g_tree_once = PTHREAD_ONCE_INIT;

static void rcllean_tree_init(void) {
  pthread_mutexattr_t attr;
  pthread_mutexattr_init(&attr);
  pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
  pthread_mutex_init(&g_tree_mutex, &attr);
  pthread_mutexattr_destroy(&attr);
}

static void rcllean_tree_lock(void) {
  pthread_once(&g_tree_once, rcllean_tree_init);
  pthread_mutex_lock(&g_tree_mutex);
}

static void rcllean_tree_unlock(void) { pthread_mutex_unlock(&g_tree_mutex); }

static rcllean_hdr *rcllean_parent_hdr(const rcllean_hdr *h) {
  return h->parent == NULL ? NULL : RCLLEAN_HDR(lean_get_external_data(h->parent));
}

static void rcllean_link_child(rcllean_hdr *parent, rcllean_hdr *child) {
  child->prev_sibling = NULL;
  child->next_sibling = parent->first_child;
  if (parent->first_child != NULL) {
    parent->first_child->prev_sibling = child;
  }
  parent->first_child = child;
}

static void rcllean_unlink_child(rcllean_hdr *parent, rcllean_hdr *child) {
  if (child->prev_sibling != NULL) {
    child->prev_sibling->next_sibling = child->next_sibling;
  } else {
    parent->first_child = child->next_sibling;
  }
  if (child->next_sibling != NULL) {
    child->next_sibling->prev_sibling = child->prev_sibling;
  }
  child->next_sibling = NULL;
  child->prev_sibling = NULL;
}

// Children first, then this handle's `fini`.  Each child unlinks itself, so
// the loop ends when the list empties.  `valid` is cleared before recursing,
// so a fini that reaches back in here does not loop.
static void rcllean_destroy_locked(rcllean_hdr *h) {
  if (!h->valid) {
    return;
  }
  h->valid = false;
  while (h->first_child != NULL) {
    rcllean_destroy_locked(h->first_child);
  }
  h->fini(h);
  rcllean_hdr *parent = rcllean_parent_hdr(h);
  if (parent != NULL) {
    rcllean_unlink_child(parent, h);
  }
}

void rcllean_handle_destroy(void *self) {
  rcllean_tree_lock();
  rcllean_destroy_locked(RCLLEAN_HDR(self));
  rcllean_tree_unlock();
}

// Runs when the last reference is dropped.  A live child holds a reference to
// its parent, so a parent reaching here has no children left.
static void rcllean_handle_finalize(void *self) {
  rcllean_hdr *h = RCLLEAN_HDR(self);
  rcllean_handle_destroy(self);
  if (h->parent != NULL) {
    lean_dec(h->parent);
    h->parent = NULL;
  }
  free(self);
}

// The parent is the only Lean object a handle references.
static void rcllean_handle_foreach(void *self, b_lean_obj_arg fn) {
  rcllean_hdr *h = RCLLEAN_HDR(self);
  if (h->parent != NULL) {
    lean_inc(fn);
    lean_inc(h->parent);
    lean_dec(lean_apply_1((lean_object *)fn, h->parent));
  }
}

// One external class for every handle type, registered once; the header's
// `fini` carries the type-specific teardown.
static lean_external_class *g_handle_class;
static pthread_once_t g_handle_class_once = PTHREAD_ONCE_INIT;

static void rcllean_handle_class_init(void) {
  g_handle_class = lean_register_external_class(rcllean_handle_finalize,
                                                rcllean_handle_foreach);
}

lean_object *rcllean_alloc_handle(size_t size, lean_object *parent,
                                  rcllean_fini_fn fini) {
  pthread_once(&g_handle_class_once, rcllean_handle_class_init);
  rcllean_hdr *h = (rcllean_hdr *)calloc(1, size);
  if (h == NULL) {
    return NULL;
  }
  h->fini = fini;
  h->valid = true;
  if (parent != NULL) {
    lean_inc(parent);
    h->parent = parent;
    rcllean_tree_lock();
    rcllean_link_child(rcllean_parent_hdr(h), h);
    rcllean_tree_unlock();
  }
  return lean_alloc_external(g_handle_class, h);
}

// Rcllean.FFI.handleIsValid : handle -> IO Bool, for any handle type.
LEAN_EXPORT lean_object *rcllean_handle_is_valid(b_lean_obj_arg h) {
  return lean_io_result_mk_ok(
      lean_box(RCLLEAN_HDR(lean_get_external_data(h))->valid ? 1 : 0));
}
