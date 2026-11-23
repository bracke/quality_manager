separate (Quality_Manager.Dispatch)
procedure Execute_Or_Reconcile
  (Store                     : in out Quality_Manager.Storage.Store;
   Runner                    : Quality_Manager.Integrations.Runner.Adapter;
   Operation                 : Quality_Manager.Identities.Operation_Id;
   Dispatch_Id               : String;
   Project_Resource          : String;
   Lease_Owner               : String;
   Expected_Lease_Generation : Interfaces.Unsigned_64;
   New_Lease_Generation      : Interfaces.Unsigned_64;
   Lease_Expires_At          : Interfaces.Unsigned_64;
   Request                   : Quality_Manager.Integrations.Runner.Execution_Request;
   Snapshot                  : out Quality_Manager.Integrations.Runner.Task_Snapshot;
   Result                    : out Operation_Result) is
   Journal_Item : Quality_Manager.Storage.Stored_Entity;
   State       : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
   Response    : Quality_Manager.Integrations.JSON_CLI.Response;
   Checked     : Operation_Result;
   External_Id : constant String := Operation_Name (Operation);
   Intent      : constant String := Intent_For (Dispatch_Id, Request);
   procedure Validate_Request is
   begin
      if Operation = 0 then
         Result := Make_Result
           (Invalid_Request, "execution coordination identity is incomplete", "qm.dispatch.identity");
      elsif Dispatch_Id = "" then
         Result := Make_Result
           (Invalid_Request, "execution coordination identity is incomplete", "qm.dispatch.identity");
      elsif Project_Resource = "" then
         Result := Make_Result
           (Invalid_Request, "execution coordination identity is incomplete", "qm.dispatch.identity");
      elsif Lease_Owner = "" then
         Result := Make_Result
           (Invalid_Request, "execution coordination identity is incomplete", "qm.dispatch.identity");
      elsif To_String (Request.Operation_Id) /= External_Id then
         Result := Make_Result
           (Invalid_Request, "external operation identity does not match journal identity",
            "qm.dispatch.operation");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Request;

   procedure Prepare_Journal is
   begin
      Read_Journal (Store, Operation, Journal_Item, State, Result);
      if Result.Kind = Success then
         if not Has_Exact_Intent (Journal_Item, Intent, External_Id) then
            Result := Make_Result
              (Integrity_Error, "operation identity is bound to different execution intent",
               "qm.dispatch.intent");
         end if;
      elsif Result.Kind = Not_Found then
         Quality_Manager.Storage.Acquire_Lease
           (Store, Project_Resource, Lease_Owner, Expected_Lease_Generation,
            New_Lease_Generation, Lease_Expires_At, Result);
         if Result.Kind = Success then
            Quality_Manager.Storage.Prepare_Operation
              (Store, Operation, "model-runner-execution", Intent, External_Id, Result);
         end if;
         if Result.Kind = Success then
            State := Quality_Manager.Journal.Prepared;
         end if;
      end if;
   end Prepare_Journal;

   procedure Invoke_Operation is
   begin
      if State = Quality_Manager.Journal.Aborted then
         Result := Make_Result (Negative_Result, "native operation was aborted", "qm.dispatch.aborted");
      elsif State = Quality_Manager.Journal.Needs_Intervention then
         Result := Make_Result
           (Authorization_Required, "native operation requires intervention", "qm.dispatch.intervention");
      elsif State = Quality_Manager.Journal.Committed then
         Quality_Manager.Integrations.Runner.Status
           (Runner, To_String (Request.Project_Path), External_Id, Response);
      elsif State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
            External_Id, "", Result);
         if Result.Kind = Success then
            State := Quality_Manager.Journal.Invoking;
            Quality_Manager.Integrations.Runner.Execute (Runner, Request, Response);
         end if;
      elsif State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Integrations.Runner.Status
           (Runner, To_String (Request.Project_Path), External_Id, Response);
         if Response.Status.Kind = Not_Found then
            Quality_Manager.Integrations.Runner.Execute (Runner, Request, Response);
         end if;
      else
         Quality_Manager.Integrations.Runner.Status
           (Runner, To_String (Request.Project_Path), External_Id, Response);
      end if;
   end Invoke_Operation;

   procedure Validate_Response is
   begin
      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Checked);
      if Checked.Kind /= Success then
         if Checked.Kind in Authorization_Required | Integrity_Error |
                            Incompatible_Contract | Stale_Evidence
         then
            Mark_Intervention (Store, Operation, State, External_Id, Message (Checked));
         end if;
         Result := Checked;
         return;
      end if;
      Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
      if Checked.Kind /= Success then
         Mark_Intervention (Store, Operation, State, External_Id, Message (Checked));
         Result := Checked;
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Response;

   procedure Commit_Observation is
   begin
      if Snapshot.State = Quality_Manager.Integrations.Runner.Executing_State then
         Result := Make_Result (Not_Ready, "native execution is still running", "qm.dispatch.executing");
         return;
      end if;
      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
            External_Id, To_String (Snapshot.Audit_Reference), Result);
         if Result.Kind = Success then
            State := Quality_Manager.Journal.Reconciling;
         end if;
      end if;
      if Result.Kind = Success and then State = Quality_Manager.Journal.Reconciling then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, Quality_Manager.Journal.Reconciling, Quality_Manager.Journal.Committed,
            External_Id, To_String (Snapshot.Native_Result), Result);
      end if;
   end Commit_Observation;

   procedure Set_Final_Result is
   begin
      case Snapshot.State is
         when Quality_Manager.Integrations.Runner.Awaiting_Integration_State |
              Quality_Manager.Integrations.Runner.Verifying_State |
              Quality_Manager.Integrations.Runner.Completed_State =>
            Result := Make_Result (Success);
         when Quality_Manager.Integrations.Runner.Cancelled_State =>
            Result := Make_Result (Interrupted, "native execution was cancelled", "qm.dispatch.cancelled");
         when others =>
            Result := Make_Result (Negative_Result, "native execution did not complete", "qm.dispatch.negative");
      end case;
   end Set_Final_Result;
begin
   Snapshot := (others => <>);
   Validate_Request;
   if Result.Kind /= Success then
      return;
   end if;
   Prepare_Journal;
   if Result.Kind /= Success then
      return;
   end if;
   Invoke_Operation;
   if Result.Kind /= Success then
      return;
   end if;
   Validate_Response;
   if Result.Kind /= Success then
      return;
   end if;
   Commit_Observation;
   if Result.Kind /= Success then
      return;
   end if;
   Complete_Attempt (Store, Operation, Dispatch_Id, Request, Snapshot, Result);
   if Result.Kind = Success then
      Set_Final_Result;
   end if;
end Execute_Or_Reconcile;

