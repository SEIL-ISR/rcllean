/-!
# ROS names

Two rule sets.  `isValidTopicName` holds the pre-expansion rules of
`rcl_validate_topic_name`, which a user's name follows: relative names,
`~/private` and `{node}` substitutions are all allowed.  `isValidFullTopicName`
holds the post-expansion rules of `rmw_validate_full_topic_name`, which demand
a leading slash and nothing else.  `TopicName.expand` goes from the first to
the second with a proof that it lands inside it.

The rules are decidable predicates over `List Char`, so `topic!"chatter"` is a
compile-time check.  A corpus test checks them against rcl and rmw.
-/

namespace Rcllean.FFI

-- C bindings

/-- rmw's verdict on an expanded name: empty when valid, an explanation
otherwise.  Used to check the Lean rules against the middleware's. -/
@[extern "rcllean_validate_full_topic_name"]
opaque validateFullTopicName (name : @& String) : IO String

/-- rcl's verdict on a name as written, before expansion. -/
@[extern "rcllean_validate_topic_name_rcl"]
opaque validateTopicNameRcl (name : @& String) : IO String

@[extern "rcllean_validate_node_name"]
opaque validateNodeName (name : @& String) : IO String

@[extern "rcllean_validate_namespace"]
opaque validateNamespace (name : @& String) : IO String

/-- `rcl_expand_topic_name` with the default substitution map.  Throws when
rcl refuses the name, the node name or the namespace. -/
@[extern "rcllean_expand_topic_name"]
opaque expandTopicName (topic : @& String) (node : @& String)
    (ns : @& String) : IO String

end Rcllean.FFI

namespace Rcllean

/-! ## Characters and tokens -/

/-- Characters allowed inside a name token: letters, digits and underscore. -/
def isNameChar (c : Char) : Bool :=
  c.isAlpha || c.isDigit || c == '_'

/-- Prepend a character to the first piece of a split. -/
def consFirst (c : Char) : List (List Char) → List (List Char)
  | [] => [[c]]
  | t :: ts => (c :: t) :: ts

/-- Split a character list on `/`, keeping empty pieces.  Over characters
rather than `String.splitOn` so the predicate reduces in the kernel, which
`topic!"chatter"` needs. -/
def splitOnSlash : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    if c == '/' then [] :: splitOnSlash cs else consFirst c (splitOnSlash cs)

/-- Put the pieces of a split back together. -/
def joinSlash : List (List Char) → List Char
  | [] => []
  | [t] => t
  | t :: ts => t ++ '/' :: joinSlash ts

/-- Whether a token is a legal name component: non-empty, made of allowed
characters, and not starting with a digit. -/
def isValidTokenChars : List Char → Bool
  | [] => false
  | c :: cs => !c.isDigit && (c :: cs).all isNameChar

/-- Whether a string is a legal name component. -/
def isValidToken (s : String) : Bool := isValidTokenChars s.toList

/-! ## Expanded names -/

/-- Whether a character list is a valid fully qualified topic or service name.

The rules, from `rmw_validate_full_topic_name`: it must begin with `/`, must
not end with `/`, must not contain `//`, and every token between slashes must
be a valid name component.  A token may begin with `_`, which is how hidden
topics are written.  A trailing slash and a doubled slash both show up as an
empty token, so the token check catches them. -/
def isValidFullTopicNameChars : List Char → Bool
  | [] => false
  | c :: cs => c == '/' && (splitOnSlash cs).all isValidTokenChars

/-- Whether a string is a valid fully qualified topic or service name.

`/` alone is a valid namespace but not a valid topic name: a topic needs at
least one token after the leading slash. -/
def isValidFullTopicName (s : String) : Bool :=
  isValidFullTopicNameChars s.toList

/-- Whether a string is a valid node name: a single token, no slashes. -/
def isValidNodeName (s : String) : Bool := isValidToken s

/-- Whether a character list is a valid namespace: the root, or an expanded
name. -/
def isValidNamespaceChars (cs : List Char) : Bool :=
  cs == ['/'] || isValidFullTopicNameChars cs

