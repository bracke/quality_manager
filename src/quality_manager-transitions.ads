with Quality_Manager.Model;
with Quality_Manager.Results;

package Quality_Manager.Transitions is
   function Is_Terminal (State : Quality_Manager.Model.Work_State) return Boolean;

   function Allowed
     (From_State : Quality_Manager.Model.Work_State;
      To_State   : Quality_Manager.Model.Work_State) return Boolean;

   function Validate
     (From_State : Quality_Manager.Model.Work_State;
      To_State   : Quality_Manager.Model.Work_State) return Quality_Manager.Results.Operation_Result;
end Quality_Manager.Transitions;
