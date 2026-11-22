package body Quality_Manager.Journal
  with SPARK_Mode
is
   function Action_For (State : Journal_State) return Recovery_Action is
     (case State is
         when Prepared           => Invoke_After_Revalidation,
         when Invoking           => Query_External_Identity,
         when Reconciling        => Adopt_Confirmed_Result,
         when Committed          => No_Action,
         when Aborted            => Preserve_Failure,
         when Needs_Intervention => Escalate);

   function Is_Terminal (State : Journal_State) return Boolean is
     (State in Committed | Aborted | Needs_Intervention);

   function Allowed (From_State, To_State : Journal_State) return Boolean is
   begin
      if From_State = To_State then
         return True;
      elsif Is_Terminal (From_State) then
         return False;
      end if;

      case From_State is
         when Prepared =>
            return To_State in Invoking | Aborted | Needs_Intervention;
         when Invoking =>
            return To_State in Reconciling | Aborted | Needs_Intervention;
         when Reconciling =>
            return To_State in Committed | Aborted | Needs_Intervention;
         when Committed | Aborted | Needs_Intervention =>
            return False;
      end case;
   end Allowed;
end Quality_Manager.Journal;
