separate (Quality_Manager.Dispatch)
procedure Execute_Persisted
  (Store            : in out Quality_Manager.Storage.Store;
   Runner           : Quality_Manager.Integrations.Runner.Adapter;
   Work_Id          : String;
   Lease_Owner      : String;
   Now              : Interfaces.Unsigned_64;
   Lease_Expires_At : Interfaces.Unsigned_64;
   Timeout_Seconds  : Positive;
   Snapshot         : out Quality_Manager.Integrations.Runner.Task_Snapshot;
   Result           : out Operation_Result;
   Maximum_Attempts : Positive := 1) is
   Work       : Quality_Manager.Storage.Schema.Work_Item;
   Mapping    : Quality_Manager.Storage.Schema.Dispatch;
   Inspected  : Quality_Manager.Integrations.Runner.Task_Snapshot;
   Response   : Quality_Manager.Integrations.JSON_CLI.Response;
   Operation  : Quality_Manager.Identities.Operation_Id;
   Request    : Quality_Manager.Integrations.Runner.Execution_Request;
   Lease      : Quality_Manager.Storage.Stored_Entity;
   Expected   : Interfaces.Unsigned_64 := 0;
   Resource   : Unbounded_String;
   Current    : Quality_Manager.Model.Work_State;
   Attempt_Number : Positive := 1;

   procedure Move_To
     (Target : Quality_Manager.Model.Work_State;
      Phase  : String;
      Cause  : String;
      Evidence : String := "") is
   begin
      if Current = Target then
         Result := Make_Result (Success);
         return;
      end if;
      Quality_Manager.Storage.Transition_Work
        (Store, Work_Id, Current, Target,
         "event:" & Work_Id & ":native:attempt-"
         & Ada.Strings.Fixed.Trim (Positive'Image (Attempt_Number), Ada.Strings.Both)
         & ":" & Phase,
         Cause, Evidence, Result);
      if Result.Kind = Success then
         Current := Target;
      end if;
   end Move_To;

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
           (Integrity_Error, "project execution lease has the wrong record kind", "qm.dispatch.lease-kind");
         return False;
      end if;
      Expected := Lease.Generation;
      Expires := Interfaces.Unsigned_64'Value
        (Ada.Strings.Fixed.Trim (To_String (Lease.Payload), Ada.Strings.Both));
      if To_String (Lease.State) /= Lease_Owner and then Expires > Now then
         Result := Make_Result
           (Not_Ready, "another coordinator owns the project execution lease", "qm.dispatch.lease-owned");
         return False;
      end if;
      Result := Make_Result (Success);
      return True;
   exception
      when Constraint_Error =>
         Result := Make_Result
           (Integrity_Error, "project execution lease is malformed", "qm.dispatch.lease-value");
         return False;
   end Lease_Available;
   procedure Validate_Coordination is
   begin
      if Work_Id = "" then
         Result := Make_Result
           (Invalid_Request, "persisted execution coordination is incomplete",
            "qm.dispatch.persisted-identity");
      elsif Lease_Owner = "" then
         Result := Make_Result
           (Invalid_Request, "persisted execution coordination is incomplete",
            "qm.dispatch.persisted-identity");
      elsif Lease_Expires_At <= Now then
         Result := Make_Result
           (Invalid_Request, "persisted execution coordination is incomplete",
            "qm.dispatch.persisted-identity");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Coordination;

   procedure Load_Work is
   begin
      Quality_Manager.Storage.Decoding.Read_Work (Store, Work_Id, Work, Result);
      if Result.Kind /= Success then
         return;
      elsif Work.State not in Quality_Manager.Model.Queued | Quality_Manager.Model.Executing then
         Result := Make_Result
           (Not_Ready, "persisted remediation is not executable", "qm.dispatch.persisted-state");
      elsif Length (Work.Planned_Source_Fingerprint) = 0 then
         Result := Make_Result
           (Stale_Evidence, "remediation has no assessed source fingerprint", "qm.dispatch.source-missing");
      else
         Current := Work.State;
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
           (Integrity_Error, "published dispatch does not match persisted remediation",
            "qm.dispatch.mapping-drift");
      elsif Mapping.Improve_Task.Plan_Id /= Work.Improve_Plan_Id then
         Result := Make_Result
           (Integrity_Error, "published dispatch does not match persisted remediation",
            "qm.dispatch.mapping-drift");
      elsif Natural (Mapping.Improve_Task.Revision) /= Work.Improve_Revision then
         Result := Make_Result
           (Integrity_Error, "published dispatch does not match persisted remediation",
            "qm.dispatch.mapping-drift");
      elsif Mapping.Improve_Task.Task_Id /= Work.Improve_Task_Id then
         Result := Make_Result
           (Integrity_Error, "published dispatch does not match persisted remediation",
            "qm.dispatch.mapping-drift");
      end if;
   end Load_Mapping;

   procedure Inspect_Native is
   begin
      Quality_Manager.Integrations.Runner.Inspect
        (Runner, To_String (Work.Project.Canonical_Path), To_String (Mapping.Native_Task_Id), Response);
      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Inspected, Result);
      if Result.Kind /= Success then
         return;
      elsif Inspected.Task_Id /= Mapping.Native_Task_Id then
         Result := Make_Result
           (Integrity_Error, "inspected native task does not match publication", "qm.dispatch.native-task");
      elsif Inspected.Source_Fingerprint /= Work.Planned_Source_Fingerprint then
         Result := Make_Result
           (Stale_Evidence, "native project source changed after planning", "qm.dispatch.source-drift");
      elsif Length (Inspected.Task_Revision) = 0 then
         Result := Make_Result
           (Incompatible_Contract, "native inspection lacks execution identity", "qm.dispatch.inspect-identity");
      elsif Length (Inspected.Project_Identity) = 0 then
         Result := Make_Result
           (Incompatible_Contract, "native inspection lacks execution identity", "qm.dispatch.inspect-identity");
      elsif Length (Inspected.Execution_Policy) = 0 then
         Result := Make_Result
           (Incompatible_Contract, "native inspection lacks execution identity", "qm.dispatch.inspect-identity");
      elsif Current in Quality_Manager.Model.Published | Quality_Manager.Model.Queued
        and then not Inspected.Ready
      then
         Result := Make_Result
           (Not_Ready, "published native task is not ready", "qm.dispatch.native-not-ready");
      elsif Current in Quality_Manager.Model.Published | Quality_Manager.Model.Queued
        and then Inspected.State /= Quality_Manager.Integrations.Runner.Ready_State
      then
         Result := Make_Result
           (Not_Ready, "published native task is not ready", "qm.dispatch.native-not-ready");
      end if;
   end Inspect_Native;

   procedure Prepare_Request is
   begin
      Next_Execution_Attempt
        (Store, To_String (Mapping.Dispatch_Id), Attempt_Number, Operation, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Resource := To_Unbounded_String
        ("project-execution:"
         & Quality_Manager.Identities.Canonical_Digest
             ([Quality_Manager.Identities.Text_Value
                 (To_String (Work.Project.Quality_Database_Id)),
               Quality_Manager.Identities.Number_Value
                 (Interfaces.Unsigned_64 (Work.Project.Quality_Project_Id)),
               Quality_Manager.Identities.Text_Value
                 (To_String (Work.Project.Canonical_Path))]));
      Request :=
        (Project_Path => Work.Project.Canonical_Path,
         Task_Id => Mapping.Native_Task_Id,
         Operation_Id => To_Unbounded_String (Operation_Name (Operation)),
         Expected_Task_Revision => Inspected.Task_Revision,
         Expected_Project_Identity => Inspected.Project_Identity,
         Expected_Source_Fingerprint => Work.Planned_Source_Fingerprint,
         Execution_Policy => Inspected.Execution_Policy,
         Timeout_Seconds => Timeout_Seconds);
      if not Lease_Available then
         return;
      elsif Expected = Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) then
         Result := Make_Result
           (Integrity_Error, "project execution lease generation is exhausted",
            "qm.dispatch.lease-generation");
      end if;
   end Prepare_Request;

   procedure Start_Execution is
   begin
      if Current = Quality_Manager.Model.Queued then
         Move_To
           (Quality_Manager.Model.Executing, "executing", "native task execution prepared",
            To_String (Mapping.Dispatch_Id));
      end if;
      if Result.Kind = Success then
         Execute_Or_Reconcile
           (Store, Runner, Operation, To_String (Mapping.Dispatch_Id), To_String (Resource), Lease_Owner,
            Expected, Expected + 1, Lease_Expires_At, Request, Snapshot, Result);
      end if;
   end Start_Execution;

   procedure Apply_Success is
      Target : constant Quality_Manager.Model.Work_State := Coordinator_State (Snapshot.State);
   begin
      if Target = Quality_Manager.Model.Awaiting_Integration then
         Move_To
           (Target, "awaiting-integration", "native execution completed in isolated workspace",
            To_String (Snapshot.Audit_Reference));
      elsif Target = Quality_Manager.Model.Awaiting_Assessment
        and then To_String (Snapshot.Workspace_State) = "integrated"
      then
         Move_To
           (Quality_Manager.Model.Awaiting_Integration, "integration-observed",
            "native execution reports integrated workspace", To_String (Snapshot.Audit_Reference));
         if Result.Kind = Success then
            Move_To
              (Quality_Manager.Model.Awaiting_Assessment, "awaiting-assessment",
               "integrated native work awaits independent assessment",
               To_String (Snapshot.Source_Fingerprint));
         end if;
      else
         Result := Make_Result
           (Incompatible_Contract, "native execution completed in an invalid coordinator state",
            "qm.dispatch.native-state");
      end if;
   end Apply_Success;

   procedure Apply_Failure
     (Target : Quality_Manager.Model.Work_State;
      Phase  : String;
      Cause  : String) is
      Failure : constant Operation_Result := Result;
   begin
      Move_To (Target, Phase, Cause);
      if Result.Kind = Success then
         Result := Failure;
      end if;
   end Apply_Failure;

   procedure Apply_Execution_Result is
   begin
      if Result.Kind = Not_Ready then
         return;
      elsif Result.Kind = Success then
         Apply_Success;
      elsif Snapshot.State = Quality_Manager.Integrations.Runner.Cancelled_State then
         Apply_Failure
           (Quality_Manager.Model.Cancelled, "cancelled", "native execution was cancelled");
      elsif Snapshot.State = Quality_Manager.Integrations.Runner.Failed_State then
         Apply_Failure
           ((if Attempt_Number < Maximum_Attempts
             then Quality_Manager.Model.Queued else Quality_Manager.Model.Failed),
            (if Attempt_Number < Maximum_Attempts then "retry-queued" else "failed"),
            (if Attempt_Number < Maximum_Attempts
             then "native execution failed; bounded retry queued"
             else "native execution failed; attempt budget exhausted"));
      end if;
   end Apply_Execution_Result;
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
   Inspect_Native;
   if Result.Kind /= Success then
      return;
   end if;
   Prepare_Request;
   if Result.Kind /= Success then
      return;
   end if;
   Start_Execution;
   Apply_Execution_Result;
exception
   when Constraint_Error =>
      Snapshot := (others => <>);
      Result := Make_Result
        (Integrity_Error, "persisted execution identity is out of range", "qm.dispatch.persisted-range");
end Execute_Persisted;

