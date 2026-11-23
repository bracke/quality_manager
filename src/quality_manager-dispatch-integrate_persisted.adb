separate (Quality_Manager.Dispatch)
procedure Integrate_Persisted
  (Store            : in out Quality_Manager.Storage.Store;
   Runner           : Quality_Manager.Integrations.Runner.Adapter;
   Work_Id          : String;
   Lease_Owner      : String;
   Now              : Interfaces.Unsigned_64;
   Lease_Expires_At : Interfaces.Unsigned_64;
   Snapshot         : out Quality_Manager.Integrations.Runner.Task_Snapshot;
   Result           : out Operation_Result) is
   Work        : Quality_Manager.Storage.Schema.Work_Item;
   Mapping     : Quality_Manager.Storage.Schema.Dispatch;
   Execution   : Quality_Manager.Integrations.Runner.Task_Snapshot;
   Response    : Quality_Manager.Integrations.JSON_CLI.Response;
   Execution_Operation : Quality_Manager.Identities.Operation_Id;
   Journal_Operation   : Quality_Manager.Identities.Operation_Id;
   Request     : Quality_Manager.Integrations.Runner.Execution_Request;
   Lease       : Quality_Manager.Storage.Stored_Entity;
   Expected    : Interfaces.Unsigned_64 := 0;
   Resource    : Unbounded_String;

   function Lease_Available return Boolean is
      Expires : Interfaces.Unsigned_64;
   begin
      Quality_Manager.Storage.Read
        (Store, "lease:" & To_String (Resource), Lease, Result);
      if Result.Kind = Not_Found then
         Result := Make_Result (Success);
         Expected := 0;
         return True;
      elsif Result.Kind /= Success then
         return False;
      elsif Lease.Kind /= Quality_Manager.Storage.Lease_Record then
         Result := Make_Result
           (Integrity_Error, "project integration lease has the wrong record kind",
            "qm.integration.lease-kind");
         return False;
      end if;
      Expected := Lease.Generation;
      Expires := Interfaces.Unsigned_64'Value
        (Ada.Strings.Fixed.Trim (To_String (Lease.Payload), Ada.Strings.Both));
      if To_String (Lease.State) /= Lease_Owner and then Expires > Now then
         Result := Make_Result
           (Not_Ready, "another coordinator owns the project integration lease",
            "qm.integration.lease-owned");
         return False;
      end if;
      Result := Make_Result (Success);
      return True;
   exception
      when Constraint_Error =>
         Result := Make_Result
           (Integrity_Error, "project integration lease is malformed", "qm.integration.lease-value");
         return False;
   end Lease_Available;
   procedure Validate_Coordination is
   begin
      if Work_Id = "" then
         Result := Make_Result
           (Invalid_Request, "persisted integration coordination is incomplete",
            "qm.integration.persisted-identity");
      elsif Lease_Owner = "" then
         Result := Make_Result
           (Invalid_Request, "persisted integration coordination is incomplete",
            "qm.integration.persisted-identity");
      elsif Lease_Expires_At <= Now then
         Result := Make_Result
           (Invalid_Request, "persisted integration coordination is incomplete",
            "qm.integration.persisted-identity");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Coordination;

   procedure Load_Work is
   begin
      Quality_Manager.Storage.Decoding.Read_Work (Store, Work_Id, Work, Result);
      if Result.Kind = Success
        and then Work.State /= Quality_Manager.Model.Awaiting_Integration
      then
         Result := Make_Result
           (Not_Ready, "persisted remediation is not awaiting integration",
            "qm.integration.persisted-state");
      end if;
   end Load_Work;

   procedure Load_Mapping is
   begin
      Quality_Manager.Storage.Decoding.Read_Active_Dispatch
        (Store, To_String (Work.Global_Remediation), Mapping, Result);
      if Result.Kind /= Success then
         return;
      elsif Mapping.Work_Id /= Work.Work_Id then
         Result := Make_Result
           (Integrity_Error, "integration dispatch does not match persisted remediation",
            "qm.integration.mapping-drift");
      elsif Mapping.Improve_Task.Plan_Id /= Work.Improve_Plan_Id then
         Result := Make_Result
           (Integrity_Error, "integration dispatch does not match persisted remediation",
            "qm.integration.mapping-drift");
      elsif Natural (Mapping.Improve_Task.Revision) /= Work.Improve_Revision then
         Result := Make_Result
           (Integrity_Error, "integration dispatch does not match persisted remediation",
            "qm.integration.mapping-drift");
      elsif Mapping.Improve_Task.Task_Id /= Work.Improve_Task_Id then
         Result := Make_Result
           (Integrity_Error, "integration dispatch does not match persisted remediation",
            "qm.integration.mapping-drift");
      end if;
   end Load_Mapping;

   function Workspace_Ready return Boolean is
   begin
      if Execution.State = Quality_Manager.Integrations.Runner.Awaiting_Integration_State then
         return To_String (Execution.Workspace_State) = "active";
      elsif Execution.State in Quality_Manager.Integrations.Runner.Verifying_State |
                               Quality_Manager.Integrations.Runner.Completed_State
      then
         return To_String (Execution.Workspace_State) = "integrated";
      else
         return False;
      end if;
   end Workspace_Ready;

   procedure Read_Execution is
   begin
      Execution_Operation := Quality_Manager.Identities.Operation_Identity
        ("model-runner-execution", To_String (Mapping.Dispatch_Id));
      Quality_Manager.Integrations.Runner.Status
        (Runner, To_String (Work.Project.Canonical_Path), Operation_Name (Execution_Operation), Response);
      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Execution, Result);
      if Result.Kind /= Success then
         return;
      elsif Execution.Operation_Id /= To_Unbounded_String (Operation_Name (Execution_Operation)) then
         Result := Make_Result
           (Integrity_Error, "native execution provenance changed before integration",
            "qm.integration.execution-drift");
      elsif Execution.Task_Id /= Mapping.Native_Task_Id then
         Result := Make_Result
           (Integrity_Error, "native execution provenance changed before integration",
            "qm.integration.execution-drift");
      elsif To_String (Execution.Workspace_State) /= "integrated"
        and then Execution.Source_Fingerprint /= Work.Planned_Source_Fingerprint
      then
         Result := Make_Result
           (Stale_Evidence, "native execution source no longer matches its plan",
            "qm.integration.source-drift");
      elsif not Workspace_Ready then
         Result := Make_Result
           (Not_Ready, "native execution has no recoverable workspace integration state",
            "qm.integration.workspace-not-ready");
      end if;
   end Read_Execution;

   procedure Prepare_Integration is
   begin
      Request :=
        (Project_Path => Work.Project.Canonical_Path,
         Task_Id => Mapping.Native_Task_Id,
         Operation_Id => To_Unbounded_String (Operation_Name (Execution_Operation)),
         Expected_Task_Revision => Execution.Task_Revision,
         Expected_Project_Identity => Execution.Project_Identity,
         Expected_Source_Fingerprint => Work.Planned_Source_Fingerprint,
         Execution_Policy => Execution.Execution_Policy,
         Timeout_Seconds => 3_600);
      Journal_Operation := Quality_Manager.Identities.Operation_Identity
        ("model-runner-integration", To_String (Mapping.Dispatch_Id));
      Resource := To_Unbounded_String
        ("project-integration:"
         & Quality_Manager.Identities.Canonical_Digest
             ([Quality_Manager.Identities.Text_Value
                 (To_String (Work.Project.Quality_Database_Id)),
               Quality_Manager.Identities.Number_Value
                 (Interfaces.Unsigned_64 (Work.Project.Quality_Project_Id)),
               Quality_Manager.Identities.Text_Value
                 (To_String (Work.Project.Canonical_Path))]));
      if not Lease_Available then
         return;
      elsif Expected = Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) then
         Result := Make_Result
           (Integrity_Error, "project integration lease generation is exhausted",
            "qm.integration.lease-generation");
      end if;
   end Prepare_Integration;

   procedure Finish_Integration is
   begin
      if Result.Kind /= Success then
         return;
      elsif Length (Snapshot.Source_Fingerprint) = 0 then
         Result := Make_Result
           (Integrity_Error, "native integration returned incomplete source evidence",
            "qm.integration.result");
      elsif To_String (Snapshot.Workspace_State) /= "integrated" then
         Result := Make_Result
           (Integrity_Error, "native integration returned incomplete source evidence",
            "qm.integration.result");
      else
         Quality_Manager.Storage.Transition_Work
           (Store, Work_Id, Quality_Manager.Model.Awaiting_Integration,
            Quality_Manager.Model.Awaiting_Assessment,
            "event:" & Work_Id & ":native:integrated",
            "model_runner integrated the isolated workspace",
            To_String (Snapshot.Source_Fingerprint), Result);
      end if;
   end Finish_Integration;
begin
   Snapshot := (others => <>);
   Validate_Coordination;
   if Result.Kind /= Success then
      return;
   end if;
   Load_Work;
   if Result.Kind /= Success then
      return;
   end if;
   Load_Mapping;
   if Result.Kind /= Success then
      return;
   end if;
   Read_Execution;
   if Result.Kind /= Success then
      return;
   end if;
   Prepare_Integration;
   if Result.Kind /= Success then
      return;
   end if;
   Integrate_Or_Reconcile
     (Store, Runner, Journal_Operation, To_String (Resource), Lease_Owner,
      Expected, Expected + 1, Lease_Expires_At, Request, Snapshot, Result);
   Finish_Integration;
exception
   when Constraint_Error =>
      Snapshot := (others => <>);
      Result := Make_Result
        (Integrity_Error, "persisted integration identity is out of range",
         "qm.integration.persisted-range");
end Integrate_Persisted;

