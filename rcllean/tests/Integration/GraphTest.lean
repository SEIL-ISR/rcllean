import Rcllean
import Support
import RclInterfaces
import RosgraphMsgs

/-!
Graph queries, name validation and serialization.  The name tests check the
predicates in `Rcllean.Names` against `rcl_validate_topic_name`,
`rmw_validate_full_topic_name` and friends, and `TopicName.expand` against
`rcl_expand_topic_name`.
-/

open Rcllean Rcllean.Test

/-- Names as a user writes them, for `isValidTopicName` against
`rcl_validate_topic_name`.  Covers every code `rcl_validate_topic_name.h` lists
plus valid relative, private, absolute and substituted names.

The flag marks a name the Lean rules reject and rcl's validator accepts.  There
are three such classes, all of them caught later by rcl rather than never: a
doubled slash (rcl leaves it to rmw after expansion), a substitution other than
`{node}` (rcl leaves it to its expander, which fails with
`RCL_RET_UNKNOWN_SUBSTITUTION`), and a two-character name starting with `~`,
which rcl accepts through an off-by-one in its token loop and then expands with
the tilde replaced and the character glued on. -/
def writtenCorpus : List (String × Bool) :=
  [-- relative, private, absolute, substituted: valid for both
   ("chatter", false), ("robot/arm/joint_states", false), ("_hidden", false),
   ("a/_b/c", false), ("A/B", false), ("x1/y2", false), ("under_score", false),
   ("a0", false), ("_", false), ("__/x", false), ("_/_", false),
   ("/chatter", false), ("/robot/arm/joint_states", false), ("/_hidden", false),
   ("~", false), ("~/status", false), ("~/a/b", false),
   ("{node}", false), ("{node}/state", false), ("/{node}/state", false),
   ("x{node}y", false), ("{node}{node}", false), ("{node}1", false),
   ("~/{node}_state", false),
   -- empty string
   ("", false),
   -- ends with a forward slash
   ("chatter/", false), ("/", false), ("/chatter/", false), ("~/", false),
   ("//", false), ("///", false), ("/a//", false), ("{ns}/", false),
   -- characters that are not allowed
   ("has-dash", false), ("/has-dash", false), ("has space", false),
   ("a.b", false), ("a:b", false), ("/*", false), ("a+b", false),
   -- a name token starting with a number
   ("1abc", false), ("/1abc", false), ("abc/1d", false), ("0", false),
   ("1{node}", false),
   -- an unmatched curly brace
   ("{node", false), ("node}", false), ("a{", false), ("}a", false),
   ("{", false), ("}", false), ("{ns", false),
   -- a misplaced tilde
   ("/~", false), ("a~b", false), ("foo~", false), ("/~/a", false),
   ("a/~/b", false), ("~/~", false),
   -- a tilde not followed by a forward slash
   ("~foo", false), ("~{node}", false),
   -- a substitution holding characters that are not allowed
   ("{no de}", false), ("{a/b}", false), ("{a-b}", false),
   -- a substitution starting with a number
   ("{1node}", false), ("{2}", false),
   -- stricter than rcl: a doubled slash
   ("a//b", true), ("/a//b", true), ("//a", true),
   -- stricter than rcl: a substitution that is not `{node}`
   ("{ns}", true), ("{ns}/x", true), ("{namespace}/y", true),
   ("{unknown}", true), ("{}", true), ("a{}b", true), ("{NODE}", true),
   ("{node0}", true),
   -- stricter than rcl: the two-character tilde name rcl lets through
   ("~a", true), ("~x", true)]

/-- Expanded names, for `isValidFullTopicName` against
`rmw_validate_full_topic_name`. -/
def fullTopicCorpus : List String :=
  ["/chatter", "/robot/arm/joint_states", "/_hidden", "/a/_b/c", "/",
   "/A/B", "/x1/y2", "/under_score",
   "chatter", "/chatter/", "/a//b", "/1abc", "/has space", "/has-dash",
   "", "//", "/a/1b", "/a.b", "/a:b", "/~foo", "/{node}", "/a/", "/*"]

