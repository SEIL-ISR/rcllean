/-!
# Contexts

A `Context` owns the middleware connection and the parsed ROS command-line
arguments; every node is created against one.  Shutting it down invalidates
everything created from it, which is how Ctrl-C wakes an executor blocked in
`rcl_wait`.  `init` installs signal handlers unless told not to; they run the
shutdown on a dedicated thread so the handler stays async-signal-safe.
-/

namespace Rcllean.FFI

-- C bindings

private opaque ContextPointed : NonemptyType
/-- An initialized `rcl_context_t`: the process's connection to a ROS graph. -/
def Context : Type := ContextPointed.type
instance : Nonempty Context := ContextPointed.property

/-- `rcl_init`.  `args` is a full command line including `argv[0]`; the ROS
arguments in it (`--ros-args ... --`) configure remapping, parameters and
logging. -/
@[extern "rcllean_context_init"]
opaque contextInit (args : @& Array String) (hasDomainId : Bool)
    (domainId : UInt64) (installSignalHandlers : Bool) : IO Context

/-- `rcl_shutdown`.  Idempotent: shutting down an already-shut-down context
succeeds. -/
@[extern "rcllean_context_shutdown"]
opaque contextShutdown (ctx : @& Context) : IO Unit

/-- Whether the context is initialized and has not been shut down. -/
@[extern "rcllean_context_ok"]
opaque contextOk (ctx : @& Context) : IO Bool

/-- The DDS domain id the context joined. -/
@[extern "rcllean_context_domain_id"]
opaque contextDomainId (ctx : @& Context) : IO UInt64

end Rcllean.FFI

namespace Rcllean

/-- An initialized ROS 2 context. -/
structure Context where
  /-- The underlying `rcl_context_t`.  Internal. -/
  handle : FFI.Context

namespace Context

/-- Initialize a context.

`args` is a full command line including `argv[0]`; the ROS section
(`--ros-args ... --`) configures remapping, parameter overrides and logging.
Passing `none` for `domainId` uses `ROS_DOMAIN_ID` from the environment. -/
def init (args : Array String := #[]) (domainId : Option UInt64 := none)
    (installSignalHandlers : Bool := true) : IO Context := do
  let handle ← FFI.contextInit args domainId.isSome (domainId.getD 0)
    installSignalHandlers
  return ⟨handle⟩

/-- Shut the context down, invalidating every node and entity created from it.
Idempotent. -/
def shutdown (ctx : Context) : IO Unit :=
  FFI.contextShutdown ctx.handle

/-- Whether the context is initialized and has not been shut down. -/
def ok (ctx : Context) : IO Bool :=
  FFI.contextOk ctx.handle

/-- The DDS domain the context joined. -/
def domainId (ctx : Context) : IO UInt64 :=
  FFI.contextDomainId ctx.handle

/-- Run `act` with a context, shutting it down afterwards even if it throws. -/
def with' (args : Array String := #[]) (domainId : Option UInt64 := none)
    (act : Context → IO α) : IO α := do
  let ctx ← init args domainId
  try
    act ctx
  finally
    ctx.shutdown

end Context

/-- Initialize a context from the arguments `main` was given; the usual entry
point.  `argv[0]` is filled in from the executable path, which rcl expects. -/
def init (args : List String := []) (domainId : Option UInt64 := none) :
    IO Context := do
  let argv0 ← (do return (← IO.appPath).toString) <|> pure "rcllean"
  Context.init (#[argv0] ++ args.toArray) domainId

end Rcllean
