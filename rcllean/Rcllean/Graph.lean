import Rcllean.Node
import Rcllean.Clock
import Rcllean.Names

/-!
# The ROS graph

Which nodes exist, what topics and services they offer, and how many
publishers a topic has: the queries behind `ros2 node list`, `ros2 topic list`
and `ros2 service list`.
-/

namespace Rcllean.FFI

-- C bindings

/-- Names and their types come back as two parallel arrays, with each entry's
types joined by a unit separator, so nothing structured is built in C. -/
@[extern "rcllean_graph_topic_names_and_types"]
opaque graphTopicNamesAndTypes (node : @& Node) :
    IO (Array String × Array String)

@[extern "rcllean_graph_service_names_and_types"]
opaque graphServiceNamesAndTypes (node : @& Node) :
    IO (Array String × Array String)

@[extern "rcllean_graph_node_names"]
opaque graphNodeNames (node : @& Node) : IO (Array String)

@[extern "rcllean_graph_count_publishers"]
opaque graphCountPublishers (node : @& Node) (topic : @& String) : IO UInt64

@[extern "rcllean_graph_count_subscribers"]
opaque graphCountSubscribers (node : @& Node) (topic : @& String) : IO UInt64

end Rcllean.FFI

namespace Rcllean

/-- A name on the graph together with the interface types carried on it.  A
topic almost always has one type; more than one means two nodes disagree. -/
structure NameAndTypes where
  name : String
  types : Array String
deriving Repr, Inhabited, BEq

namespace Graph

/-- C returns names and types as parallel arrays with the types joined by a
unit separator, which cannot occur in a ROS type name. -/
private def zipNamesAndTypes (names types : Array String) :
    Array NameAndTypes :=
  names.zipWith (fun n t =>
    { name := n
      types := (t.splitOn "\x1f").filter (!·.isEmpty) |>.toArray }) types

/-- Every topic on the graph, with its types. -/
def topicNamesAndTypes (node : Node) : IO (Array NameAndTypes) := do
  let (names, types) ← FFI.graphTopicNamesAndTypes node.handle
  return zipNamesAndTypes names types

/-- Every service on the graph, with its types. -/
def serviceNamesAndTypes (node : Node) : IO (Array NameAndTypes) := do
  let (names, types) ← FFI.graphServiceNamesAndTypes node.handle
  return zipNamesAndTypes names types

/-- Every node on the graph, as fully qualified names. -/
def nodeNames (node : Node) : IO (Array String) :=
  FFI.graphNodeNames node.handle

/-- How many publishers a topic has. -/
def countPublishers (node : Node) (topic : String) : IO Nat :=
  return (← FFI.graphCountPublishers node.handle topic).toNat

/-- How many subscriptions a topic has. -/
def countSubscribers (node : Node) (topic : String) : IO Nat :=
  return (← FFI.graphCountSubscribers node.handle topic).toNat

/-- Whether a node with this fully qualified name is on the graph. -/
def hasNode (node : Node) (name : String) : IO Bool :=
  return (← nodeNames node).contains name

/-- Wait for a node to appear, polling until the timeout expires.  Discovery
is asynchronous, so a peer that will exist shortly does not exist yet. -/
partial def waitForNode (node : Node) (name : String)
    (timeout : Duration := Duration.ofSeconds 10) : IO Bool := do
  let clock ← Clock.steady
  let start ← clock.now
  while !(← hasNode node name) do
    if ((← clock.now) - start).nanos > timeout.nanos then
      return false
    sleepFor (Duration.ofMillis 100)
  return true

/-- Wait for a topic to have at least one publisher. -/
partial def waitForPublisher (node : Node) (topic : String)
    (timeout : Duration := Duration.ofSeconds 10) : IO Bool := do
  let clock ← Clock.steady
  let start ← clock.now
  while (← countPublishers node topic) == 0 do
    if ((← clock.now) - start).nanos > timeout.nanos then
      return false
    sleepFor (Duration.ofMillis 100)
  return true

end Graph

end Rcllean
