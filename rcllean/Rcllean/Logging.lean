/-!
# Logging

Records go through `rcutils`, so they reach the console, any configured log
file and `/rosout` with the same formatting and level filtering as `rclpy` or
`rclcpp` records; `--ros-args --log-level ...` works as usual.

The `logInfo` family capture the call site's enclosing declaration, which
`rcutils` records and log consumers display.
-/

namespace Rcllean.FFI

-- C bindings

@[extern "rcllean_logging_initialize"]
opaque loggingInitialize : IO Unit

/-- `rcutils_log` with an explicit call site.  The message is passed as a
literal, so `%` in user text is never interpreted as a format directive. -/
@[extern "rcllean_log_at"]
opaque logAt (severity : UInt32) (loggerName : @& String) (message : @& String)
    (fileName : @& String) (functionName : @& String) (line : UInt32) : IO Unit

@[extern "rcllean_set_logger_level"]
opaque setLoggerLevel (loggerName : @& String) (severity : UInt32) : IO Unit

@[extern "rcllean_get_logger_level"]
opaque getLoggerLevel (loggerName : @& String) : IO UInt32

end Rcllean.FFI

namespace Rcllean

/-- Log levels, matching `RCUTILS_LOG_SEVERITY_*`. -/
inductive LogSeverity where
  | unset | debug | info | warn | error | fatal
deriving DecidableEq, Repr, Inhabited, BEq

namespace LogSeverity

def toUInt32 : LogSeverity → UInt32
  | .unset => 0
  | .debug => 10
  | .info => 20
  | .warn => 30
  | .error => 40
  | .fatal => 50

def ofUInt32? : UInt32 → Option LogSeverity
  | 0 => some .unset
  | 10 => some .debug
  | 20 => some .info
  | 30 => some .warn
  | 40 => some .error
  | 50 => some .fatal
  | _ => none

@[simp] theorem ofUInt32?_toUInt32 (s : LogSeverity) :
    ofUInt32? s.toUInt32 = some s := by
  cases s <;> rfl

def toString : LogSeverity → String
  | .unset => "UNSET"
  | .debug => "DEBUG"
  | .info => "INFO"
  | .warn => "WARN"
  | .error => "ERROR"
  | .fatal => "FATAL"

instance : ToString LogSeverity := ⟨toString⟩

end LogSeverity

/-- A named logger.  Nodes have one whose name is their fully qualified name
with `/` replaced by `.`, so log levels can be set per node. -/
structure Logger where
  name : String
deriving Repr, Inhabited, BEq

namespace Logger

/-- The logger every ROS process has by default. -/
def default : Logger := ⟨"rcllean"⟩

/-- Emit a record with an explicit call site; the `logInfo` macros fill it
in. -/
def logAt (logger : Logger) (severity : LogSeverity) (message : String)
    (file : String) (function : String) (line : UInt32) : IO Unit :=
  FFI.logAt severity.toUInt32 logger.name message file function line

/-- Set the minimum severity this logger will emit. -/
def setLevel (logger : Logger) (severity : LogSeverity) : IO Unit :=
  FFI.setLoggerLevel logger.name severity.toUInt32

/-- The severity this logger will emit, taking inherited levels into account. -/
def getLevel (logger : Logger) : IO LogSeverity := do
  return (LogSeverity.ofUInt32? (← FFI.getLoggerLevel logger.name)).getD .unset

end Logger

/-- Anything with a logger: a `Logger` itself, or a `Node`. -/
class HasLogger (α : Type) where
  logger : α → Logger

instance : HasLogger Logger := ⟨id⟩

/-!
### Call-site capture

The `Logger.info` family take the calling declaration's name as an auto-param.
`decl_name%` elaborates at the call site, so the name is the caller's.

File and line are not captured: that needs a term elaborator, hence `Lean`
imported into the library and seconds added to every downstream module compile.
Pass them to `Logger.logAt` if you need them.
-/

namespace Logger

/-- Log a debug record. -/
def debug (logger : Logger) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  logger.logAt .debug message "" function 0

/-- Log an informational record. -/
def info (logger : Logger) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  logger.logAt .info message "" function 0

/-- Log a warning. -/
def warn (logger : Logger) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  logger.logAt .warn message "" function 0

/-- Log an error. -/
def error (logger : Logger) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  logger.logAt .error message "" function 0

/-- Log a fatal record. -/
def fatal (logger : Logger) (message : String)
    (function : String := by exact toString decl_name%) : IO Unit :=
  logger.logAt .fatal message "" function 0

end Logger

end Rcllean
