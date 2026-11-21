with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Quality_Manager.Recovery is
   use type Quality_Manager.Results.Result_Kind;

   procedure Reconstruct
     (Store   : in out Quality_Manager.Storage.Store;
      Maximum : Positive;
      Work    : out Recovery_Vectors.Vector;
      Result  : out Quality_Manager.Results.Operation_Result) is
      Entries : Quality_Manager.Storage.Entity_Vectors.Vector;
   begin
      Work.Clear;
      Quality_Manager.Storage.Recovery_Entries (Store, Entries, Maximum, Result);
      if Result.Kind /= Quality_Manager.Results.Success then
         return;
      end if;
      for Record_Item of Entries loop
         declare
            State : constant Quality_Manager.Journal.Journal_State :=
              Quality_Manager.Journal.Journal_State'Value (To_String (Record_Item.State));
         begin
            Work.Append
              (Recovery_Item'
                 (Operation_Key => Record_Item.Entity_Key,
                  State         => State,
                  Action        => Quality_Manager.Journal.Action_For (State)));
         end;
      end loop;
   exception
      when Constraint_Error =>
         Work.Clear;
         Result := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Incompatible_Contract,
            "unknown journal state during startup reconstruction",
            "qm.recovery.state");
   end Reconstruct;
end Quality_Manager.Recovery;
