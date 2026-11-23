separate (Quality_Manager.Verification)
procedure Verify_Remediation
     (Store       : in out Quality_Manager.Storage.Store;
      Quality     : Quality_Manager.Integrations.Quality.Adapter;
      Planner     : Quality_Manager.Integrations.Improve.Adapter;
      Native      : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Request     : Remediation_Request;
      Decision    : out Verification_Decision;
      Result      : out Operation_Result) is
      Assessment_Result : Assessment_Evidence;
      Regression_Result : Regression_Evidence;
      Improve_Result    : Improve_Evidence;
      Comparison        : Quality_Manager.Integrations.JSON_CLI.Response;
      Context           : Verification_Context;
      Record_Item       : Quality_Manager.Storage.Schema.Verification;
      Target            : Quality_Manager.Model.Work_State;
      Work_Record       : Quality_Manager.Storage.Stored_Entity;
      Current_State     : Quality_Manager.Model.Work_State;

      function Request_Is_Valid return Boolean is
        (Length (Request.Work_Id) > 0
         and then Length (Request.Candidate_Revision) > 0
         and then Length (Request.Candidate_Source) > 0
         and then Length (Request.Contract_Digest) > 0
         and then Request.Assessment_Operation /= 0
         and then Request.Improve_Operation /= 0);

      procedure Gather_Evidence (Failed : out Boolean) is
      begin
         Establish_Assessment
           (Store, Quality,
            (Operation => Request.Assessment_Operation,
             Work_Id => Request.Work_Id,
             Project => Request.Project,
             Project_Selector => Request.Project_Selector,
             Profile => Request.Profile,
             Candidate_Source => Request.Candidate_Source,
             Policy_Fingerprint => Request.Policy_Fingerprint,
             Toolchain_Fingerprint => Request.Toolchain_Fingerprint),
            Assessment_Result, Result);
         Failed := Result.Kind /= Success;
         if Failed then
            return;
         end if;
         Enter_Verifying
           (Store, To_String (Request.Work_Id), Positive (Assessment_Result.Assessment_Id), Result);
         Failed := Result.Kind /= Success;
         if Failed then
            return;
         end if;
         Quality_Manager.Integrations.Quality.Compare
           (Quality, Request.Baseline_Assessment, Positive (Assessment_Result.Assessment_Id), Comparison);
         Decode_Regression (Comparison, Regression_Result, Result);
         Failed := Result.Kind /= Success;
         if Failed then
            return;
         end if;
         Improve_Verification
           (Store, Planner, Request, Positive (Assessment_Result.Assessment_Id), Improve_Result, Result);
         Failed := Result.Kind /= Success;
      end Gather_Evidence;

      procedure Save_Verification is
      begin
         Record_Item :=
           (Composite_Key => To_Unbounded_String
              (Quality_Manager.Identities.Canonical_Digest
                 ([Quality_Manager.Identities.Text_Value (To_String (Request.Work_Id)),
                   Quality_Manager.Identities.Number_Value
                     (Interfaces.Unsigned_64 (Assessment_Result.Assessment_Id)),
                   Quality_Manager.Identities.Text_Value (To_String (Request.Contract_Digest))])),
            Work_Id => Request.Work_Id,
            Assessment =>
              (Project => Request.Project, Run_Id => Positive (Assessment_Result.Assessment_Id)),
            Contract_Digest => Request.Contract_Digest,
            Native_Result => To_Unbounded_String
              (Quality_Manager.Integrations.Runner.Execution_State'Image (Native.State)),
            Improve_Result => Improve_Result.Task_Outcome,
            Regression_Result => To_Unbounded_String
              (Natural'Image (Regression_Result.Regression_Count)),
            Candidate_Revision => Request.Candidate_Revision,
            Source_Fingerprint => Assessment_Result.Source_Fingerprint,
            Policy_Fingerprint => Assessment_Result.Policy_Fingerprint,
            Toolchain_Fingerprint => Assessment_Result.Toolchain_Fingerprint);
         Quality_Manager.Storage.Records.Save (Store, Record_Item, Result);
      end Save_Verification;

      procedure Finalize_Work is
      begin
         Target := Final_State (Decision, Request);
         Quality_Manager.Storage.Read (Store, To_String (Request.Work_Id), Work_Record, Result);
         if Result.Kind /= Success then
            return;
         end if;
         begin
            Current_State := Quality_Manager.Model.Work_State'Value (To_String (Work_Record.State));
         exception
            when Constraint_Error =>
               Result := Make_Result (Incompatible_Contract, "unknown final work state", "qm.verify.final-state");
               return;
         end;
         if Current_State = Target then
            Result := Make_Result (Success);
         elsif Current_State = Quality_Manager.Model.Verifying then
            Quality_Manager.Storage.Transition_Work
              (Store, To_String (Request.Work_Id), Current_State, Target,
               "event:" & To_String (Request.Work_Id) & ":verified:" &
                 Positive'Image (Assessment_Result.Assessment_Id),
               To_String (Decision.Diagnostic),
               "assessment:" & Positive'Image (Assessment_Result.Assessment_Id), Result);
         else
            Result := Make_Result
              (Invalid_Request, "work changed during verification", "qm.verify.concurrent-state");
         end if;
         if Result.Kind = Success and then not Decision.Verified then
            Result := Make_Result (Negative_Result, To_String (Decision.Diagnostic), "qm.verify.negative");
         end if;
      end Finalize_Work;

      Failed : Boolean;
   begin
      Decision := (others => <>);
      if not Request_Is_Valid then
         Result := Make_Result (Invalid_Request, "verification request is incomplete", "qm.verify.request");
         return;
      end if;
      Gather_Evidence (Failed);
      if Failed then
         return;
      end if;

      Context :=
        (Project_Id            => Request.Project.Quality_Project_Id,
         Project_Path          => Request.Project.Canonical_Path,
         Candidate_Source      => Request.Candidate_Source,
         Policy_Fingerprint    => Request.Policy_Fingerprint,
         Toolchain_Fingerprint => Request.Toolchain_Fingerprint,
         Baseline_Assessment   => Request.Baseline_Assessment,
         Current_Assessment    => Positive (Assessment_Result.Assessment_Id),
         Improve_Plan_Id       => Request.Improve_Plan_Id,
         Improve_Task_Id       => Request.Improve_Task_Id);
      Decide (Native, Assessment_Result, Regression_Result, Improve_Result, Context, Decision);
      Save_Verification;
      if Result.Kind /= Success then
         return;
      end if;
      Finalize_Work;
   end Verify_Remediation;