def nodeCorpus : List String :=
  ["my_node", "node1", "_private", "A",
   "/foo", "my node", "my-node", "1node", "", "a/b", "a.b"]

def namespaceCorpus : List String :=
  ["/", "/robot", "/robot/arm", "/_hidden",
   "robot", "/robot/", "//", "/1a", "/a b", ""]

/-- Node names and namespaces to expand against.  The root namespace is here
because it is the one that turns a careless `<ns>/<name>` into `//name`. -/
def expandCases : List (String × String) :=
  [("talker", "/"), ("talker", "/robot"), ("nd", "/a/b"), ("_n", "/_h/x")]

def testNamesAgreeWithMiddleware : IO Unit := do
  IO.println "Lean's name rules agree with rcl and the middleware"
  let mut disagreements := 0

  for (name, stricter) in writtenCorpus do
    let leanSays := isValidTopicName name
    let rclSays := (← Names.rclTopicNameError name).isNone
    if stricter && !rclSays then
      fail "topic name" s!"'{name}': marked stricter, but rcl rejects it too"
      disagreements := disagreements + 1
    else if leanSays != (rclSays && !stricter) then
      fail "topic name" s!"'{name}': Lean says {leanSays}, rcl says {rclSays}"
      disagreements := disagreements + 1
  check s!"{writtenCorpus.length} names as written agree with rcl"
    (disagreements == 0)

  disagreements := 0
  for name in fullTopicCorpus do
    let leanSays := isValidFullTopicName name
    let rmwSays := (← Names.rmwFullTopicNameError name).isNone
    if leanSays != rmwSays then
      fail "full topic name"
        s!"'{name}': Lean says {leanSays}, rmw says {rmwSays}"
      disagreements := disagreements + 1
  check s!"{fullTopicCorpus.length} expanded names agree with rmw"
    (disagreements == 0)

  disagreements := 0
  for name in nodeCorpus do
    let leanSays := isValidNodeName name
    let rmwSays := (← Names.rmwNodeNameError name).isNone
    if leanSays != rmwSays then
      fail "node name" s!"'{name}': Lean says {leanSays}, rmw says {rmwSays}"
      disagreements := disagreements + 1
  check s!"{nodeCorpus.length} node names agree" (disagreements == 0)

  disagreements := 0
  for name in namespaceCorpus do
    let leanSays := isValidNamespace name
    let rmwSays := (← Names.rmwNamespaceError name).isNone
    if leanSays != rmwSays then
      fail "namespace" s!"'{name}': Lean says {leanSays}, rmw says {rmwSays}"
      disagreements := disagreements + 1
  check s!"{namespaceCorpus.length} namespaces agree" (disagreements == 0)

def testExpandMatchesRcl : IO Unit := do
  IO.println "TopicName.expand agrees with rcl_expand_topic_name"
  let mut mismatches := 0
  let mut expansions := 0
  for (name, _) in writtenCorpus do
    let some topic := TopicName.ofString? name | continue
    for (nodeName, nsName) in expandCases do
      let some node := NodeName.ofString? nodeName
        | fail "expand" s!"'{nodeName}' is not a node name"; continue
      let some ns := Namespace.ofString? nsName
        | fail "expand" s!"'{nsName}' is not a namespace"; continue
      let ours := topic.expand node ns
      let theirs ← Names.rclExpand name nodeName nsName
      expansions := expansions + 1
      if ours.toString != theirs then
        fail "expand" s!"'{name}' in {nsName} as {nodeName}: \
          Lean gives '{ours}', rcl gives '{theirs}'"
        mismatches := mismatches + 1
      -- The type says the result is a valid expanded name; ask rmw too.
      if (← Names.rmwFullTopicNameError ours.toString).isSome then
        fail "expand" s!"rmw rejects the expansion '{ours}' of '{name}'"
        mismatches := mismatches + 1
  check s!"{expansions} expansions match rcl" (mismatches == 0)

