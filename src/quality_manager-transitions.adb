with Quality_Manager.Results; use Quality_Manager.Results;

package body Quality_Manager.Transitions is
   use Quality_Manager.Model;

   function Is_Terminal (State : Work_State) return Boolean is
     (State in Verified | Failed | Cancelled | Superseded);

   function Allowed (From_State : Work_State; To_State : Work_State) return Boolean is
   begin
      if From_State = To_State then
         return True;
      elsif Is_Terminal (From_State) then
         return False;
      end if;

      case From_State is
         when Discovered =>
            return To_State in Planning | Blocked | Failed | Cancelled | Superseded | Needs_Intervention;
         when Planning =>
            return To_State in Awaiting_Approval | Publishable | Blocked | Failed | Cancelled | Superseded
              | Needs_Intervention;
         when Awaiting_Approval =>
            return To_State in Publishable | Blocked | Cancelled | Superseded | Needs_Intervention;
         when Publishable =>
            return To_State in Publishing | Blocked | Cancelled | Superseded | Needs_Intervention;
         when Publishing =>
            return To_State in Published | Blocked | Failed | Inconclusive | Needs_Intervention;
         when Published =>
            return To_State in Queued | Blocked | Cancelled | Superseded | Needs_Intervention;
         when Queued =>
            return To_State in Executing | Blocked | Cancelled | Superseded | Needs_Intervention;
         when Executing =>
            return To_State in Awaiting_Integration | Blocked | Failed | Cancelled | Inconclusive
              | Needs_Intervention;
         when Awaiting_Integration =>
            return To_State in Awaiting_Assessment | Blocked | Failed | Cancelled | Inconclusive
              | Needs_Intervention;
         when Awaiting_Assessment =>
            return To_State in Verifying | Blocked | Failed | Inconclusive | Needs_Intervention;
         when Verifying =>
            return To_State in Verified | Planning | Blocked | Failed | Inconclusive | Needs_Intervention;
         when Blocked =>
            return To_State in Planning | Awaiting_Approval | Publishable | Queued | Executing | Awaiting_Integration
              | Awaiting_Assessment | Verifying | Cancelled | Superseded | Needs_Intervention;
         when Inconclusive =>
            return To_State in Planning | Awaiting_Assessment | Verifying | Blocked | Failed | Cancelled
              | Needs_Intervention;
         when Needs_Intervention =>
            return To_State in Planning | Awaiting_Approval | Publishable | Queued | Awaiting_Integration
              | Awaiting_Assessment | Verifying | Blocked | Failed | Cancelled | Superseded;
         when Verified | Failed | Cancelled | Superseded =>
            return False;
      end case;
   end Allowed;

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
