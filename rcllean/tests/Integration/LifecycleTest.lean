import Rcllean
import Support
import LifecycleMsgs

/-!
Lifecycle tests.  The state machine's own properties are proved in
`Rcllean.Lifecycle.State`; these check that a running node follows it and
reports the state it is in.
-/

open Rcllean Rcllean.Lifecycle Rcllean.Test

def testTransitions : IO Unit := do
  IO.println "the managed node follows its state machine"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_lifecycle_test"
  let configured ← IO.mkRef 0
  let activated ← IO.mkRef 0

  let ln ← LifecycleNode.create node
    { onConfigure := do configured.modify (· + 1); return .success
      onActivate := do activated.modify (· + 1); return .success }

  check "a new node is unconfigured" ((← ln.currentState) == .unconfigured)
    s!"it was {← ln.currentState}"

  -- The type-level machine forbids this transition; the running node must
  -- refuse it too.
  check "activating an unconfigured node is refused"
    (!(← ln.attempt .activate))
  check "a refused transition leaves the state alone"
    ((← ln.currentState) == .unconfigured) s!"it became {← ln.currentState}"
  check "a refused transition does not run the handler"
    ((← activated.get) == 0) "the activate handler ran"

  check "configuring succeeds" (← ln.attempt .configure)
  check "the node is now inactive" ((← ln.currentState) == .inactive)
  check "the configure handler ran" ((← configured.get) == 1)

  check "activating succeeds" (← ln.attempt .activate)
  check "the node is now active" ((← ln.currentState) == .active)

  check "cleaning up an active node is refused" (!(← ln.attempt .cleanup))
  check "deactivating succeeds" (← ln.attempt .deactivate)
  check "cleaning up an inactive node succeeds" (← ln.attempt .cleanup)
  check "the node is unconfigured again" ((← ln.currentState) == .unconfigured)

  ln.destroy
  node.destroy
  ctx.shutdown

def testFailingHandler : IO Unit := do
  IO.println "a handler that fails"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_lifecycle_fail"
  -- A node that cannot acquire its resources must not claim to be configured.
  let ln ← LifecycleNode.create node { onConfigure := return .failure }

  check "a failing transition reports failure" (!(← ln.attempt .configure))
  check "the node stays where it was" ((← ln.currentState) == .unconfigured)
    s!"it became {← ln.currentState}"

  ln.destroy
  node.destroy
  ctx.shutdown

def testTerminal : IO Unit := do
  IO.println "finalized is a dead end"
  let ctx ← Context.init
  let node ← Node.create ctx "rcllean_lifecycle_terminal"
  let ln ← LifecycleNode.create node

  check "shutting down succeeds" (← ln.attempt .shutdown)
  check "the node is finalized" ((← ln.currentState) == .finalized)
  for t in [TransitionId.configure, .cleanup, .activate, .deactivate, .shutdown] do
    check s!"{t} is refused once finalized" (!(← ln.attempt t))
  check "nothing is available from finalized" (available .finalized == [])

  ln.destroy
  node.destroy
  ctx.shutdown

def main : IO UInt32 := do
  IO.println "lifecycle tests"
  testTransitions
  testFailingHandler
  testTerminal
  finish "lifecycle"
