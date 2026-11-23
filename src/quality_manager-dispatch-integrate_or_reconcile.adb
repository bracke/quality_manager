separate (Quality_Manager.Dispatch)
procedure Integrate_Or_Reconcile
  (Store                     : in out Quality_Manager.Storage.Store;
   Runner                    : Quality_Manager.Integrations.Runner.Adapter;
   Journal_Operation         : Quality_Manager.Identities.Operation_Id;
   Project_Resource          : String;
   Lease_Owner               : String;
   Expected_Lease_Generation : Interfaces.Unsigned_64;
   New_Lease_Generation      : Interfaces.Unsigned_64;
   Lease_Expires_At          : Interfaces.Unsigned_64;
   Request                   : Quality_Manager.Integrations.Runner.Execution_Request;
   Snapshot                  : out Quality_Manager.Integrations.Runner.Task_Snapshot;
   Result                    : out Operation_Result) is
   Journal_Item : Quality_Manager.Storage.Stored_Entity;
   State        : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
   Response     : Quality_Manager.Integrations.JSON_CLI.Response;
   Recovered    : Quality_Manager.Integrations.JSON_CLI.Response;
   Checked      : Operation_Result;
   External_Id  : constant String := To_String (Request.Operation_Id);
   Intent       : constant String := Integration_Intent (Request);
   procedure Validate_Request is
   begin
      if Journal_Operation = 0 then
         Result := Make_Result
           (Invalid_Request, "integration coordination identity is incomplete", "qm.integration.identity");
      elsif Project_Resource = "" then
         Result := Make_Result
           (Invalid_Request, "integration coordination identity is incomplete", "qm.integration.identity");
      elsif Lease_Owner = "" then
         Result := Make_Result
           (Invalid_Request, "integration coordination identity is incomplete", "qm.integration.identity");
      elsif External_Id = "" then
         Result := Make_Result
           (Invalid_Request, "integration coordination identity is incomplete", "qm.integration.identity");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Request;

   procedure Prepare_Journal is
   begin
      Read_Journal (Store, Journal_Operation, Journal_Item, State, Result);
      if Result.Kind = Success then
         if not Has_Exact_Intent (Journal_Item, Intent, External_Id) then
            Result := Make_Result
              (Integrity_Error, "journal identity is bound to another integration", "qm.integration.intent");
         end if;
      elsif Result.Kind = Not_Found then
         Quality_Manager.Storage.Acquire_Lease
           (Store, Project_Resource, Lease_Owner, Expected_Lease_Generation,
            New_Lease_Generation, Lease_Expires_At, Result);
         if Result.Kind = Success then
            Quality_Manager.Storage.Prepare_Operation
              (Store, Journal_Operation, "model-runner-integration", Intent, External_Id, Result);
         end if;
         if Result.Kind = Success then
            State := Quality_Manager.Journal.Prepared;
         end if;
      end if;
   end Prepare_Journal;

   procedure Invoke_Operation is
   begin
      if State = Quality_Manager.Journal.Aborted then
         Result := Make_Result (Negative_Result, "native integration was aborted", "qm.integration.aborted");
      elsif State = Quality_Manager.Journal.Needs_Intervention then
         Result := Make_Result
           (Authorization_Required, "native integration requires intervention", "qm.integration.intervention");
      elsif State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Journal_Operation, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
            External_Id, "", Result);
         if Result.Kind = Success then
            State := Quality_Manager.Journal.Invoking;
            Quality_Manager.Integrations.Runner.Integrate
              (Runner, To_String (Request.Project_Path), External_Id, Response);
         end if;
      else
         if State = Quality_Manager.Journal.Invoking then
            Quality_Manager.Integrations.Runner.Recover
              (Runner, To_String (Request.Project_Path), Recovered);
            if Recovered.Status.Kind /= Success then
               Result := Recovered.Status;
               return;
            end if;
         end if;
         Quality_Manager.Integrations.Runner.Status
           (Runner, To_String (Request.Project_Path), External_Id, Response);
      end if;
   end Invoke_Operation;

   procedure Decode_Response is
   begin
      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Checked);
      if Checked.Kind /= Success then
         if Checked.Kind in Authorization_Required | Integrity_Error |
                            Incompatible_Contract | Stale_Evidence
         then
            Mark_Intervention (Store, Journal_Operation, State, External_Id, Message (Checked));
         end if;
         Result := Checked;
         return;
      end if;
      Validate_Integration (Snapshot, Request, Checked);
      if Checked.Kind /= Success then
         Mark_Intervention (Store, Journal_Operation, State, External_Id, Message (Checked));
         Result := Checked;
      else
         Result := Make_Result (Success);
      end if;
   end Decode_Response;

   procedure Retry_Integration is
   begin
      if State /= Quality_Manager.Journal.Invoking then
         return;
      elsif To_String (Snapshot.Workspace_State) = "integrated" then
         return;
      end if;
      Quality_Manager.Integrations.Runner.Integrate
        (Runner, To_String (Request.Project_Path), External_Id, Response);
      Decode_Response;
   end Retry_Integration;

   procedure Commit_Integration is
   begin
      if To_String (Snapshot.Workspace_State) /= "integrated" then
         Result := Make_Result
           (Not_Ready, "native workspace is not authoritatively integrated", "qm.integration.pending");
         return;
      end if;
      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Storage.Advance_Operation
           (Store, Journal_Operation, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
            External_Id, To_String (Snapshot.Audit_Reference), Result);
         if Result.Kind = Success then
            State := Quality_Manager.Journal.Reconciling;
         end if;
      end if;
      if Result.Kind = Success and then State = Quality_Manager.Journal.Reconciling then
         Quality_Manager.Storage.Advance_Operation
           (Store, Journal_Operation, Quality_Manager.Journal.Reconciling, Quality_Manager.Journal.Committed,
            External_Id, To_String (Snapshot.Source_Fingerprint), Result);
      end if;
   end Commit_Integration;
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
   Decode_Response;
   if Result.Kind /= Success then
      return;
   end if;
   Retry_Integration;
   if Result.Kind /= Success then
      return;
   end if;
   Commit_Integration;
end Integrate_Or_Reconcile;

