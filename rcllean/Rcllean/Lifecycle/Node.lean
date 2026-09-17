import Rcllean.Lifecycle.State
import Rcllean.Service
import Rcllean.Executor
import LifecycleMsgs

/-!
# Managed nodes

A lifecycle node exposes its state machine over five services and one topic,
which `ros2 lifecycle list`, `get` and `set` talk to.  The user writes the
transition handlers; one that returns failure leaves the node where it was.
-/

namespace Rcllean

open RosidlRuntimeLean Rcllean.Lifecycle

/-- What a transition handler decided. -/
inductive TransitionResult where
  /-- The move happened. -/
  | success
  /-- The move did not happen; the node stays where it was. -/
  | failure
deriving DecidableEq, Repr, Inhabited, BEq

/-- What to run on each transition.  Each defaults to succeeding without
doing anything. -/
structure LifecycleCallbacks where
  onConfigure : IO TransitionResult := return .success
  onCleanup : IO TransitionResult := return .success
  onActivate : IO TransitionResult := return .success
  onDeactivate : IO TransitionResult := return .success
  onShutdown : IO TransitionResult := return .success

/-- A node with a lifecycle. -/
structure LifecycleNode where
  node : Node
  /-- Where the node is now. -/
  state : IO.Ref PrimaryState
  callbacks : LifecycleCallbacks
  changeState : Service LifecycleMsgs.Srv.ChangeState
  getState : Service LifecycleMsgs.Srv.GetState
  getAvailableStates : Service LifecycleMsgs.Srv.GetAvailableStates
  getAvailableTransitions : Service LifecycleMsgs.Srv.GetAvailableTransitions
  getTransitionGraph : Service LifecycleMsgs.Srv.GetAvailableTransitions
  /-- Announces each move, so other nodes can follow along. -/
  transitionEvents : Publisher LifecycleMsgs.Msg.TransitionEvent

namespace LifecycleNode

private def stateMsg (s : PrimaryState) : LifecycleMsgs.Msg.State :=
  { id := s.toUInt8, label := s.label }

private def transitionMsg (t : TransitionId) (from_ : PrimaryState) :
    LifecycleMsgs.Msg.Transition :=
  { id := t.toUInt8 from_, label := t.label }

/-- Attempt a transition.  The move is checked against the state machine, then
the handler runs; a handler that fails leaves the node where it was. -/
def attempt (ln : LifecycleNode) (t : TransitionId) : IO Bool := do
  let current ← ln.state.get
  match step current t with
  | none =>
    ln.node.logWarn s!"{t} is not available from {current}"
    return false
  | some target =>
    let handler := match t with
      | .configure => ln.callbacks.onConfigure
      | .cleanup => ln.callbacks.onCleanup
      | .activate => ln.callbacks.onActivate
      | .deactivate => ln.callbacks.onDeactivate
      | .shutdown => ln.callbacks.onShutdown
    match ← handler with
    | .failure =>
      ln.node.logWarn s!"{t} failed; staying {current}"
      return false
    | .success =>
      ln.state.set target
      ln.node.logInfo s!"{current} -> {target} ({t})"
      -- A publish failure must not undo a transition that already happened.
      try
        ln.transitionEvents.publish
          { transition := transitionMsg t current
            start_state := stateMsg current
            goal_state := stateMsg target }
      catch _ => pure ()
      return true

/-- Where the node is now. -/
def currentState (ln : LifecycleNode) : IO PrimaryState := ln.state.get

/-- Create a managed node.  It starts unconfigured, as the standard
requires. -/
def create (node : Node) (callbacks : LifecycleCallbacks := {}) :
    IO LifecycleNode := do
  let state ← IO.mkRef PrimaryState.unconfigured
  let events ← node.createPublisher LifecycleMsgs.Msg.TransitionEvent
    topic!"~/transition_event" (QoS.transientLocal 10)
  let nodeRef ← IO.mkRef (none : Option LifecycleNode)

  let changeState ← node.createService LifecycleMsgs.Srv.ChangeState
    topic!"~/change_state" fun req => do
      match TransitionId.ofUInt8? req.transition.id with
      | none => return { success := false }
      | some t =>
        match ← nodeRef.get with
        | none => return { success := false }
        | some ln => return { success := ← ln.attempt t }

  let getState ← node.createService LifecycleMsgs.Srv.GetState
    topic!"~/get_state" fun _ => do
      return { current_state := stateMsg (← state.get) }

  let getAvailableStates ← node.createService
    LifecycleMsgs.Srv.GetAvailableStates topic!"~/get_available_states"
    fun _ => do
      return { available_states := (PrimaryState.all.map stateMsg).toArray }

  let getAvailableTransitions ← node.createService
    LifecycleMsgs.Srv.GetAvailableTransitions
    topic!"~/get_available_transitions" fun _ => do
      let current ← state.get
      -- Only the moves legal from here; `available_sound` proves `step`
      -- accepts each of them.
      let ts := (available current).filterMap fun t =>
        match step current t with
        | none => none
        | some target =>
          some ({ transition := transitionMsg t current
                  start_state := stateMsg current
                  goal_state := stateMsg target } :
                LifecycleMsgs.Msg.TransitionDescription)
      return { available_transitions := ts.toArray }

  -- The whole graph, regardless of where the node is now.
  let getTransitionGraph ← node.createService
    LifecycleMsgs.Srv.GetAvailableTransitions topic!"~/get_transition_graph"
    fun _ => do
      let mut all : Array LifecycleMsgs.Msg.TransitionDescription := #[]
      for s in PrimaryState.all do
        for t in available s do
          if let some target := step s t then
            all := all.push { transition := transitionMsg t s
                              start_state := stateMsg s
                              goal_state := stateMsg target }
      return { available_transitions := all }

  let ln : LifecycleNode :=
    { node, state, callbacks, changeState, getState, getAvailableStates,
      getAvailableTransitions, getTransitionGraph, transitionEvents := events }
  nodeRef.set (some ln)
  return ln

/-- Register the lifecycle services with an executor so they are answered. -/
def addToExecutor (ln : LifecycleNode) (ex : Executor) : IO Unit := do
  ex.addService ln.changeState
  ex.addService ln.getState
  ex.addService ln.getAvailableStates
  ex.addService ln.getAvailableTransitions
  ex.addService ln.getTransitionGraph

def destroy (ln : LifecycleNode) : IO Unit := do
  ln.changeState.destroy
  ln.getState.destroy
  ln.getAvailableStates.destroy
  ln.getAvailableTransitions.destroy
  ln.getTransitionGraph.destroy
  ln.transitionEvents.destroy

end LifecycleNode

end Rcllean
