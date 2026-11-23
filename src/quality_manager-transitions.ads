with Quality_Manager.Model;
with Quality_Manager.Results;

--  Validates coordinator work-state transitions.
package Quality_Manager.Transitions is
   --  Public contract for this Quality Manager unit.
   function Is_Terminal (State : Quality_Manager.Model.Work_State) return Boolean;
   --  Return Is Terminal.
   --  @param State State.
   --  @return Is Terminal result.

   function Allowed
     (From_State : Quality_Manager.Model.Work_State;
      To_State   : Quality_Manager.Model.Work_State) return Boolean;
   --  Return Allowed.
   --  @param From_State From State.
   --  @param To_State To State.
   --  @return Allowed result.

   function Validate
     (From_State : Quality_Manager.Model.Work_State;
      To_State   : Quality_Manager.Model.Work_State) return Quality_Manager.Results.Operation_Result;
   --  Return Validate.
   --  @param From_State From State.
   --  @param To_State To State.
   --  @return Validate result.
end Quality_Manager.Transitions;
