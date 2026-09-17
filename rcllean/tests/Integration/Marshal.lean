import Rcllean
import Support
import BuiltinInterfaces
import LifecycleMsgs
import RclInterfaces
import RosgraphMsgs

/-!
Round trips through CDR.  These need a sourced ROS 2 install: `serialize` and
`deserialize` go through rmw and the interface packages' generated converters.

Values are compared by their `Repr` output; generated structures derive `Repr`
and nothing else, and `Float` and `ByteArray` do not compare usefully with
`BEq` anyway.
-/

open Rcllean Rcllean.Test

/-- Serialize, deserialize, and require the same value back. -/
def roundTrip {α : Type} [RosMessage α] [Repr α] (name : String) (msg : α) :
    IO Unit := do
  try
    let bytes ← serialize msg
    if bytes.isEmpty then
      fail name "serializing produced no bytes"
      return
    let back ← deserialize α bytes
    let before := (repr msg).pretty
    let after := (repr back).pretty
    if before == after then
      pass name
    else
      fail name s!"differs\n         sent: {before}\n         got:  {after}"
  catch e =>
    fail name (toString e)

def testParameterValue : IO Unit := do
  IO.println "rcl_interfaces/msg/ParameterValue, one field kind at a time"
  roundTrip "notSet" ({ type := 0 } : RclInterfaces.Msg.ParameterValue)
  roundTrip "bool" ({ type := 1, bool_value := true } :
    RclInterfaces.Msg.ParameterValue)
  roundTrip "integer" ({ type := 2, integer_value := -9223372036854775808 } :
    RclInterfaces.Msg.ParameterValue)
  roundTrip "double" ({ type := 3, double_value := -2.5e-8 } :
    RclInterfaces.Msg.ParameterValue)
  roundTrip "string" ({ type := 4, string_value := "hello ünïcøde" } :
    RclInterfaces.Msg.ParameterValue)
  roundTrip "byte array"
    ({ type := 5,
       byte_array_value :=
         ByteArray.mk (Array.range 512 |>.map fun i => UInt8.ofNat (i % 256)) } :
     RclInterfaces.Msg.ParameterValue)
  roundTrip "bool array"
    ({ type := 6, bool_array_value := #[true, false, true, true] } :
     RclInterfaces.Msg.ParameterValue)
  roundTrip "integer array"
    ({ type := 7, integer_array_value := #[0, -1, 1, 9007199254740993] } :
     RclInterfaces.Msg.ParameterValue)
  roundTrip "double array"
    ({ type := 8, double_array_value := #[0.0, -0.5, 1.25, 1e100] } :
     RclInterfaces.Msg.ParameterValue)
  roundTrip "string array"
    ({ type := 9, string_array_value := #["", "a", "日本語", "x y z"] } :
     RclInterfaces.Msg.ParameterValue)
  -- Every field set at once, so a converter that reads the wrong offset shows
  -- up whatever the type tag says.
  roundTrip "every field at once"
    ({ type := 9, bool_value := true, integer_value := 42,
       double_value := 0.125, string_value := "all",
       byte_array_value := ByteArray.mk #[1, 2, 3],
       bool_array_value := #[false, true],
       integer_array_value := #[7, 8],
       double_array_value := #[1.5, 2.5],
       string_array_value := #["p", "q"] } :
     RclInterfaces.Msg.ParameterValue)

def testNested : IO Unit := do
  IO.println "nested messages"
  roundTrip "rcl_interfaces/msg/Parameter"
    ({ name := "rate",
       value := { type := 3, double_value := 10.5 } } :
     RclInterfaces.Msg.Parameter)
  roundTrip "rcl_interfaces/msg/ListParametersResult"
    ({ names := #["a", "a.b", "a.b.c"], prefixes := #["a", "a.b"] } :
     RclInterfaces.Msg.ListParametersResult)
  roundTrip "rcl_interfaces/msg/ParameterEvent"
    ({ stamp := { sec := -1, nanosec := 999999999 },
       node := "/talker",
       new_parameters := #[{ name := "n", value := { type := 1,
                                                     bool_value := true } }],
       changed_parameters := #[],
       deleted_parameters := #[{ name := "d", value := { type := 0 } }] } :
     RclInterfaces.Msg.ParameterEvent)
  roundTrip "rcl_interfaces/msg/Log"
    ({ stamp := { sec := 12, nanosec := 34 }, level := 20, name := "logger",
       msg := "line", file := "f.lean", function := "main", line := 7 } :
     RclInterfaces.Msg.Log)
  -- Two levels of nesting: the event holds a transition and two states.
  roundTrip "lifecycle_msgs/msg/TransitionEvent"
    ({ timestamp := 1234567890123456789,
       transition := { id := 3, label := "activate" },
       start_state := { id := 2, label := "inactive" },
       goal_state := { id := 3, label := "active" } } :
     LifecycleMsgs.Msg.TransitionEvent)
  roundTrip "rosgraph_msgs/msg/Clock"
    ({ clock := { sec := 1700000000, nanosec := 250000000 } } :
     RosgraphMsgs.Msg.Clock)

def testServicePair : IO Unit := do
  IO.println "a service's request and response"
  roundTrip "rcl_interfaces/srv/GetParameters_Request"
    ({ names := #["use_sim_time", "rate"] } :
     RclInterfaces.Srv.GetParameters_Request)
  roundTrip "rcl_interfaces/srv/GetParameters_Response"
    ({ values := #[{ type := 1, bool_value := false },
                   { type := 3, double_value := 10.5 }] } :
     RclInterfaces.Srv.GetParameters_Response)
  roundTrip "lifecycle_msgs/srv/GetState_Request"
    ({} : LifecycleMsgs.Srv.GetState_Request)
  roundTrip "lifecycle_msgs/srv/GetState_Response"
    ({ current_state := { id := 1, label := "unconfigured" } } :
     LifecycleMsgs.Srv.GetState_Response)

/-- `rcl_interfaces/msg/ParameterDescriptor` bounds `integer_range` at one
element and it is the last field, so the CDR tail of a one-element descriptor
is a `uint32` count, four bytes of padding to the 8-byte alignment of
`IntegerRange`, and one 24-byte element.  Rewriting the count to two is a wire
value the Lean type cannot hold; deserializing it must raise. -/
def testBoundViolation : IO Unit := do
  IO.println "a bound violated on the wire"
  let d : RclInterfaces.Msg.ParameterDescriptor :=
    { name := "count", type := 2,
      integer_range := ⟨#[{ from_value := 0, to_value := 10, step := 1 }],
                        by simp⟩ }
  let bytes ← serialize d
  let n := bytes.size
  if n < 32 || bytes.get! (n - 32) != 1 then
    fail "bound violation" s!"unexpected CDR tail in {n} bytes"
    return
  let element := bytes.extract (n - 24) n
  let forged :=
    (bytes.extract 0 (n - 32)).push 2 |>.push 0 |>.push 0 |>.push 0
      |> (· ++ bytes.extract (n - 28) n) |> (· ++ element)
  let raised ← try
      let _ ← deserialize RclInterfaces.Msg.ParameterDescriptor forged
      pure false
    catch _ => pure true
  check "two elements in a [<=1] field are refused" raised
    "deserializing accepted a sequence longer than the bound"

def main : IO UInt32 := do
  IO.println "CDR round trips"
  testParameterValue
  testNested
  testServicePair
  testBoundViolation
  finish "round trip"