def testGraphQueries : IO Unit := do
  IO.println "graph queries"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_graph_test"
  let pub ← node.createPublisher RosgraphMsgs.Msg.Clock topic!"graph_topic"
  let svc ← node.createService RclInterfaces.Srv.GetParameters
    topic!"graph_service"
    fun _ => return { values := #[] }

  -- Discovery is asynchronous; a node does not see even its own entities
  -- instantly.
  let clock ← Clock.steady
  let start ← clock.now
  let mut sawTopic := false
  let mut sawService := false
  let mut sawSelf := false
  while ((← clock.now) - start).toFloatSeconds < 10.0 &&
        !(sawTopic && sawService && sawSelf) do
    sawTopic := (← Graph.topicNamesAndTypes node).any (·.name == "/graph_topic")
    sawService := (← Graph.serviceNamesAndTypes node).any (·.name == "/graph_service")
    sawSelf := (← Graph.nodeNames node).contains "/rcllean_graph_test"
    if !(sawTopic && sawService && sawSelf) then
      sleepFor (Duration.ofMillis 200)

  check "the node sees itself on the graph" sawSelf
  check "the node sees its own topic" sawTopic
  check "the node sees its own service" sawService

  match (← Graph.topicNamesAndTypes node).find? (·.name == "/graph_topic") with
  | none => fail "the topic reports its type" "topic not found"
  | some t =>
    check "the topic reports its type"
      (t.types.contains "rosgraph_msgs/msg/Clock")
      s!"got {t.types.toList}"

  check "the publisher is counted"
    ((← Graph.countPublishers node "/graph_topic") ≥ 1)
    s!"counted {← Graph.countPublishers node "/graph_topic"}"

  svc.destroy
  pub.destroy
  node.destroy
  ctx.shutdown

def testSerialization : IO Unit := do
  IO.println "serialization"

  -- A round trip through the wire format must give back what went in.
  let msg : RclInterfaces.Msg.Log := { msg := "hello, wire", level := 20 }
  let bytes ← serialize msg
  check "serializing produces bytes" (bytes.size > 0) "empty buffer"
  let back ← deserialize RclInterfaces.Msg.Log bytes
  check "a string round-trips through CDR"
    (back.msg == msg.msg && back.level == msg.level) s!"got '{back.msg}'"

  -- A message with nested fields and an array of messages.
  let event : RclInterfaces.Msg.ParameterEvent :=
    { stamp := { sec := 1, nanosec := 2 }, node := "/n"
      new_parameters := #[{ name := "a", value := { type := 2,
                                                    integer_value := 5 } }] }
  let eventBytes ← serialize event
  let eventBack ← deserialize RclInterfaces.Msg.ParameterEvent eventBytes
  check "a nested message round-trips"
    (eventBack.stamp.sec == 1 && eventBack.node == "/n")
    "stamp or node differs"
  check "an array of nested messages round-trips"
    (eventBack.new_parameters.map (·.name) == #["a"] &&
     eventBack.new_parameters[0]!.value.integer_value == 5)
    "parameters differ"

  -- Serializing the same value twice must give the same bytes.  CDR leaves
  -- alignment padding untouched, so this holds only for a type whose fields
  -- need none: two string sequences, counts and lengths all 4-aligned.
  let packed : RclInterfaces.Msg.ListParametersResult := { names := #["abc"] }
  let once ← serialize packed
  let again ← serialize packed
  check "serialization is deterministic" (again.toList == once.toList)
    "two serializations of one value differ"

def main : IO UInt32 := do
  IO.println "graph, names and serialization tests"
  testNamesAgreeWithMiddleware
  testExpandMatchesRcl
  testGraphQueries
  testSerialization
  finish "graph"
