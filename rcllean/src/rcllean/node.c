// The rcl node: creation with its own `--ros-args`, the /rosout publisher it
// owns, the name getters, and the parameter overrides a node reads off its
// context.

#include "node.h"

#include <stdlib.h>
#include <string.h>

#include <rcl/allocator.h>
#include <rcl/arguments.h>
#include <rcl/logging.h>
#include <rcl/logging_rosout.h>
#include <rcl/node_options.h>
#include <rcl_yaml_param_parser/types.h>

#include "context.h"
#include "exceptions.h"
#include "utils.h"

static void rcllean_node_fini(void *self) {
  rcllean_node_t *n = (rcllean_node_t *)self;
  if (n->rosout_publisher) {
    // Must go before rcl_node_fini: the publisher belongs to the node.
    if (rcl_logging_rosout_fini_publisher_for_node(&n->node) != RCL_RET_OK) {
      rcl_reset_error();
    }
    n->rosout_publisher = false;
  }
  if (rcl_node_fini(&n->node) != RCL_RET_OK) {
    rcl_reset_error();
  }
}

// Rcllean.FFI.nodeCreate :
// Context -> String -> String -> Bool -> Bool -> Array String -> IO Node
//
// The trailing arguments are `useGlobalArguments`, `enableRosout` and
// node-specific `--ros-args`.
LEAN_EXPORT lean_object *rcllean_node_create(b_lean_obj_arg ctx,
                                             b_lean_obj_arg name,
                                             b_lean_obj_arg ns,
                                             uint8_t use_global_args,
                                             uint8_t enable_rosout,
                                             b_lean_obj_arg args) {
  rcllean_context_t *c = rcllean_to_context(ctx);
  if (!c->hdr.valid || !rcl_context_is_valid(&c->context)) {
    RCLLEAN_FAIL("rcl_node_init", "context is not valid");
  }

  rcl_node_options_t options = rcl_node_get_default_options();
  options.use_global_arguments = use_global_args != 0;
  options.enable_rosout = enable_rosout != 0;

  bool args_parsed = false;
  size_t argc = lean_array_size(args);
  if (argc > 0) {
    char const **argv = (char const **)calloc(argc + 1, sizeof(char *));
    if (argv == NULL) {
      RCLLEAN_FAIL("rcl_node_init", "out of memory");
    }
    for (size_t i = 0; i < argc; ++i) {
      argv[i] = lean_string_cstr(lean_array_get_core(args, i));
    }
    rcl_ret_t pret = rcl_parse_arguments((int)argc, argv,
                                         rcl_get_default_allocator(),
                                         &options.arguments);
    free((void *)argv);
    if (pret != RCL_RET_OK) {
      return lean_io_result_mk_error(
          rcllean_mk_error("rcl_parse_arguments", pret));
    }
    args_parsed = true;
  }

  lean_object *obj = rcllean_alloc_handle(sizeof(rcllean_node_t),
                                          (lean_object *)ctx, rcllean_node_fini);
  if (obj == NULL) {
    if (args_parsed && rcl_arguments_fini(&options.arguments) != RCL_RET_OK) {
      rcl_reset_error();
    }
    RCLLEAN_FAIL("rcl_node_init", "out of memory");
  }
  rcllean_node_t *n = rcllean_to_node(obj);
  n->node = rcl_get_zero_initialized_node();

  rcl_ret_t ret = rcl_node_init(&n->node, lean_string_cstr(name),
                                lean_string_cstr(ns), &c->context, &options);
  // rcl_node_init copies the parsed arguments, so they can be released on
  // either outcome.
  if (args_parsed && rcl_arguments_fini(&options.arguments) != RCL_RET_OK) {
    rcl_reset_error();
  }
  if (ret != RCL_RET_OK) {
    lean_dec_ref(obj);
    return lean_io_result_mk_error(rcllean_mk_error("rcl_node_init", ret));
  }

  // rcl_node_init does not attach the /rosout publisher; each client library
  // asks for one.  Failing to get it still leaves a usable node.
  if (options.enable_rosout && rcl_logging_rosout_enabled()) {
    if (rcl_logging_rosout_init_publisher_for_node(&n->node) == RCL_RET_OK) {
      n->rosout_publisher = true;
    } else {
      rcl_reset_error();
    }
  }
  return lean_io_result_mk_ok(obj);
}

// Rcllean.FFI.nodeDestroy : Node -> IO Unit.  Idempotent; tears down every
// entity created on the node first.
LEAN_EXPORT lean_object *rcllean_node_destroy(b_lean_obj_arg node) {
  rcllean_handle_destroy(rcllean_to_node(node));
  return rcllean_unit_ok();
}