/-- Whether a string is a valid namespace. -/
def isValidNamespace (s : String) : Bool := isValidNamespaceChars s.toList

/-! ## Names as written

rcl expands a name against the node before it reaches the middleware, so what
a user writes follows the looser rules of `rcl_validate_topic_name`: a name may
be relative, may start with `~`, and may contain `{...}` substitutions.

A token is parsed into pieces, and a piece carries the proof that a literal
character is a name character.  Rendering pieces then cannot produce a
character the expanded rules reject, so the parser needs no lemma of its
own. -/

/-- A piece of a token as written: a literal character or the node name. -/
inductive Piece where
  | lit (c : Char) (h : isNameChar c = true)
  | node

/-- Parse one token.  `none` when it holds a character that is not allowed, an
unbalanced brace, or a substitution other than `{node}`.

rcl's validator admits any `{name}` whose contents are token characters and
leaves unknown names to `rcl_expand_topic_name`, which fails with
`RCL_RET_UNKNOWN_SUBSTITUTION`.  Only `{node}`, `{ns}` and `{namespace}` ever
expand, and `{ns}` and `{namespace}` splice a namespace, which begins with `/`,
into the middle of a name: under the root namespace `{ns}/x` expands to `//x`
and `{ns}` to `/`, both of which rmw then rejects.  Only `{node}` is accepted
here, so `expand` is total. -/
def parseToken : List Char → Option (List Piece)
  | [] => some []
  | '{' :: 'n' :: 'o' :: 'd' :: 'e' :: '}' :: rest =>
    (parseToken rest).map (Piece.node :: ·)
  | '{' :: _ => none
  | c :: cs =>
    if h : isNameChar c = true then (parseToken cs).map (Piece.lit c h :: ·)
    else none

/-- Parse every token of a split name. -/
def parseTokens : List (List Char) → Option (List (List Piece))
  | [] => some []
  | t :: ts =>
    match parseToken t, parseTokens ts with
    | some ps, some pss => some (ps :: pss)
    | _, _ => none

/-- Whether a token is non-empty and does not start with a digit.  A token
that starts with `{node}` starts with the node name's first character, which a
node name may not have as a digit either. -/
def headPieceOk : List Piece → Bool
  | [] => false
  | .node :: _ => true
  | .lit c _ :: _ => !c.isDigit

/-- Split a name as written into its tokens and whether the node's namespace
goes in front.  `~` and `~/rest` put the node name in as a token of its own. -/
def splitName : List Char → Option (Bool × List (List Piece))
  | [] => none
  | ['~'] => some (true, [[Piece.node]])
  | '~' :: '/' :: body =>
    (parseTokens (splitOnSlash body)).map fun ts => (true, [Piece.node] :: ts)
  | '~' :: _ => none
  | '/' :: body => (parseTokens (splitOnSlash body)).map fun ts => (false, ts)
  | cs => (parseTokens (splitOnSlash cs)).map fun ts => (true, ts)

/-- Whether a character list is a valid topic or service name as written,
before rcl expands it. -/
def isValidTopicNameChars (t : List Char) : Bool :=
  match splitName t with
  | some (_, ts) => !ts.isEmpty && ts.all headPieceOk
  | none => false

/-- Whether a string is a valid topic or service name as written.

The rules, from `rcl_validate_topic_name`: not empty, not ending in `/`, tokens
of letters, digits and underscore with no token starting with a digit, `~`
alone or as the first token followed by `/`, and `{node}` as a whole token or
part of one.

Stricter than rcl's validator in three places, each of which rcl catches later
rather than never: a doubled slash (rcl leaves it to rmw after expansion), a
substitution other than `{node}` (rcl leaves it to its expander), and a
two-character name beginning with `~` such as `~a`, which rcl accepts through
an off-by-one in its token loop and then expands to the node name with the
character glued on. -/
def isValidTopicName (s : String) : Bool := isValidTopicNameChars s.toList

