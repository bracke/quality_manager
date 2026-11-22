with Quality_Manager.Results; use Quality_Manager.Results;

package body Quality_Manager.Transitions is
   use Quality_Manager.Model;

   type Transition_Matrix is array (Work_State, Work_State) of Boolean;

   Allowed_Transitions : constant Transition_Matrix :=
     [Discovered =>
        [Planning | Blocked | Failed | Cancelled | Superseded | Needs_Intervention => True,
         others => False],
      Planning =>
        [Awaiting_Approval | Publishable | Blocked | Failed | Cancelled | Superseded | Needs_Intervention => True,
         others => False],
      Awaiting_Approval =>
        [Publishable | Blocked | Cancelled | Superseded | Needs_Intervention => True,
         others => False],
      Publishable =>
        [Publishing | Blocked | Cancelled | Superseded | Needs_Intervention => True,
         others => False],
      Publishing =>
        [Published | Blocked | Failed | Inconclusive | Needs_Intervention => True,
         others => False],
      Published =>
        [Queued | Blocked | Cancelled | Superseded | Needs_Intervention => True,
         others => False],
      Queued =>
        [Executing | Blocked | Cancelled | Superseded | Needs_Intervention => True,
         others => False],
      Executing =>
        [Awaiting_Integration | Blocked | Failed | Cancelled | Inconclusive | Needs_Intervention => True,
         others => False],
      Awaiting_Integration =>
        [Awaiting_Assessment | Blocked | Failed | Cancelled | Inconclusive | Needs_Intervention => True,
         others => False],
      Awaiting_Assessment =>
        [Verifying | Blocked | Failed | Inconclusive | Needs_Intervention => True,
         others => False],
      Verifying =>
        [Verified | Planning | Blocked | Failed | Inconclusive | Needs_Intervention => True,
         others => False],
      Blocked =>
        [Planning | Awaiting_Approval | Publishable | Queued | Executing | Awaiting_Integration |
         Awaiting_Assessment | Verifying | Cancelled | Superseded | Needs_Intervention => True,
         others => False],
      Inconclusive =>
        [Planning | Awaiting_Assessment | Verifying | Blocked | Failed | Cancelled | Needs_Intervention => True,
         others => False],
      Needs_Intervention =>
        [Planning | Awaiting_Approval | Publishable | Queued | Awaiting_Integration | Awaiting_Assessment |
         Verifying | Blocked | Failed | Cancelled | Superseded => True,
         others => False],
      Verified | Failed | Cancelled | Superseded => [others => False]];

   function Is_Terminal (State : Work_State) return Boolean is
     (State in Verified | Failed | Cancelled | Superseded);

   function Allowed (From_State : Work_State; To_State : Work_State) return Boolean is
     (From_State = To_State or else Allowed_Transitions (From_State, To_State));

   function Validate (From_State : Work_State; To_State : Work_State) return Operation_Result is
   begin
      if Allowed (From_State, To_State) then
         return Make_Result (Success);
      elsif Is_Terminal (From_State) then
         return Make_Result
           (Invalid_Request,
            "terminal work state cannot be reopened",
            "qm.transition.terminal");
      else
         return Make_Result
           (Invalid_Request,
            "work state transition is not permitted",
            "qm.transition.invalid");
      end if;
   end Validate;
end Quality_Manager.Transitions;
