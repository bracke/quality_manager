--  Defines recoverable external-operation journal states and replay actions.
package Quality_Manager.Journal
  with Pure, SPARK_Mode
is
   --  Recoverable journal lifecycle and replay decisions.
   type Journal_State is
     (Prepared, Invoking, Reconciling, Committed, Aborted, Needs_Intervention);
   --  Durable external-operation journal phase.
   --  @enum Prepared The operation intent is durable but has not started.
   --  @enum Invoking The external operation may be in progress.
   --  @enum Reconciling The external outcome is being adopted locally.
   --  @enum Committed The observed outcome is durably committed.
   --  @enum Aborted The operation ended with preserved failure evidence.
   --  @enum Needs_Intervention Automatic recovery cannot proceed safely.

   type Recovery_Action is
     (Invoke_After_Revalidation,
      Query_External_Identity,
      Adopt_Confirmed_Result,
      No_Action,
      Preserve_Failure,
      Escalate);
   --  Recovery action selected for a journal phase.
   --  @enum Invoke_After_Revalidation Revalidate preconditions and invoke.
   --  @enum Query_External_Identity Query the durable external operation identity.
   --  @enum Adopt_Confirmed_Result Adopt a confirmed external result.
   --  @enum No_Action The operation needs no recovery work.
   --  @enum Preserve_Failure Retain the final failure evidence.
   --  @enum Escalate Require explicit operator intervention.

   function Action_For (State : Journal_State) return Recovery_Action;
   --  Return the recovery action required by State.
   --  @param State Journal phase.
   --  @return Required recovery action.
   function Allowed (From_State, To_State : Journal_State) return Boolean;
   --  Test whether a journal transition is valid.
   --  @param From_State Current journal phase.
   --  @param To_State Proposed journal phase.
   --  @return True when the transition is valid.
   function Is_Terminal (State : Journal_State) return Boolean;
   --  Test whether State is terminal.
   --  @param State Journal phase.
   --  @return True for committed, aborted, or intervention states.
end Quality_Manager.Journal;