/-! ## Checked names -/

/-- A fully qualified topic or service name, as rcl hands one back. -/
structure FullTopicName where
  toString : String
  isValid : isValidFullTopicName toString = true
deriving Repr

/-- A topic or service name as written, known to be well formed. -/
structure TopicName where
  toString : String
  isValid : isValidTopicName toString = true
deriving Repr

/-- A node name known to be well formed. -/
structure NodeName where
  toString : String
  isValid : isValidNodeName toString = true
deriving Repr

/-- A namespace known to be well formed. -/
structure Namespace where
  toString : String
  isValid : isValidNamespace toString = true
deriving Repr

namespace FullTopicName

/-- Check an expanded name at run time. -/
def ofString? (s : String) : Option FullTopicName :=
  if h : isValidFullTopicName s = true then some ⟨s, h⟩ else none

instance : ToString FullTopicName := ⟨FullTopicName.toString⟩

end FullTopicName

namespace TopicName

/-- Check a name at run time. -/
def ofString? (s : String) : Option TopicName :=
  if h : isValidTopicName s = true then some ⟨s, h⟩ else none

instance : ToString TopicName := ⟨TopicName.toString⟩

end TopicName

namespace NodeName

def ofString? (s : String) : Option NodeName :=
  if h : isValidNodeName s = true then some ⟨s, h⟩ else none

instance : ToString NodeName := ⟨NodeName.toString⟩

end NodeName

namespace Namespace

def ofString? (s : String) : Option Namespace :=
  if h : isValidNamespace s = true then some ⟨s, h⟩ else none

instance : ToString Namespace := ⟨Namespace.toString⟩

/-- The root namespace, which is what a node gets when none is given. -/
def root : Namespace := ⟨"/", by decide⟩

end Namespace

/-- `topic!"chatter"` is a topic name checked while the program is compiled;
a malformed name is a compile error.  The name is the one a user writes, so
`topic!"chatter"` and `topic!"~/status"` are both fine. -/
macro:max "topic!" s:str : term => `(TopicName.mk $s (by decide))

/-- `fullTopic!"/chatter"` is an expanded name checked while the program is
compiled. -/
macro:max "fullTopic!" s:str : term => `(FullTopicName.mk $s (by decide))

/-- `node!"my_node"` is a node name checked while the program is compiled. -/
macro:max "node!" s:str : term => `(NodeName.mk $s (by decide))

/-- `ns!"/robot"` is a namespace checked while the program is compiled. -/
macro:max "ns!" s:str : term => `(Namespace.mk $s (by decide))

/-! ## Expansion

`rcl_expand_topic_name` in Lean: `~` becomes `<ns>/<node>`, a relative name
gets `<ns>/` in front, an absolute name is left alone, and `{node}` becomes the
node name.  The root namespace is `/`, so the prefix cases join tokens rather
than concatenate strings and no `//` can appear. -/

/-- Fill the node name into the pieces of a token. -/
def render (node : List Char) : List Piece → List Char
  | [] => []
  | .lit c _ :: ps => c :: render node ps
  | .node :: ps => node ++ render node ps

/-- The tokens of a namespace: none for the root. -/
def namespaceTokensChars : List Char → List (List Char)
  | [] => []
  | _ :: rest => if rest.isEmpty then [] else splitOnSlash rest

/-- The tokens the expanded name is made of. -/
def expandTokens (t node : List Char) (nsToks : List (List Char)) :
    List (List Char) :=
  match splitName t with
  | some (pns, ts) => (if pns then nsToks else []) ++ ts.map (render node)
  | none => []

/-- The expanded name, as characters. -/
def expandChars (t node ns : List Char) : List Char :=
  '/' :: joinSlash (expandTokens t node (namespaceTokensChars ns))

/-! ## What the rules guarantee -/

theorem consFirst_ne_nil (c : Char) (l : List (List Char)) :
    consFirst c l ≠ [] := by
  cases l <;> simp [consFirst]

