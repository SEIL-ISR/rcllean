/-!
# Utilities

The bindings in `src/rcllean/utils.c`: which middleware is linked in, and the
command line with the ROS section removed.
-/

namespace Rcllean.FFI

-- C bindings

/-- The rmw implementation the process is linked against, e.g.
`"rmw_fastrtps_cpp"`.  Fails if no middleware could be loaded. -/
@[extern "rcllean_rmw_implementation_identifier"]
opaque rmwImplementationIdentifier : IO String

/-- The command line with the `--ros-args ... --` section removed. -/
@[extern "rcllean_remove_ros_arguments"]
opaque removeRosArguments (args : @& Array String) : IO (Array String)

end Rcllean.FFI

namespace Rcllean

/-- The arguments `main` was given, with the ROS section removed.

rcl skips the first argument as the program name, so a placeholder is added
and removed around the call. -/
def removeRosArguments (args : List String) : IO (Array String) := do
  let out ← FFI.removeRosArguments (#["rcllean"] ++ args.toArray)
  return out.extract 1 out.size

end Rcllean
