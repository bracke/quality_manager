separate (Quality_Manager_Test_Suite)
procedure Test_Verification_Workflow (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path      : constant String := "/tmp/quality-manager-verification.database";
   Store     : Quality_Manager.Storage.Store;
   Quality   : Quality_Manager.Integrations.Quality.Adapter;
   Planner   : Quality_Manager.Integrations.Improve.Adapter;
   Native    : Quality_Manager.Integrations.Runner.Task_Snapshot := (others => <>);
   Decision  : Quality_Manager.Verification.Verification_Decision;
   Result    : Quality_Manager.Results.Operation_Result;
   Loaded    : Quality_Manager.Storage.Stored_Entity;
   Project   : constant Quality_Manager.Identities.Project_Key :=
     (Quality_Database_Id => To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
      Quality_Project_Id  => 7,
      Canonical_Path      => To_Unbounded_String ("/project"));
   Work      : constant Quality_Manager.Storage.Schema.Work_Item :=
     (Work_Id            => To_Unbounded_String ("work:verification"),
      Global_Remediation => To_Unbounded_String ("remediation:verification"),
      Project            => Project,
      Origin             => Quality_Manager.Model.Maintenance,
      Finding_Identities => To_Unbounded_String ("AQ-01"),
      Priority           => 1,
      Baseline_Assessment_Run => 1,
      Improve_Plan_Id    => To_Unbounded_String ("PLAN-001"),
      Improve_Revision   => 1,
      Improve_Task_Id    => To_Unbounded_String ("IMP-001"),
      Improve_Content_SHA256 => To_Unbounded_String
        ("plan-content-sha256-v2:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
      Planned_Source_Fingerprint => To_Unbounded_String ("candidate-source"),
      Effective_Policy_Digest => To_Unbounded_String ("policy"),
      State              => Quality_Manager.Model.Awaiting_Assessment,
      Outcome            => Quality_Manager.Model.No_Outcome);
   Request   : constant Quality_Manager.Verification.Remediation_Request :=
     (Work_Id               => To_Unbounded_String ("work:verification"),
      Project               => Project,
      Project_Selector      => To_Unbounded_String ("7"),
      Profile               => To_Unbounded_String ("ci"),
      Candidate_Revision    => To_Unbounded_String ("candidate-commit"),
      Candidate_Source      => To_Unbounded_String ("candidate-source"),
      Policy_Fingerprint    => To_Unbounded_String ("policy"),
      Toolchain_Fingerprint => To_Unbounded_String ("toolchain"),
      Baseline_Assessment   => 1,
      Improve_Plan_Id       => To_Unbounded_String ("PLAN-001"),
      Improve_Plan_Revision => 1,
      Improve_Task_Id       => To_Unbounded_String ("IMP-001"),
      Contract_Digest       => To_Unbounded_String ("contract-digest"),
      Assessment_Operation  => 200,
      Improve_Operation     => 201,
      Attempts_Used         => 1,
      Maximum_Attempts      => 2);

   procedure Cleanup is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Cleanup;
begin
   Cleanup;
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "verification store opened");
   Quality_Manager.Storage.Records.Save (Store, Work, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "awaiting-assessment work persisted");
   Quality_Manager.Integrations.Quality.Initialize
     (Quality, "./bin/qm_adapter_fixture", "quality.db");
   Quality_Manager.Integrations.Improve.Initialize
     (Planner, "./bin/qm_adapter_fixture", "improve.toml", "quality.db", "improve.db");
   Native.State := Quality_Manager.Integrations.Runner.Completed_State;
   Native.Workspace_State := To_Unbounded_String ("integrated");

   declare
      Assessment_Request : Quality_Manager.Verification.Assessment_Request :=
        (Operation => 0, Work_Id => Work.Work_Id, Project => Project,
         Project_Selector => To_Unbounded_String ("7"),
         Profile => To_Unbounded_String ("ci"),
         Candidate_Source => To_Unbounded_String ("candidate-source"),
         Policy_Fingerprint => To_Unbounded_String ("policy"),
         Toolchain_Fingerprint => To_Unbounded_String ("toolchain"));
      Evidence : Quality_Manager.Verification.Assessment_Evidence;

      function Intent return String is
        (Quality_Manager.Identities.Canonical_Digest
           ([Quality_Manager.Identities.Text_Value ("authoritative-assessment-v1"),
             Quality_Manager.Identities.Text_Value (To_String (Assessment_Request.Work_Id)),
             Quality_Manager.Identities.Text_Value
               (To_String (Assessment_Request.Project.Quality_Database_Id)),
             Quality_Manager.Identities.Number_Value
               (Interfaces.Unsigned_64 (Assessment_Request.Project.Quality_Project_Id)),
             Quality_Manager.Identities.Text_Value
               (To_String (Assessment_Request.Project.Canonical_Path)),
             Quality_Manager.Identities.Text_Value
               (To_String (Assessment_Request.Project_Selector)),
             Quality_Manager.Identities.Text_Value
               (To_String (Assessment_Request.Candidate_Source)),
             Quality_Manager.Identities.Text_Value
               (To_String (Assessment_Request.Policy_Fingerprint)),
             Quality_Manager.Identities.Text_Value
               (To_String (Assessment_Request.Toolchain_Fingerprint)),
             Quality_Manager.Identities.Text_Value
               (To_String (Assessment_Request.Profile))]));

      function Pending return String is
        ("assessment:pending:" &
         Ada.Strings.Fixed.Trim
           (Quality_Manager.Identities.Operation_Id'Image
              (Assessment_Request.Operation), Ada.Strings.Both));
   begin
      Quality_Manager.Verification.Establish_Assessment
        (Store, Quality, Assessment_Request, Evidence, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "authoritative assessment requires a complete durable request");

      Assessment_Request.Operation := 210;
      Quality_Manager.Storage.Put
        (Store,
         (Internal_Id => 1, Kind => Quality_Manager.Storage.Project_Record,
          Entity_Key => To_Unbounded_String ("journal:210"),
          State => To_Unbounded_String ("ENABLED"), Payload => Null_Unbounded_String,
          Terminal => False, Generation => 1),
         Result);
      Quality_Manager.Verification.Establish_Assessment
        (Store, Quality, Assessment_Request, Evidence, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "authoritative assessment rejects a non-journal operation record");

      Assessment_Request.Operation := 211;
      Quality_Manager.Storage.Prepare_Operation
        (Store, 211, "assessment", "different-intent", Pending, Result);
      Quality_Manager.Verification.Establish_Assessment
        (Store, Quality, Assessment_Request, Evidence, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "authoritative assessment rejects operation identity reuse");

      Assessment_Request.Operation := 212;
      Quality_Manager.Storage.Prepare_Operation
        (Store, 212, "assessment", Intent, Pending, Result);
      Quality_Manager.Storage.Advance_Operation
        (Store, 212, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         Pending, "", Result);
      Quality_Manager.Verification.Establish_Assessment
        (Store, Quality, Assessment_Request, Evidence, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "ambiguous assessment invocation requires explicit reconciliation");

      Assessment_Request.Operation := 213;
      Quality_Manager.Storage.Prepare_Operation
        (Store, 213, "assessment", Intent, Pending, Result);
      Quality_Manager.Storage.Advance_Operation
        (Store, 213, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         Pending, "", Result);
      Quality_Manager.Storage.Advance_Operation
        (Store, 213, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
         Pending, "", Result);
      Quality_Manager.Verification.Establish_Assessment
        (Store, Quality, Assessment_Request, Evidence, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "reconciling assessment requires a durable completed run identity");
   end;

   declare
      Incomplete_Request : Quality_Manager.Verification.Remediation_Request := Request;
   begin
      Incomplete_Request.Work_Id := Null_Unbounded_String;
      Quality_Manager.Verification.Verify_Remediation
        (Store, Quality, Planner, Native, Incomplete_Request, Decision, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "remediation verification requires a complete request identity");
   end;

   Quality_Manager.Verification.Verify_Remediation
     (Store, Quality, Planner, Native, Request, Decision, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "fresh assessment, explicit comparison, and Improve verification complete autonomously");
   Assert (Decision.Verified,
      "fresh assessment, explicit comparison, and Improve verification complete autonomously");
   Quality_Manager.Storage.Read (Store, "work:verification", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "only the complete independent predicate marks work verified");
   Assert (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
        (Quality_Manager.Model.Verified),
      "only the complete independent predicate marks work verified");
   Quality_Manager.Storage.Read (Store, "journal:200", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "authoritative assessment side effect is journaled");
   Assert (To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
        (Quality_Manager.Journal.Committed),
      "authoritative assessment side effect is journaled");
   Quality_Manager.Storage.Read (Store, "journal:201", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "Improve verification side effect is journaled");
   Assert (To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
        (Quality_Manager.Journal.Committed),
      "Improve verification side effect is journaled");
   Quality_Manager.Verification.Verify_Remediation
     (Store, Quality, Planner, Native, Request, Decision, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "repeated workflow recovery adopts the exact historical verification");
   Assert (Decision.Verified,
      "repeated workflow recovery adopts the exact historical verification");

   declare
      Unresolved_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Unresolved      : Quality_Manager.Verification.Remediation_Request := Request;
   begin
      Unresolved_Work.Work_Id := To_Unbounded_String ("work:still-failing");
      Unresolved_Work.Global_Remediation := To_Unbounded_String ("remediation:still-failing");
      Unresolved_Work.Improve_Task_Id := To_Unbounded_String ("IMP-FAIL");
      Quality_Manager.Storage.Records.Save (Store, Unresolved_Work, Result);
      Unresolved.Work_Id := Unresolved_Work.Work_Id;
      Unresolved.Improve_Task_Id := To_Unbounded_String ("IMP-FAIL");
      Unresolved.Assessment_Operation := 204;
      Unresolved.Improve_Operation := 205;
      Quality_Manager.Verification.Verify_Remediation
        (Store, Quality, Planner, Native, Unresolved, Decision, Result);
Assert (Result.Kind = Quality_Manager.Results.Negative_Result,
         "native completion without resolving the finding remains unverified");
      Assert (Decision.Outcome = Quality_Manager.Model.Unresolved,
         "native completion without resolving the finding remains unverified");
      Quality_Manager.Storage.Read (Store, "work:still-failing", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "an unresolved finding is sent to bounded replanning");
      Assert (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Planning),
         "an unresolved finding is sent to bounded replanning");
   end;

   declare
      Regression_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Regressed       : Quality_Manager.Verification.Remediation_Request := Request;
   begin
      Regression_Work.Work_Id := To_Unbounded_String ("work:regression");
      Regression_Work.Global_Remediation := To_Unbounded_String ("remediation:regression");
      Quality_Manager.Storage.Records.Save (Store, Regression_Work, Result);
      Regressed.Work_Id := Regression_Work.Work_Id;
      Regressed.Baseline_Assessment := 3;
      Regressed.Assessment_Operation := 206;
      Regressed.Improve_Operation := 207;
      Quality_Manager.Verification.Verify_Remediation
        (Store, Quality, Planner, Native, Regressed, Decision, Result);
