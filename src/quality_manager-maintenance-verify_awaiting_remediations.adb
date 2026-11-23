separate (Quality_Manager.Maintenance)
procedure Verify_Awaiting_Remediations
  (Item             : in out Context;
   Project_Selector : String;
   Result           : out Operation_Result) is
   Values   : Quality_Manager.Storage.Entity_Vectors.Vector;
   Work     : Quality_Manager.Storage.Schema.Work_Item;
   Mapping  : Quality_Manager.Storage.Schema.Dispatch;
   Native   : Quality_Manager.Integrations.Runner.Task_Snapshot;
   Response : Quality_Manager.Integrations.JSON_CLI.Response;
   Plan     : Assessment_Plan;
   Decision : Quality_Manager.Verification.Verification_Decision;
   Request  : Quality_Manager.Verification.Remediation_Request;
   Local    : Operation_Result;
   Execution_Operation : Quality_Manager.Identities.Operation_Id;
   procedure Stop_Missing_Baseline is
   begin
      Quality_Manager.Storage.Transition_Work
        (Item.Database.all, To_String (Work.Work_Id), Work.State,
         Quality_Manager.Model.Needs_Intervention,
         "event:" & To_String (Work.Work_Id) & ":verify:baseline-missing",
         "verification baseline is unavailable", "", Result);
   end Stop_Missing_Baseline;

   procedure Load_Native_Evidence is
   begin
      Quality_Manager.Storage.Decoding.Read_Active_Dispatch
        (Item.Database.all, To_String (Work.Global_Remediation), Mapping, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Execution_Operation := Quality_Manager.Identities.Operation_Identity
        ("model-runner-execution", To_String (Mapping.Dispatch_Id));
      Quality_Manager.Integrations.Runner.Status
        (Item.Runner, To_String (Work.Project.Canonical_Path),
         Quality_Manager.Dispatch.Operation_Name (Execution_Operation), Response);
      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Native, Result);
      if Result.Kind /= Success then
         return;
      elsif Native.Operation_Id /= To_Unbounded_String
        (Quality_Manager.Dispatch.Operation_Name (Execution_Operation))
      then
         Result := Make_Result
           (Integrity_Error, "integrated native evidence is incomplete or mismatched",
            "qm.maintenance.native-verification");
      elsif Native.Task_Id /= Mapping.Native_Task_Id then
         Result := Make_Result
           (Integrity_Error, "integrated native evidence is incomplete or mismatched",
            "qm.maintenance.native-verification");
      elsif Native.State /= Quality_Manager.Integrations.Runner.Completed_State then
         Result := Make_Result
           (Integrity_Error, "integrated native evidence is incomplete or mismatched",
            "qm.maintenance.native-verification");
      elsif To_String (Native.Workspace_State) /= "integrated" then
         Result := Make_Result
           (Integrity_Error, "integrated native evidence is incomplete or mismatched",
            "qm.maintenance.native-verification");
      elsif Length (Native.Source_Fingerprint) = 0 then
         Result := Make_Result
           (Integrity_Error, "integrated native evidence is incomplete or mismatched",
            "qm.maintenance.native-verification");
      end if;
   end Load_Native_Evidence;

   procedure Load_Verification_Plan is
   begin
      Quality_Manager.Integrations.Quality.Plan_Check
        (Item.Quality,
         Ada.Strings.Fixed.Trim
           (Positive'Image (Work.Project.Quality_Project_Id), Ada.Strings.Both),
         "", False, Response);
      Decode_Plan (Response, Work.Project, Plan, Result);
      if Result.Kind /= Success then
         return;
      elsif Plan.Source_Fingerprint /= Native.Source_Fingerprint then
         Result := Make_Result
           (Stale_Evidence, "integrated source or policy changed before verification",
            "qm.maintenance.verification-drift");
      elsif Plan.Policy_Fingerprint /= Work.Effective_Policy_Digest then
         Result := Make_Result
           (Stale_Evidence, "integrated source or policy changed before verification",
            "qm.maintenance.verification-drift");
      end if;
   end Load_Verification_Plan;

   procedure Build_Request is
   begin
      Request :=
        (Work_Id => Work.Work_Id,
         Project => Work.Project,
         Project_Selector => To_Unbounded_String
           (Ada.Strings.Fixed.Trim
              (Positive'Image (Work.Project.Quality_Project_Id), Ada.Strings.Both)),
         Profile => Null_Unbounded_String,
         Candidate_Revision => Native.Source_Fingerprint,
         Candidate_Source => Native.Source_Fingerprint,
         Policy_Fingerprint => Plan.Policy_Fingerprint,
         Toolchain_Fingerprint => Plan.Toolchain_Fingerprint,
         Baseline_Assessment => Positive (Work.Baseline_Assessment_Run),
         Improve_Plan_Id => Work.Improve_Plan_Id,
         Improve_Plan_Revision => Positive (Work.Improve_Revision),
         Improve_Task_Id => Work.Improve_Task_Id,
         Contract_Digest => To_Unbounded_String
           (Quality_Manager.Identities.Canonical_Digest
              ([Quality_Manager.Identities.Text_Value (To_String (Mapping.Dispatch_Id)),
                Quality_Manager.Identities.Text_Value (To_String (Native.Source_Fingerprint)),
                Quality_Manager.Identities.Text_Value (To_String (Plan.Policy_Fingerprint)),
                Quality_Manager.Identities.Text_Value (To_String (Plan.Toolchain_Fingerprint)),
                Quality_Manager.Identities.Number_Value
                  (Interfaces.Unsigned_64 (Work.Baseline_Assessment_Run))])),
         Assessment_Operation => Quality_Manager.Identities.Operation_Identity
           ("post-remediation-assessment", To_String (Work.Work_Id)),
         Improve_Operation => Quality_Manager.Identities.Operation_Identity
           ("post-remediation-verification", To_String (Work.Work_Id)),
         Attempts_Used => 1,
         Maximum_Attempts => Item.Maximum_Attempts);
   end Build_Request;

   procedure Verify_Work is
   begin
      Load_Native_Evidence;
      if Result.Kind = Success then
         Load_Verification_Plan;
      end if;
      if Result.Kind = Success then
         Build_Request;
         Quality_Manager.Verification.Verify_Remediation
           (Item.Database.all, Item.Quality, Item.Planner, Native, Request, Decision, Local);
         if Local.Kind not in Success | Negative_Result then
            Result := Local;
         end if;
      end if;
   end Verify_Work;

   procedure Process_Work
     (Stored : Quality_Manager.Storage.Stored_Entity) is
   begin
      Quality_Manager.Storage.Decoding.Read_Work
        (Item.Database.all, To_String (Stored.Entity_Key), Work, Result);
      if Result.Kind /= Success then
         return;
      elsif not Selected
        (Project_Selector, Work.Project.Quality_Project_Id,
         To_String (Work.Project.Canonical_Path))
      then
         return;
      elsif Work.Baseline_Assessment_Run = 0 then
         Stop_Missing_Baseline;
      else
         Verify_Work;
      end if;
   end Process_Work;
begin
   Result := Make_Result (Success);
   Quality_Manager.Storage.List
     (Item.Database.all, Quality_Manager.Storage.Work_Item_Record, Values, 100_000, Result);
   if Result.Kind /= Success then
      return;
   end if;
   for Stored of Values loop
      Renew_Coordinator_Lease (Item, Local);
      if Local.Kind /= Success then
         Result := Local;
         return;
      elsif To_String (Stored.State) = Quality_Manager.Model.Awaiting_Assessment'Image then
         Process_Work (Stored);
         if Result.Kind /= Success then
            return;
         end if;
      end if;
   end loop;
   Result := Make_Result (Success);
exception
   when Constraint_Error =>
      Result := Make_Result
        (Integrity_Error, "persisted verification identity is out of range",
         "qm.maintenance.verification-range");
end Verify_Awaiting_Remediations;

