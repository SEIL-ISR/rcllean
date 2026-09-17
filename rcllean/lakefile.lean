import Lake
open Lake DSL System

/-! # rcllean — a ROS 2 client library for Lean 4

The C shim in `src/rcllean/` is compiled by Lake and linked into every Lean
target of this package.  Include and link flags are derived from the ROS 2
install prefix, taken from `RCLLEAN_ROS_PREFIX` and defaulting to
`/opt/ros/jazzy`.  Source ROS 2 and elan before building.
-/

/-- Read an environment variable while elaborating the configuration.  Lake's
    package fields are pure, hence `implemented_by`. -/
private unsafe def envImpl (key : String) : String :=
  match unsafeBaseIO (IO.getEnv key) with
  | some v => v
  | none => ""

@[implemented_by envImpl]
opaque envVar (key : String) : String

/-- The Lean package directory an installed ament package exports through its
    environment hook. -/
def amentPackage (name : String) : String :=
  envVar s!"AMENT_LEAN_PKG_{name.toUpper}"

/-- The ROS 2 install prefix, e.g. `/opt/ros/jazzy`, from `RCLLEAN_ROS_PREFIX`
    or the usual system location. -/
def rosPrefix : String :=
  let p := envVar "RCLLEAN_ROS_PREFIX"
  if p.isEmpty then "/opt/ros/jazzy" else p

/-- Where Lake writes its output.  colcon-ros-lake points this at the
    package's build directory, so a `colcon build` leaves the source tree
    clean. -/
def amentBuildDir : String :=
  let d := envVar "AMENT_LEAN_BUILD_DIR"
  if d.isEmpty then ".lake/build" else d

/-- Libraries the shim itself references.  The interface packages come in
    through `AMENT_LEAN_LINK_ARGS` instead, archive by archive. -/
def rosLibs : Array String := #[
  "-lrcl", "-lrcl_lifecycle", "-lrcl_yaml_param_parser",
  "-lrcutils", "-lrmw", "-lrmw_implementation",
  "-lrosidl_runtime_c", "-lrosidl_typesupport_c",
  "-lrcl_logging_interface",
  "-ldl", "-lpthread"
]

/-- `-L` and `-rpath` for the ROS prefix, followed by the shim's libraries. -/
def rosLinkArgs : Array String :=
  #[s!"-L{rosPrefix}/lib", s!"-Wl,-rpath,{rosPrefix}/lib",
    -- ROS shared libraries reference symbols (dlopen, stat, ...) that Lean's
    -- bundled glibc stubs do not export.  They resolve against the real libc
    -- at run time, so relax lld's static check.
    "-Wl,--allow-shlib-undefined"] ++ rosLibs

/-- ROS 2 installs headers as `<prefix>/include/<pkg>/<pkg>/...`, so every
    package directory under `include/` is an include root of its own. -/
def rosIncludeFlags : IO (Array String) := do
  let inc : FilePath := rosPrefix / "include"
  if !(← inc.pathExists) then
    return #[]
  let mut flags : Array String := #[]
  for entry in (← inc.readDir) do
    if (← entry.path.isDir) then
      flags := flags.push s!"-I{entry.path}"
  return flags.qsort (· < ·)

/-- The separator inside `AMENT_LEAN_LINK_ARGS`.  A tab, since those flags
    carry paths and a path may contain spaces. -/
def amentArgSep : String := "\t"

/-- This package's own archives, which an installed rcllean exports through
    its environment hook.  These sources must not link against the archives of
    an installed copy of themselves. -/
def ownArchives : Array String :=
  #["-lrcllean_c", "-lrcllean_Rcllean", "-lrcllean_TestSupport",
    "-lrcllean_UnitTests"]

/-- Linker flags from the environment hooks of the installed Lean packages:
    the runtime and the interface packages this one depends on.  Empty when no
    workspace is sourced, in which case the link fails on the generated
    symbols.

    Static archives resolve left to right, so the whole line goes inside a
    linker group. -/
def amentLinkArgs : Array String :=
  let args := ((envVar "AMENT_LEAN_LINK_ARGS").splitOn amentArgSep
    |>.filter (fun a => !a.isEmpty && !ownArchives.contains a)).toArray
  if args.isEmpty then #[]
  else #["-Wl,--start-group"] ++ args ++ #["-Wl,--end-group"]

/-- Link the shim by flag rather than through `moreLinkObjs`, which would
    archive `librcllean_c.a` inside every `lean_lib` archive and leave a
    nested member the linker cannot read.  A separate archive can also be
    installed and linked on its own by a downstream package. -/
def cLinkArgs : Array String :=
  #[s!"-L{amentBuildDir}/lib", "-lrcllean_c"]

require rosidl_runtime_lean from amentPackage "rosidl_runtime_lean"
require builtin_interfaces from amentPackage "builtin_interfaces"
require rcl_interfaces from amentPackage "rcl_interfaces"
require lifecycle_msgs from amentPackage "lifecycle_msgs"
require rosgraph_msgs from amentPackage "rosgraph_msgs"