theorem splitOnSlash_ne_nil (cs : List Char) : splitOnSlash cs ≠ [] := by
  induction cs with
  | nil => simp [splitOnSlash]
  | cons c cs ih =>
    simp only [splitOnSlash]
    split
    · simp
    · exact consFirst_ne_nil c _

theorem consFirst_append (c : Char) {l : List (List Char)} (h : l ≠ [])
    (m : List (List Char)) : consFirst c (l ++ m) = consFirst c l ++ m := by
  cases l with
  | nil => exact absurd rfl h
  | cons t ts => simp [consFirst]

/-- Splitting a join splits at the joint. -/
theorem splitOnSlash_append (a b : List Char) :
    splitOnSlash (a ++ '/' :: b) = splitOnSlash a ++ splitOnSlash b := by
  induction a with
  | nil => simp [splitOnSlash]
  | cons c a ih =>
    simp only [List.cons_append, splitOnSlash]
    split
    · simp [ih]
    · rw [ih, consFirst_append c (splitOnSlash_ne_nil a)]

/-- A piece with no slash in it splits into itself. -/
theorem splitOnSlash_no_slash {cs : List Char} (h : cs.all isNameChar = true) :
    splitOnSlash cs = [cs] := by
  induction cs with
  | nil => simp [splitOnSlash]
  | cons c cs ih =>
    simp only [List.all_cons, Bool.and_eq_true] at h
    have hc : (c == '/') = false := by
      cases hh : c == '/' with
      | false => rfl
      | true =>
        have hce : c = '/' := by simpa using hh
        subst hce
        exact absurd h.1 (by decide)
    simp [splitOnSlash, hc, ih h.2, consFirst]

theorem all_nameChar_of_token {t : List Char} (h : isValidTokenChars t = true) :
    t.all isNameChar = true := by
  cases t with
  | nil => simp [isValidTokenChars] at h
  | cons c cs => simp only [isValidTokenChars, Bool.and_eq_true] at h; exact h.2

/-- Joining valid tokens with slashes gives a body every token of which is
still valid. -/
theorem all_valid_join : ∀ ts : List (List Char), ts ≠ [] →
    ts.all isValidTokenChars = true →
    (splitOnSlash (joinSlash ts)).all isValidTokenChars = true
  | [], h, _ => absurd rfl h
  | [t], _, h => by
    simp only [List.all_cons, List.all_nil, Bool.and_true] at h
    simp [joinSlash, splitOnSlash_no_slash (all_nameChar_of_token h), h]
  | t :: u :: ts, _, h => by
    simp only [List.all_cons, Bool.and_eq_true] at h
    have hjoin : joinSlash (t :: u :: ts) = t ++ '/' :: joinSlash (u :: ts) :=
      rfl
    rw [hjoin, splitOnSlash_append,
      splitOnSlash_no_slash (all_nameChar_of_token h.1)]
    simp only [List.all_append, List.all_cons, List.all_nil, Bool.and_true,
      Bool.and_eq_true]
    exact ⟨h.1, all_valid_join (u :: ts) (by simp) (by simp [h.2.1, h.2.2])⟩

/-- Rendering only ever emits characters a name token may hold. -/
theorem render_all_nameChar (node : List Char)
    (hn : node.all isNameChar = true) :
    ∀ ps : List Piece, (render node ps).all isNameChar = true
  | [] => by simp [render]
  | .lit c h :: ps => by simp [render, h, render_all_nameChar node hn ps]
  | .node :: ps => by
    simp [render, List.all_append, hn, render_all_nameChar node hn ps]

