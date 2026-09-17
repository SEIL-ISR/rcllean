/-!
# The lifecycle state machine

A managed node moves through four states, and only certain moves are legal.
`Transition from to` exists only for the moves the standard allows, so
activating an unconfigured node does not compile.  `step` is the runtime
counterpart, for requests that arrive over a service carrying a number rather
than a proof; the theorems below tie the two together.
-/

namespace Rcllean.Lifecycle

/-- The four states a managed node rests in.  Values match
`lifecycle_msgs/msg/State`. -/
inductive PrimaryState where
  /-- Created but not yet configured: no resources held. -/
  | unconfigured
  /-- Configured and holding resources, but not processing. -/
  | inactive
  /-- Doing its job. -/
  | active
  /-- Shut down for good. -/
  | finalized
deriving DecidableEq, Repr, Inhabited, BEq

namespace PrimaryState

def toUInt8 : PrimaryState → UInt8
  | .unconfigured => 1 | .inactive => 2 | .active => 3 | .finalized => 4

def ofUInt8? : UInt8 → Option PrimaryState
  | 1 => some .unconfigured | 2 => some .inactive | 3 => some .active
  | 4 => some .finalized | _ => none

@[simp] theorem ofUInt8?_toUInt8 (s : PrimaryState) :
    ofUInt8? s.toUInt8 = some s := by cases s <;> rfl

def label : PrimaryState → String
  | .unconfigured => "unconfigured" | .inactive => "inactive"
  | .active => "active" | .finalized => "finalized"

instance : ToString PrimaryState := ⟨label⟩

/-- Every state, for answering `get_available_states`. -/
def all : List PrimaryState := [.unconfigured, .inactive, .active, .finalized]

end PrimaryState

/-- The moves a caller can ask for.  Values match
`lifecycle_msgs/msg/Transition`. -/
inductive TransitionId where
  | configure | cleanup | activate | deactivate
  /-- Shutting down is legal from any live state; the code it carries on the
  wire depends on where it starts. -/
  | shutdown
deriving DecidableEq, Repr, Inhabited, BEq

namespace TransitionId

def label : TransitionId → String
  | .configure => "configure" | .cleanup => "cleanup"
  | .activate => "activate" | .deactivate => "deactivate"
  | .shutdown => "shutdown"

instance : ToString TransitionId := ⟨label⟩

/-- The wire code for a transition, which for shutdown depends on the state it
starts from. -/
def toUInt8 (t : TransitionId) (from_ : PrimaryState) : UInt8 :=
  match t with
  | .configure => 1
  | .cleanup => 2
  | .activate => 3
  | .deactivate => 4
  | .shutdown =>
    match from_ with
    | .unconfigured => 5
    | .inactive => 6
    | .active => 7
    | .finalized => 8

-- Code 8 is shutdown from `finalized`, which `step` refuses anyway, so it is
-- rejected here rather than accepted and then declined.
def ofUInt8? : UInt8 → Option TransitionId
  | 1 => some .configure | 2 => some .cleanup | 3 => some .activate
  | 4 => some .deactivate | 5 => some .shutdown | 6 => some .shutdown
  | 7 => some .shutdown | _ => none

end TransitionId

/-- The transition relation.  A value of `Transition s t` is a proof that the
standard allows moving from `s` to `t`. -/
inductive Transition : PrimaryState → PrimaryState → Type where
  /-- Acquire resources. -/
  | configure : Transition .unconfigured .inactive
  /-- Release resources. -/
  | cleanup : Transition .inactive .unconfigured
  /-- Start doing the job. -/
  | activate : Transition .inactive .active
  /-- Stop doing the job, keeping resources. -/
  | deactivate : Transition .active .inactive
  | shutdownUnconfigured : Transition .unconfigured .finalized
  | shutdownInactive : Transition .inactive .finalized
  | shutdownActive : Transition .active .finalized

namespace Transition

/-- Which move this is, for reporting. -/
def id {s t : PrimaryState} : Transition s t → TransitionId
  | .configure => .configure
  | .cleanup => .cleanup
  | .activate => .activate
  | .deactivate => .deactivate
  | .shutdownUnconfigured => .shutdown
  | .shutdownInactive => .shutdown
  | .shutdownActive => .shutdown

end Transition

/-- Where a requested move lands, if it is legal.  The runtime counterpart of
`Transition`, for requests that carry a number rather than a proof. -/
def step (s : PrimaryState) (t : TransitionId) : Option PrimaryState :=
  match s, t with
  | .unconfigured, .configure => some .inactive
  | .inactive, .cleanup => some .unconfigured
  | .inactive, .activate => some .active
  | .active, .deactivate => some .inactive
  | .unconfigured, .shutdown => some .finalized
  | .inactive, .shutdown => some .finalized
  | .active, .shutdown => some .finalized
  | _, _ => none

/-- The moves available from a state, for answering
`get_available_transitions`. -/
def available : PrimaryState → List TransitionId
  | .unconfigured => [.configure, .shutdown]
  | .inactive => [.cleanup, .activate, .shutdown]
  | .active => [.deactivate, .shutdown]
  | .finalized => []

/-! ## What the machine guarantees -/

/-- If a `Transition s t` exists, `step` lands on `t`: the typed relation and
the runtime check agree. -/
theorem step_of_transition {s t : PrimaryState} (tr : Transition s t) :
    step s tr.id = some t := by
  cases tr <;> rfl

/-- A finalized node has nowhere left to go. -/
theorem finalized_is_terminal (t : TransitionId) : step .finalized t = none := by
  cases t <;> rfl

/-- Every move `available` lists is one `step` accepts, so a node cannot offer
a transition it would then refuse. -/
theorem available_sound (s : PrimaryState) :
    ∀ t ∈ available s, (step s t).isSome = true := by
  cases s <;> intro t ht <;> simp [available] at ht <;>
    (try rcases ht with h | h | h) <;> (try subst h) <;> rfl

/-- The converse: every move `step` accepts is one `available` lists. -/
theorem available_complete (s : PrimaryState) (t : TransitionId)
    (h : (step s t).isSome = true) : t ∈ available s := by
  cases s <;> cases t <;> simp [step, available] at h ⊢

/-- The other direction of `step_of_transition`: whenever `step` accepts a
move, the typed relation has a witness for it. -/
theorem transition_of_step (s t : PrimaryState) (id : TransitionId)
    (h : step s id = some t) : Nonempty (Transition s t) := by
  cases s <;> cases id <;> simp [step] at h <;> subst h <;>
    exact ⟨by constructor⟩

/-- `active` is reachable only from `inactive`, so a node cannot start work
without configuring first. -/
theorem active_only_from_inactive (s : PrimaryState) (t : TransitionId)
    (h : step s t = some .active) : s = .inactive := by
  cases s <;> cases t <;> simp [step] at h <;> rfl

/-- Configuring is the only way out of `unconfigured` other than shutting
down. -/
theorem unconfigured_moves (t : TransitionId) (s : PrimaryState)
    (h : step .unconfigured t = some s) :
    (t = .configure ∧ s = .inactive) ∨ (t = .shutdown ∧ s = .finalized) := by
  cases t <;> simp [step] at h <;> simp [h]

/-- Every state is reachable from `unconfigured`. -/
theorem inactive_reachable : step .unconfigured .configure = some .inactive := rfl
theorem active_reachable : step .inactive .activate = some .active := rfl
theorem finalized_reachable : step .unconfigured .shutdown = some .finalized := rfl

end Rcllean.Lifecycle