Assert (Result.Kind = Quality_Manager.Results.Negative_Result,
         "resolved work with a new regression is not verified");
      Assert (Decision.Outcome = Quality_Manager.Model.Regression,
         "resolved work with a new regression is not verified");
      Quality_Manager.Storage.Read (Store, "work:regression", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "a regressed candidate is rejected and durably blocked");
      Assert (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Blocked),
         "a regressed candidate is rejected and durably blocked");
   end;

   declare
      Interrupted_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Interrupted      : Quality_Manager.Verification.Remediation_Request := Request;
   begin
      Interrupted_Work.Work_Id := To_Unbounded_String ("work:interrupted-assessment");
      Interrupted_Work.Global_Remediation := To_Unbounded_String ("remediation:interrupted-assessment");
      Quality_Manager.Storage.Records.Save (Store, Interrupted_Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "interrupted assessment work persisted");
      Interrupted.Work_Id := Interrupted_Work.Work_Id;
      Interrupted.Project_Selector := To_Unbounded_String ("99");
      Interrupted.Assessment_Operation := 202;
      Interrupted.Improve_Operation := 203;
      Quality_Manager.Verification.Verify_Remediation
        (Store, Quality, Planner, Native, Interrupted, Decision, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Invalid_Request,
         "invalid assessment output cannot become evidence");
      Quality_Manager.Verification.Verify_Remediation
        (Store, Quality, Planner, Native, Interrupted, Decision, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Authorization_Required,
         "ambiguous interrupted assessment is not blindly repeated");
      Quality_Manager.Storage.Read (Store, "journal:202", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "ambiguous assessment recovery is durably escalated");
      Assert (To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Needs_Intervention),
         "ambiguous assessment recovery is durably escalated");
   end;

   declare
      Manual_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Work_Id     : constant String := "work:manual-assessment";
      Operation   : constant Quality_Manager.Identities.Operation_Id :=
        Quality_Manager.Identities.Operation_Identity ("maintenance-assessment", Work_Id);
      Intent      : constant String := Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value ("authoritative-assessment-v1"),
          Quality_Manager.Identities.Text_Value (Work_Id),
          Quality_Manager.Identities.Text_Value (To_String (Project.Quality_Database_Id)),
          Quality_Manager.Identities.Number_Value
            (Interfaces.Unsigned_64 (Project.Quality_Project_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Project.Canonical_Path)),
          Quality_Manager.Identities.Text_Value ("7"),
          Quality_Manager.Identities.Text_Value ("candidate-source"),
          Quality_Manager.Identities.Text_Value ("policy"),
          Quality_Manager.Identities.Text_Value ("toolchain"),
          Quality_Manager.Identities.Text_Value ("")]);
   begin
      Manual_Work.Work_Id := To_Unbounded_String (Work_Id);
      Manual_Work.Global_Remediation := To_Unbounded_String ("assessment:manual");
      Manual_Work.Finding_Identities := To_Unbounded_String ("__assessment__");
      Manual_Work.Improve_Plan_Id := Null_Unbounded_String;
      Manual_Work.Improve_Revision := 0;
      Manual_Work.Improve_Task_Id := Null_Unbounded_String;
      Manual_Work.State := Quality_Manager.Model.Needs_Intervention;
      Manual_Work.Outcome := Quality_Manager.Model.Evidence_Unavailable;
      Quality_Manager.Storage.Records.Save (Store, Manual_Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "manual recovery work persisted");
      Quality_Manager.Storage.Prepare_Operation
        (Store, Operation, "authoritative-assessment", Intent, "assessment:pending", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "manual recovery intent persisted");
      Quality_Manager.Storage.Advance_Operation
        (Store, Operation, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         "assessment:pending", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "manual recovery invocation persisted");
      Quality_Manager.Recovery.Reconcile_Assessment
        (Store, Quality, Operation, 2, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "exact completed assessment is reconciled");
      Quality_Manager.Storage.Read (Store, "journal:" &
        Ada.Strings.Fixed.Trim
          (Interfaces.Unsigned_64'Image (Interfaces.Unsigned_64 (Operation)), Ada.Strings.Both),
        Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "manual reconciliation commits the interrupted assessment journal");
      Assert (To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Committed),
         "manual reconciliation commits the interrupted assessment journal");
      Quality_Manager.Storage.Read (Store, Work_Id, Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "complete reconciled evidence finishes assessment work");
      Assert (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Verified),
         "complete reconciled evidence finishes assessment work");
      Quality_Manager.Recovery.Reconcile_Assessment
        (Store, Quality, Operation, 2, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "assessment reconciliation replay is idempotent");
   end;

   declare
      Rejected_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Work_Id       : constant String := "work:rejected-assessment";
      Operation     : constant Quality_Manager.Identities.Operation_Id :=
        Quality_Manager.Identities.Operation_Identity ("maintenance-assessment", Work_Id);
   begin
      Rejected_Work.Work_Id := To_Unbounded_String (Work_Id);
      Rejected_Work.Global_Remediation := To_Unbounded_String ("assessment:rejected");
      Rejected_Work.Finding_Identities := To_Unbounded_String ("__assessment__");
      Rejected_Work.Improve_Plan_Id := Null_Unbounded_String;
      Rejected_Work.Improve_Revision := 0;
      Rejected_Work.Improve_Task_Id := Null_Unbounded_String;
      Rejected_Work.State := Quality_Manager.Model.Needs_Intervention;
      Quality_Manager.Storage.Records.Save (Store, Rejected_Work, Result);
      Quality_Manager.Storage.Prepare_Operation
        (Store, Operation, "authoritative-assessment", "different-intent", "assessment:pending", Result);
      Quality_Manager.Storage.Advance_Operation
        (Store, Operation, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         "assessment:pending", "", Result);
      Quality_Manager.Recovery.Reconcile_Assessment
        (Store, Quality, Operation, 2, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Negative_Result,
         "observed assessment with mismatched intent is explicitly rejected");
      Quality_Manager.Storage.Read (Store, Work_Id, Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "intent-mismatched assessment work is durably blocked");
      Assert (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Blocked),
         "intent-mismatched assessment work is durably blocked");
      Quality_Manager.Storage.Read
        (Store, "journal:" & Ada.Strings.Fixed.Trim
           (Interfaces.Unsigned_64'Image (Interfaces.Unsigned_64 (Operation)), Ada.Strings.Both),
         Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "intent-mismatched assessment journal preserves a terminal rejection");
      Assert (To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Aborted),
         "intent-mismatched assessment journal preserves a terminal rejection");
   end;

   declare
      procedure Exercise_Recovery_State
        (Name           : String;
         Initial_State  : Quality_Manager.Model.Work_State;
         Run            : Positive;
         Expected_State : Quality_Manager.Model.Work_State) is
         Recovered : Quality_Manager.Storage.Schema.Work_Item := Work;
         Work_Id   : constant String := "work:recovery-" & Name;
         Operation : constant Quality_Manager.Identities.Operation_Id :=
           Quality_Manager.Identities.Operation_Identity ("maintenance-assessment", Work_Id);
         Intent : constant String := Quality_Manager.Identities.Canonical_Digest
           ([Quality_Manager.Identities.Text_Value ("authoritative-assessment-v1"),
             Quality_Manager.Identities.Text_Value (Work_Id),
             Quality_Manager.Identities.Text_Value (To_String (Project.Quality_Database_Id)),
             Quality_Manager.Identities.Number_Value
               (Interfaces.Unsigned_64 (Project.Quality_Project_Id)),
             Quality_Manager.Identities.Text_Value (To_String (Project.Canonical_Path)),
             Quality_Manager.Identities.Text_Value ("7"),
             Quality_Manager.Identities.Text_Value ("candidate-source"),
             Quality_Manager.Identities.Text_Value ("policy"),
             Quality_Manager.Identities.Text_Value ("toolchain"),
             Quality_Manager.Identities.Text_Value ("")]);
      begin
         Recovered.Work_Id := To_Unbounded_String (Work_Id);
         Recovered.Global_Remediation := To_Unbounded_String ("assessment:recovery-" & Name);
         Recovered.Finding_Identities := To_Unbounded_String ("__assessment__");
         Recovered.Improve_Plan_Id := Null_Unbounded_String;
         Recovered.Improve_Revision := 0;
         Recovered.Improve_Task_Id := Null_Unbounded_String;
         Recovered.State := Initial_State;
         Recovered.Outcome := Quality_Manager.Model.Evidence_Unavailable;
         Quality_Manager.Storage.Records.Save (Store, Recovered, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "recovery state work persisted: " & Name);
         Quality_Manager.Storage.Prepare_Operation
           (Store, Operation, "authoritative-assessment", Intent, "assessment:pending", Result);
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
            "assessment:pending", "", Result);
         Quality_Manager.Recovery.Reconcile_Assessment (Store, Quality, Operation, Run, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "recovery state reconciled: " & Name);
         Quality_Manager.Storage.Read (Store, Work_Id, Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
            "recovery state reaches its evidence-derived outcome: " & Name);
         Assert (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image (Expected_State),
            "recovery state reaches its evidence-derived outcome: " & Name);
      end Exercise_Recovery_State;
   begin
      Exercise_Recovery_State
        ("incomplete-intervention", Quality_Manager.Model.Needs_Intervention, 3,
         Quality_Manager.Model.Inconclusive);
      Exercise_Recovery_State
        ("incomplete-executing", Quality_Manager.Model.Executing, 3,
         Quality_Manager.Model.Inconclusive);
      Exercise_Recovery_State
        ("complete-executing", Quality_Manager.Model.Executing, 2,
         Quality_Manager.Model.Verified);
   end;
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Verification_Workflow;