/-- Rendering a token that does not start with a digit gives a valid token. -/
theorem render_valid {node : List Char} (hn : isValidTokenChars node = true) :
    ∀ ps : List Piece, headPieceOk ps = true →
      isValidTokenChars (render node ps) = true
  | [], h => by simp [headPieceOk] at h
  | .lit c hc :: ps, h => by
    simp only [headPieceOk, Bool.not_eq_true'] at h
    simp [render, isValidTokenChars, h, hc,
      render_all_nameChar node (all_nameChar_of_token hn) ps]
  | .node :: ps, _ => by
    cases node with
    | nil => simp [isValidTokenChars] at hn
    | cons d ds =>
      simp only [isValidTokenChars, List.all_cons, Bool.and_eq_true,
        Bool.not_eq_true'] at hn
      simp [render, isValidTokenChars, List.all_append, hn.1, hn.2.1, hn.2.2,
        render_all_nameChar (d :: ds) (by simp [hn.2.1, hn.2.2]) ps]

theorem map_render_valid {node : List Char}
    (hn : isValidTokenChars node = true) :
    ∀ ts : List (List Piece), ts.all headPieceOk = true →
      (ts.map (render node)).all isValidTokenChars = true
  | [], _ => by simp
  | t :: ts, h => by
    simp only [List.all_cons, Bool.and_eq_true] at h
    simp [render_valid hn t h.1, map_render_valid hn ts h.2]

theorem namespaceTokens_valid {ns : List Char}
    (h : isValidNamespaceChars ns = true) :
    (namespaceTokensChars ns).all isValidTokenChars = true := by
  unfold isValidNamespaceChars at h
  cases ns with
  | nil => simp [namespaceTokensChars]
  | cons c rest =>
    simp only [namespaceTokensChars]
    split
    · simp
    · rename_i hr
      rcases Bool.or_eq_true .. ▸ h with h1 | h2
      · exfalso
        have hns : c :: rest = ['/'] := by simpa using h1
        have hnil : rest = [] := by
          have := congrArg List.tail hns
          simpa using this
        exact hr (by simp [hnil])
      · simp only [isValidFullTopicNameChars, Bool.and_eq_true] at h2
        exact h2.2

/-- Every name that passes the pre-expansion rules expands to one that passes
the post-expansion rules.  `TopicName.expand` returns a `FullTopicName` on
this, with no runtime check. -/
theorem expandChars_valid {t node ns : List Char}
    (ht : isValidTopicNameChars t = true) (hn : isValidTokenChars node = true)
    (hs : isValidNamespaceChars ns = true) :
    isValidFullTopicNameChars (expandChars t node ns) = true := by
  have hns := namespaceTokens_valid hs
  unfold isValidTopicNameChars at ht
  unfold expandChars expandTokens
  cases hsp : splitName t with
  | none => rw [hsp] at ht; simp at ht
  | some p =>
    obtain ⟨pns, ts⟩ := p
    rw [hsp] at ht
    simp only [Bool.and_eq_true, Bool.not_eq_true',
      List.isEmpty_eq_false_iff] at ht
    have hall : ((if pns then namespaceTokensChars ns else []) ++
        ts.map (render node)).all isValidTokenChars = true := by
      simp only [List.all_append, Bool.and_eq_true]
      refine ⟨?_, map_render_valid hn ts ht.2⟩
      split <;> simp [hns]
    have hne : ((if pns then namespaceTokensChars ns else []) ++
        ts.map (render node)) ≠ [] := by
      simp only [ne_eq, List.append_eq_nil_iff, not_and]
      intro _
      simpa using ht.1
    simp only [isValidFullTopicNameChars, beq_self_eq_true, Bool.true_and]
    exact all_valid_join _ hne hall

namespace TopicName

/-- Expand a name against a node, as `rcl_expand_topic_name` does.  The result
is a `FullTopicName` by construction, not by checking. -/
def expand (t : TopicName) (node : NodeName) (ns : Namespace) : FullTopicName :=
  ⟨String.ofList (expandChars t.toString.toList node.toString.toList
      ns.toString.toList),
   by
     unfold isValidFullTopicName
     rw [String.toList_ofList]
     exact expandChars_valid t.isValid node.isValid ns.isValid⟩

end TopicName

/-! ## The rules, stated -/

/-- The root namespace is valid; an unqualified node gets it. -/
theorem root_namespace_valid : isValidNamespace "/" = true := by decide

/-- A bare slash is a namespace, not a topic; the two rule sets differ only
here. -/
theorem root_is_not_a_full_topic : isValidFullTopicName "/" = false := by decide

/-- An expanded name must be absolute. -/
theorem relative_full_topic_invalid :
    isValidFullTopicName "chatter" = false := by decide

/-- A name must not end in a slash. -/
theorem trailing_slash_full_invalid :
    isValidFullTopicName "/chatter/" = false := by decide
theorem trailing_slash_invalid :
    isValidTopicName "chatter/" = false := by decide

/-- Empty tokens are rejected, which rules out a doubled slash. -/
theorem double_slash_full_invalid :
    isValidFullTopicName "/a//b" = false := by decide
theorem double_slash_invalid : isValidTopicName "a//b" = false := by decide

/-- A token may not start with a digit. -/
theorem leading_digit_full_invalid :
    isValidFullTopicName "/1abc" = false := by decide
theorem leading_digit_invalid : isValidTopicName "1abc" = false := by decide

/-- Spaces and punctuation are not name characters. -/
theorem space_full_invalid :
    isValidFullTopicName "/has space" = false := by decide
theorem dash_full_invalid :
    isValidFullTopicName "/has-dash" = false := by decide
theorem dash_invalid : isValidTopicName "has-dash" = false := by decide

/-- Ordinary expanded names are accepted. -/
theorem simple_full_valid : isValidFullTopicName "/chatter" = true := by decide
theorem nested_full_valid :
    isValidFullTopicName "/robot/arm/joint_states" = true := by decide
theorem underscore_full_valid :
    isValidFullTopicName "/_hidden" = true := by decide

/-- A name as written may be relative, private or substituted. -/
theorem relative_valid : isValidTopicName "chatter" = true := by decide
theorem private_valid : isValidTopicName "~/status" = true := by decide
theorem private_alone_valid : isValidTopicName "~" = true := by decide
theorem absolute_valid : isValidTopicName "/chatter" = true := by decide
theorem node_substitution_valid : isValidTopicName "{node}/state" = true := by
  decide

/-- A tilde anywhere but the front is rejected, and one that is not the whole
name must be followed by a slash. -/
theorem misplaced_tilde_invalid : isValidTopicName "a/~/b" = false := by decide
theorem tilde_not_slash_invalid : isValidTopicName "~foo" = false := by decide

/-- Only `{node}` expands, so only `{node}` is accepted. -/
theorem unknown_substitution_invalid :
    isValidTopicName "{unknown}" = false := by decide
theorem namespace_substitution_invalid :
    isValidTopicName "{ns}/x" = false := by decide
theorem unmatched_brace_invalid : isValidTopicName "{node" = false := by decide

/-- A node name is a single token, so a slash disqualifies it. -/
theorem node_name_rejects_slash : isValidNodeName "/foo" = false := by decide
theorem node_name_simple : isValidNodeName "my_node" = true := by decide

/-! ## Asking rcl and rmw

The middleware's own verdicts, for the corpus test that keeps the Lean rules in
step with them. -/

namespace Names

/-- rcl's verdict on a name as written: `none` if valid, else its
explanation. -/
def rclTopicNameError (name : String) : IO (Option String) := do
  let e ← FFI.validateTopicNameRcl name
  return if e.isEmpty then none else some e

/-- rmw's verdict on an expanded name. -/
def rmwFullTopicNameError (name : String) : IO (Option String) := do
  let e ← FFI.validateFullTopicName name
  return if e.isEmpty then none else some e

def rmwNodeNameError (name : String) : IO (Option String) := do
  let e ← FFI.validateNodeName name
  return if e.isEmpty then none else some e

def rmwNamespaceError (name : String) : IO (Option String) := do
  let e ← FFI.validateNamespace name
  return if e.isEmpty then none else some e

/-- `rcl_expand_topic_name`'s own answer, for comparison with
`TopicName.expand`. -/
def rclExpand (topic node ns : String) : IO String :=
  FFI.expandTopicName topic node ns

end Names

end Rcllean
