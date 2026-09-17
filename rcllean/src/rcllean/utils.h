// What the rest of the shim needs from utils.c: string, byte and argv
// conversions, plus the Option and pair constructors every entry point
// returning one of those shares.

#ifndef RCLLEAN_UTILS_H
#define RCLLEAN_UTILS_H

#include <lean/lean.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "destroyable.h"

// Copy a borrowed C string into a fresh Lean string.  NULL becomes "".
lean_object *rcllean_mk_string(const char *s);

// Copy `len` bytes into a fresh Lean string.  Ill-formed UTF-8 becomes U+FFFD.
lean_object *rcllean_mk_string_n(const char *s, size_t len);

// Copy `len` bytes into a fresh Lean ByteArray.
lean_object *rcllean_mk_raw_bytes(const uint8_t *data, size_t len);

// Lean `Array String` to a NULL-terminated argv.  Caller frees the outer
// array; the strings are borrowed from `args`.
char const **rcllean_argv_of(b_lean_obj_arg args, size_t *out_argc);

static inline lean_object *rcllean_unit_ok(void) {
  return lean_io_result_mk_ok(lean_box(0));
}

// `Option` and pair constructors.  A Lean pair is polymorphic, so its fields
// are boxed objects even when the types are scalars.
static inline lean_object *rcllean_none(void) { return lean_box(0); }
static inline lean_object *rcllean_some(lean_object *v) {
  lean_object *o = lean_alloc_ctor(1, 1, 0);
  lean_ctor_set(o, 0, v);
  return o;
}
static inline lean_object *rcllean_pair(lean_object *a, lean_object *b) {
  lean_object *o = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(o, 0, a);
  lean_ctor_set(o, 1, b);
  return o;
}

#endif // RCLLEAN_UTILS_H