// Rcllean.FFI.nodeIsValid : Node -> IO Bool
LEAN_EXPORT lean_object *rcllean_node_is_valid(b_lean_obj_arg node) {
  rcllean_node_t *n = rcllean_to_node(node);
  bool ok = n->hdr.valid && rcl_node_is_valid(&n->node);
  return lean_io_result_mk_ok(lean_box(ok ? 1 : 0));
}

#define RCLLEAN_NODE_GETTER(lean_fn, rcl_fn)                                  \
  LEAN_EXPORT lean_object *lean_fn(b_lean_obj_arg node) {      \
    rcllean_node_t *n = rcllean_to_node(node);                                 \
    RCLLEAN_REQUIRE_VALID(n, #rcl_fn);                                         \
    const char *s = rcl_fn(&n->node);                                          \
    if (s == NULL) {                                                           \
      RCLLEAN_FAIL(#rcl_fn, "node is not valid");                              \
    }                                                                          \
    return lean_io_result_mk_ok(rcllean_mk_string(s));                         \
  }

RCLLEAN_NODE_GETTER(rcllean_node_get_name, rcl_node_get_name)
RCLLEAN_NODE_GETTER(rcllean_node_get_namespace, rcl_node_get_namespace)
RCLLEAN_NODE_GETTER(rcllean_node_get_fully_qualified_name,
                    rcl_node_get_fully_qualified_name)
RCLLEAN_NODE_GETTER(rcllean_node_logger_name, rcl_node_get_logger_name)

// Parameter overrides: what rcl parsed out of `--ros-args`, handed to Lean
// one value at a time as an rcl_interfaces/msg/ParameterValue.

static const rcl_params_t *rcllean_overrides(rcllean_context_t *c) {
  if (!c->hdr.valid) {
    return NULL;
  }
  if (!c->param_overrides_fetched) {
    c->param_overrides_fetched = true;
    rcl_params_t *params = NULL;
    if (rcl_arguments_get_param_overrides(&c->context.global_arguments,
                                          &params) != RCL_RET_OK) {
      rcl_reset_error();
      params = NULL;
    }
    c->param_overrides = params;
  }
  return (const rcl_params_t *)c->param_overrides;
}

// Rcllean.FFI.paramOverrideNodeCount : Context -> IO UInt32
LEAN_EXPORT lean_object *rcllean_param_override_node_count(b_lean_obj_arg ctx) {
  const rcl_params_t *p = rcllean_overrides(rcllean_to_context(ctx));
  return lean_io_result_mk_ok(
      lean_box_uint32(p == NULL ? 0 : (uint32_t)p->num_nodes));
}

// The node name an override block applies to; may be a wildcard pattern,
// which the Lean side resolves against the node's own name.
LEAN_EXPORT lean_object *rcllean_param_override_node_name(b_lean_obj_arg ctx,
                                                          uint32_t i) {
  const rcl_params_t *p = rcllean_overrides(rcllean_to_context(ctx));
  if (p == NULL || i >= p->num_nodes) {
    return lean_io_result_mk_error(
        rcllean_mk_msg_error("paramOverrideNodeName", "index out of range"));
  }
  return lean_io_result_mk_ok(rcllean_mk_string(p->node_names[i]));
}

LEAN_EXPORT lean_object *rcllean_param_override_count(b_lean_obj_arg ctx,
                                                      uint32_t i) {
  const rcl_params_t *p = rcllean_overrides(rcllean_to_context(ctx));
  if (p == NULL || i >= p->num_nodes) {
    return lean_io_result_mk_ok(lean_box_uint32(0));
  }
  return lean_io_result_mk_ok(
      lean_box_uint32((uint32_t)p->params[i].num_params));
}

LEAN_EXPORT lean_object *rcllean_param_override_name(b_lean_obj_arg ctx,
                                                     uint32_t i, uint32_t j) {
  const rcl_params_t *p = rcllean_overrides(rcllean_to_context(ctx));
  if (p == NULL || i >= p->num_nodes || j >= p->params[i].num_params) {
    return lean_io_result_mk_error(
        rcllean_mk_msg_error("paramOverrideName", "index out of range"));
  }
  return lean_io_result_mk_ok(
      rcllean_mk_string(p->params[i].parameter_names[j]));
}

// Rcllean.FFI.paramOverrideValue :
// Context -> UInt32 -> UInt32 -> IO RclInterfaces.Msg.ParameterValue
//
// An rcl variant has exactly one member set; `type` says which, using the
// codes of rcl_interfaces/msg/ParameterType.

// Exported by the Lean module of rcl_interfaces/msg/ParameterValue.
lean_object *rcl_interfaces__msg__ParameterValue__mk(
    uint8_t, uint8_t, uint64_t, double, lean_object *, lean_object *,
    lean_object *, lean_object *, lean_object *, lean_object *);

// The union's unset members, so every call passes all ten arguments.
typedef struct {
  uint8_t type;
  uint8_t bool_value;
  int64_t integer_value;
  double double_value;
  lean_object *string_value;
  lean_object *byte_array_value;
  lean_object *bool_array_value;
  lean_object *integer_array_value;
  lean_object *double_array_value;
  lean_object *string_array_value;
} rcllean_param_value_t;

static void rcllean_param_value_init(rcllean_param_value_t *v, uint8_t type) {
  v->type = type;
  v->bool_value = 0;
  v->integer_value = 0;
  v->double_value = 0.0;
  v->string_value = lean_mk_string("");
  v->byte_array_value = rcllean_mk_raw_bytes(NULL, 0);
  v->bool_array_value = lean_mk_empty_array();
  v->integer_array_value = lean_mk_empty_array();
  v->double_array_value = lean_mk_empty_array();
  v->string_array_value = lean_mk_empty_array();
}

static lean_object *rcllean_param_value_mk(rcllean_param_value_t *v) {
  return rcl_interfaces__msg__ParameterValue__mk(
      v->type, v->bool_value, (uint64_t)v->integer_value, v->double_value,
      v->string_value, v->byte_array_value, v->bool_array_value,
      v->integer_array_value, v->double_array_value, v->string_array_value);
}

LEAN_EXPORT lean_object *rcllean_param_override_value(b_lean_obj_arg ctx,
                                                      uint32_t i, uint32_t j) {
  const rcl_params_t *p = rcllean_overrides(rcllean_to_context(ctx));
  if (p == NULL || i >= p->num_nodes || j >= p->params[i].num_params) {
    return lean_io_result_mk_error(
        rcllean_mk_msg_error("paramOverrideValue", "index out of range"));
  }
  const rcl_variant_t *v = &p->params[i].parameter_values[j];
  rcllean_param_value_t out;

  if (v->bool_value != NULL) {
    rcllean_param_value_init(&out, 1);
    out.bool_value = *v->bool_value ? 1 : 0;
  } else if (v->integer_value != NULL) {
    rcllean_param_value_init(&out, 2);
    out.integer_value = *v->integer_value;
  } else if (v->double_value != NULL) {
    rcllean_param_value_init(&out, 3);
    out.double_value = *v->double_value;
  } else if (v->string_value != NULL) {
    rcllean_param_value_init(&out, 4);
    lean_dec(out.string_value);
    out.string_value = rcllean_mk_string(v->string_value);
  } else if (v->byte_array_value != NULL) {
    rcllean_param_value_init(&out, 5);
    lean_dec(out.byte_array_value);
    out.byte_array_value = rcllean_mk_raw_bytes(v->byte_array_value->values,
                                                v->byte_array_value->size);
  } else if (v->bool_array_value != NULL) {
    size_t n = v->bool_array_value->size;
    rcllean_param_value_init(&out, 6);
    lean_dec(out.bool_array_value);
    out.bool_array_value = lean_alloc_array(n, n);
    for (size_t k = 0; k < n; ++k) {
      lean_array_set_core(out.bool_array_value, k,
                          lean_box(v->bool_array_value->values[k] ? 1 : 0));
    }
  } else if (v->integer_array_value != NULL) {
    size_t n = v->integer_array_value->size;
    rcllean_param_value_init(&out, 7);
    lean_dec(out.integer_array_value);
    out.integer_array_value = lean_alloc_array(n, n);
    for (size_t k = 0; k < n; ++k) {
      lean_array_set_core(
          out.integer_array_value, k,
          lean_box_uint64((uint64_t)v->integer_array_value->values[k]));
    }
  } else if (v->double_array_value != NULL) {
    size_t n = v->double_array_value->size;
    rcllean_param_value_init(&out, 8);
    lean_dec(out.double_array_value);
    out.double_array_value = lean_alloc_array(n, n);
    for (size_t k = 0; k < n; ++k) {
      lean_array_set_core(out.double_array_value, k,
                          lean_box_float(v->double_array_value->values[k]));
    }
  } else if (v->string_array_value != NULL) {
    size_t n = v->string_array_value->size;
    rcllean_param_value_init(&out, 9);
    lean_dec(out.string_array_value);
    out.string_array_value = lean_alloc_array(n, n);
    for (size_t k = 0; k < n; ++k) {
      lean_array_set_core(out.string_array_value, k,
                          rcllean_mk_string(v->string_array_value->data[k]));
    }
  } else {
    return lean_io_result_mk_error(rcllean_mk_msg_error(
        "paramOverrideValue", "override has no value set"));
  }

  return rcllean_param_value_mk(&out);
}