package rcllean where
  version := v!"0.1.0"
  description := "ROS 2 client library for Lean 4"
  keywords := #["ros2", "robotics", "ffi"]
  buildDir := amentBuildDir
  extraDepTargets := #[`rcllean_c, `amentLinkArgsFile]
  -- The shim's own archive first, then the interface packages' archives,
  -- then the ROS shared libraries both resolve against.
  moreLinkArgs := cLinkArgs ++ amentLinkArgs ++ rosLinkArgs

/-- The flags a downstream package needs beyond this package's own archives:
    the ROS libraries the shim references.  colcon-ros-lake reads the file
    from the build directory and exports it through the environment hook. -/
target amentLinkArgsFile pkg : FilePath := do
  let file := pkg.buildDir / "ament_link_args"
  createParentDirs file
  IO.FS.writeFile file ("\n".intercalate rosLinkArgs.toList ++ "\n")
  return .pure file

/-- Compile every `src/rcllean/*.c` file and archive them into one static
    library. -/
target rcllean_c pkg : FilePath := do
  let cDir := pkg.dir / "src" / "rcllean"
  let incFlags ← rosIncludeFlags
  let leanInc ← getLeanIncludeDir
  let cflags := #[-- gnu11, not c11, so the POSIX declarations the shim needs
                  -- (sigaction, semaphores, pthreads) are visible.
                  "-fPIC", "-O2", "-std=gnu11", "-Wall", "-Wextra",
                  s!"-I{leanInc}", s!"-I{cDir}",
                  -- rosidl_runtime_lean is header-only and installs its
                  -- header beside the Lake stub package.
                  s!"-I{amentPackage "rosidl_runtime_lean"}/../include"]
                ++ incFlags
  -- Headers are inputs too: with only the `.c` files in each object's trace,
  -- editing `src/rcllean/destroyable.h` rebuilds nothing.
  let hdrs ← inputDir cDir (text := true)
    (fun p => p.extension == some "h")
  let mut srcs : Array FilePath := #[]
  for entry in (← cDir.readDir) do
    if entry.path.extension == some "c" then
      srcs := srcs.push entry.path
  srcs := srcs.qsort (fun a b => a.toString < b.toString)
  let mut objs : Array (Job FilePath) := #[]
  for src in srcs do
    let stem := src.fileStem.getD "obj"
    let oFile := pkg.buildDir / "src" / (stem ++ ".o")
    let srcJob ← inputTextFile src
    -- Same source, with the headers mixed into the job's trace.
    let depJob := Job.zipWith
      (fun (s : FilePath) (_ : Array FilePath) => s) srcJob hdrs
    objs := objs.push (← buildO oFile depJob #[] cflags "cc")
  buildStaticLib (pkg.staticLibDir / (nameToStaticLib "rcllean_c")) objs

@[default_target]
lean_lib Rcllean where
  srcDir := "."
  roots := #[`Rcllean]

/-- The harness the integration tests share.  Not installed. -/
lean_lib TestSupport where
  srcDir := "tests/Integration"
  roots := #[`Support]

/-- Round trips generated types through CDR.  Needs a sourced ROS 2, so it
    lives outside `lake test`. -/
lean_exe «test-marshal» where
  srcDir := "tests/Integration"
  root := `Marshal

/-- Lifecycle transitions, refusals and the terminal state. -/
lean_exe «test-lifecycle» where
  srcDir := "tests/Integration"
  root := `LifecycleTest

/-- Entity lifetimes, node teardown, and services under the multi-threaded
    executor. -/
lean_exe «test-executor» where
  srcDir := "tests/Integration"
  root := `ExecutorTest

/-- Callback group scheduling under the multi-threaded executor. -/
lean_exe «test-concurrency» where
  srcDir := "tests/Integration"
  root := `Concurrency

/-- Graph queries, name validation against rmw, and serialization. -/
lean_exe «test-graph» where
  srcDir := "tests/Integration"
  root := `GraphTest

/-- Parameter declaration, constraints, callbacks and simulated time. -/
lean_exe «test-params» where
  srcDir := "tests/Integration"
  root := `ParamsTest

/-- In-process service and client tests. -/
lean_exe «test-services» where
  srcDir := "tests/Integration"
  root := `Services

/-- In-process topic, timer and clock tests. -/
lean_exe «test-topics» where
  srcDir := "tests/Integration"
  root := `Topics

/-- The unit tests' own modules.  A `lean_exe` builds only its root and that
root's submodules, so the shared assertions (`Check`) are declared here for
`Main` to import. -/
lean_lib UnitTests where
  srcDir := "tests/Unit"
  roots := #[`Check]

@[test_driver]
lean_exe tests where
  srcDir := "tests/Unit"
  root := `Main
