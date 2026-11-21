package Quality_Manager.Journal
  with Pure
is
   type Journal_State is
     (Prepared, Invoking, Reconciling, Committed, Aborted, Needs_Intervention);

   type Recovery_Action is
     (Invoke_After_Revalidation,
      Query_External_Identity,
      Adopt_Confirmed_Result,
      No_Action,
      Preserve_Failure,
      Escalate);

   function Action_For (State : Journal_State) return Recovery_Action;
   function Allowed (From_State, To_State : Journal_State) return Boolean;
   function Is_Terminal (State : Journal_State) return Boolean;
end Quality_Manager.Journal;
