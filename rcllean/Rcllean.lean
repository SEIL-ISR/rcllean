import RosidlRuntimeLean
import Rcllean.Destroyable
import Rcllean.Utilities
import Rcllean.Duration
import Rcllean.Time
import Rcllean.Context
import Rcllean.Logging
import Rcllean.Clock
import Rcllean.Node
import Rcllean.Names
import Rcllean.Graph
import Rcllean.QoS
import Rcllean.Serialization
import Rcllean.Publisher
import Rcllean.Subscription
import Rcllean.EventHandle
import Rcllean.GuardCondition
import Rcllean.Timer
import Rcllean.WaitSet
import Rcllean.Future
import Rcllean.Service
import Rcllean.Client
import Rcllean.CallbackGroup
import Rcllean.Executor
import Rcllean.Parameter
import Rcllean.ParameterStore
import Rcllean.ParameterService
import Rcllean.Lifecycle.State
import Rcllean.Lifecycle.Node
import Rcllean.TimeSource

/-!
# rcllean

A ROS 2 client library for Lean 4.  This root module re-exports the public
API: one module per entity, as `rclpy` lays out its package.

Message, service and action types come from interface packages built by
`rosidl_generator_lean`; their classes are re-exported here so `open Rcllean`
is enough to write `[RosMessage α]`.
-/

namespace Rcllean

export RosidlRuntimeLean (RosMessage RosService RosAction)

/-- The rmw (ROS middleware) implementation this process will use. -/
def rmwImplementation : IO String := FFI.rmwImplementationIdentifier

end Rcllean
