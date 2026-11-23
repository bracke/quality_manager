separate (Quality_Manager_Test_Suite)
procedure Test_Maintenance_Cycle (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path      : constant String := "/tmp/quality-manager-maintenance.database";
   Store     : aliased Quality_Manager.Storage.Store;
   Scheduler : aliased Quality_Manager.Scheduler.Scheduler_Type;
   Quality   : Quality_Manager.Integrations.Quality.Adapter;
   Planner   : Quality_Manager.Integrations.Improve.Adapter;
   Runner    : Quality_Manager.Integrations.Runner.Adapter;
   Context   : Quality_Manager.Maintenance.Context;
   Result    : Quality_Manager.Results.Operation_Result;
   Values    : Quality_Manager.Storage.Entity_Vectors.Vector;
   Remediation_Work : Unbounded_String;

   function Logical_Snapshot return String is
      Records : Quality_Manager.Storage.Entity_Vectors.Vector;
      Text    : Unbounded_String;
      Local   : Quality_Manager.Results.Operation_Result;
   begin
      for Kind in Quality_Manager.Storage.Record_Kind loop
         Quality_Manager.Storage.List (Store, Kind, Records, 100_000, Local);
         if Local.Kind /= Quality_Manager.Results.Success then
            return "snapshot-error";
         end if;
         for Value of Records loop
            Append (Text, Quality_Manager.Storage.Record_Kind'Image (Value.Kind));
            Append (Text, To_String (Value.Entity_Key));
            Append (Text, To_String (Value.State));
            Append (Text, To_String (Value.Payload));
            Append (Text, Interfaces.Unsigned_64'Image (Value.Generation));
         end loop;
      end loop;
      return Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value (To_String (Text))]);
   end Logical_Snapshot;

   procedure Cleanup is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      if Ada.Directories.Exists ("/tmp/qm-adapter-project-integrated") then
         Ada.Directories.Delete_File ("/tmp/qm-adapter-project-integrated");
      end if;
   end Cleanup;
begin
   Cleanup;
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "maintenance store opened");
   Quality_Manager.Maintenance.Run_Cycle (Context, "", False, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
           "uninitialized maintenance context fails closed");
   Quality_Manager.Maintenance.Reconcile_Authorized_Work (Context, "", 1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
           "uninitialized authorized-work reconciliation fails closed");
   Quality_Manager.Maintenance.Reconcile_Cycles (Context, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
           "uninitialized cycle reconciliation fails closed");
   Quality_Manager.Scheduler.Initialize (Scheduler);
   Quality_Manager.Scheduler.Configure (Scheduler, Store'Unchecked_Access, 4, 1);
   Quality_Manager.Integrations.Quality.Initialize
     (Quality, "./bin/qm_adapter_fixture", "quality.db");
   Quality_Manager.Integrations.Improve.Initialize
     (Planner, "./bin/qm_adapter_fixture", "improve.toml", "quality.db", "improve.db");
   Quality_Manager.Integrations.Runner.Initialize (Runner, "./bin/qm_adapter_fixture");
   Quality_Manager.Maintenance.Initialize
     (Context, Store'Unchecked_Access, Scheduler'Unchecked_Access, Quality, Planner, Runner, 60);
   Quality_Manager.Maintenance.Run_Cycle (Context, "", False, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "maintenance consumes due assessment work without blocking on disabled projects: "
      & Quality_Manager.Results.Message (Result)
      & " pending=" & Natural'Image (Quality_Manager.Scheduler.Pending_Count (Scheduler)));
   Assert (Quality_Manager.Scheduler.Pending_Count (Scheduler) = 0,
      "maintenance consumes due assessment work without blocking on disabled projects: "
      & Quality_Manager.Results.Message (Result)
      & " pending=" & Natural'Image (Quality_Manager.Scheduler.Pending_Count (Scheduler)));
   Assert (Quality_Manager.Scheduler.Active_Count
        (Scheduler, Quality_Manager.Scheduler.Assessment_Resource) = 0,
      "maintenance consumes due assessment work without blocking on disabled projects: "
      & Quality_Manager.Results.Message (Result)
      & " pending=" & Natural'Image (Quality_Manager.Scheduler.Pending_Count (Scheduler)));
   Quality_Manager.Storage.List
     (Store, Quality_Manager.Storage.Project_Record, Values, 10, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
           "qualified project inventory is synchronized across multiple projects");
   Assert (Natural (Values.Length) = 3,
           "qualified project inventory is synchronized across multiple projects");
   declare
      Observed_Count : Natural := 0;
   begin
      for Value of Values loop
         if Ada.Strings.Fixed.Index (To_String (Value.Payload), """last_assessment_run"":2") > 0 then
            Observed_Count := Observed_Count + 1;
         end if;
      end loop;
      Assert
        (Observed_Count = 2,
         "complete and incomplete assessments remain the latest durable project observations");
   end;
   Quality_Manager.Storage.List
     (Store, Quality_Manager.Storage.Cycle_Record, Values, 10, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
           "each selected project has independent durable cycle state");
   Assert (Natural (Values.Length) = 3,
           "each selected project has independent durable cycle state");
   declare
      Completed : Natural := 0;
      Planned   : Natural := 0;
   begin
      for Value of Values loop
         if To_String (Value.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Verified)
           and then Value.Terminal
         then
            Completed := Completed + 1;
         elsif To_String (Value.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Discovered)
           and then not Value.Terminal
         then
            Planned := Planned + 1;
         end if;
      end loop;
Assert (Completed = 2,
         "completed project passes close their cycles while disabled dry-run work remains planned");
      Assert (Planned = 1,
         "completed project passes close their cycles while disabled dry-run work remains planned");
   end;
   Quality_Manager.Storage.List
     (Store, Quality_Manager.Storage.Work_Item_Record, Values, 10, Result);
   declare
      Verified_Count : Natural := 0;
      Inconclusive_Count : Natural := 0;
      Approval_Count : Natural := 0;
      Assessment_Work : Unbounded_String;
   begin
      for Value of Values loop
         if To_String (Value.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Verified)
         then
            Verified_Count := Verified_Count + 1;
            Assessment_Work := Value.Entity_Key;
         elsif To_String (Value.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Inconclusive)
         then
            Inconclusive_Count := Inconclusive_Count + 1;
         elsif To_String (Value.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Awaiting_Approval)
         then
            Approval_Count := Approval_Count + 1;
            Remediation_Work := Value.Entity_Key;
Assert (Ada.Strings.Fixed.Index (To_String (Value.Payload), """plan_id"":""PLAN-001""") > 0,
               "remediation work retains the exact plan task and canonical finding set");
            Assert (Ada.Strings.Fixed.Index
                 (To_String (Value.Payload), """task_id"":""IMP-001""") > 0,
               "remediation work retains the exact plan task and canonical finding set");
            Assert (Ada.Strings.Fixed.Index
                 (To_String (Value.Payload),
                  """planned_source_fingerprint"":""candidate-source""") > 0,
               "remediation work retains the exact plan task and canonical finding set");
            Assert (Ada.Strings.Fixed.Index
                 (To_String (Value.Payload), "finding-a\nfinding-b") > 0,
               "remediation work retains the exact plan task and canonical finding set");
         end if;
      end loop;
Assert (Result.Kind = Quality_Manager.Results.Success,
         "violations create approval-gated remediation while incomplete evidence remains inconclusive");
      Assert (Natural (Values.Length) = 3,
         "violations create approval-gated remediation while incomplete evidence remains inconclusive");
      Assert (Verified_Count = 1,
         "violations create approval-gated remediation while incomplete evidence remains inconclusive");
      Assert (Inconclusive_Count = 1,
         "violations create approval-gated remediation while incomplete evidence remains inconclusive");
      Assert (Approval_Count = 1,
         "violations create approval-gated remediation while incomplete evidence remains inconclusive");
      Quality_Manager.Planning.Generate_Or_Reconcile
        (Store, Planner,
         (Quality_Database_Id => To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
          Quality_Project_Id => 7,
          Canonical_Path => To_Unbounded_String ("/project")),
         2, "candidate-source", "policy", Quality_Manager.Model.Maintenance,
         To_String (Assessment_Work), Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success,
         "committed planning recovery adopts the exact stored plan without duplicate work");
   end;
   Quality_Manager.Storage.List
     (Store, Quality_Manager.Storage.Journal_Record, Values, 10, Result);
   declare
      Committed_Count : Natural := 0;
   begin
      for Value of Values loop
         if To_String (Value.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Committed)
         then
            Committed_Count := Committed_Count + 1;
         end if;
      end loop;
Assert (Result.Kind = Quality_Manager.Results.Success,
         "assessments and exact-run Improve planning retain committed durable identities");
      Assert (Natural (Values.Length) = 3,
         "assessments and exact-run Improve planning retain committed durable identities");
      Assert (Committed_Count = 3,
         "assessments and exact-run Improve planning retain committed durable identities");
   end;
   declare
      procedure Reject_Plan
        (Mode : String; Expected : Quality_Manager.Results.Result_Kind) is
         Invalid_Planner : Quality_Manager.Integrations.Improve.Adapter;
      begin
         Quality_Manager.Integrations.Improve.Initialize
           (Invalid_Planner, "./bin/qm_adapter_fixture", "improve.toml",
            "planning-" & Mode & ".db", "improve.db");
         Quality_Manager.Planning.Generate_Or_Reconcile
           (Store, Invalid_Planner,
            (Quality_Database_Id => To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
             Quality_Project_Id => 7,
             Canonical_Path => To_Unbounded_String ("/project")),
            2, "candidate-source", "policy", Quality_Manager.Model.Maintenance,
            "invalid-plan-" & Mode, Result);
         Assert
           (Result.Kind = Expected,
            "invalid Improve plan is rejected for " & Mode & ": " &
              Quality_Manager.Results.Result_Kind'Image (Result.Kind));
      end Reject_Plan;
   begin
      Reject_Plan ("invalid-json", Quality_Manager.Results.Invalid_Request);
      Reject_Plan ("empty-tasks", Quality_Manager.Results.Negative_Result);
      Reject_Plan ("bad-task", Quality_Manager.Results.Incompatible_Contract);
      Reject_Plan ("empty-findings", Quality_Manager.Results.Incompatible_Contract);
      Reject_Plan ("duplicate-finding", Quality_Manager.Results.Integrity_Error);
   end;
   declare
      Before : constant String := Logical_Snapshot;
   begin
      Quality_Manager.Maintenance.Run_Cycle (Context, "missing", True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "maintenance selector with no project is explicit");
      Assert (Logical_Snapshot = Before, "unmatched maintenance dry-run is non-mutating");
      Quality_Manager.Maintenance.Run_Cycle (Context, "8", True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "disabled project can be observed in dry-run without dispatch");
      Assert (Logical_Snapshot = Before, "maintenance dry-run preserves all logical database contents");
   end;
   declare
      Work : Quality_Manager.Storage.Schema.Work_Item;
      Approval : Quality_Manager.Storage.Schema.Approval;
   begin
      Quality_Manager.Storage.Decoding.Read_Work
        (Store, To_String (Remediation_Work), Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "approval-gated maintenance work can be reconstructed");
      Approval :=
        (Approval_Id => To_Unbounded_String ("approval-maintenance-expired"),
         Project => Work.Project,
         Plan_Id => Work.Improve_Plan_Id,
         Plan_Revision => Positive (Work.Improve_Revision),
         Content_Digest => Work.Improve_Content_SHA256,
         Authorized_Action => To_Unbounded_String ("publish"),
         Policy_Digest => Work.Effective_Policy_Digest,
         Approver => To_Unbounded_String ("quality-manager-test"),
         Created_At => 1,
         Expires_At => 40);
      Quality_Manager.Storage.Records.Save (Store, Approval, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "expired exact maintenance approval is durable audit evidence");
      Quality_Manager.Maintenance.Reconcile_Authorized_Work
        (Context, "7", 50, Result);
      Quality_Manager.Storage.Decoding.Read_Work
        (Store, To_String (Remediation_Work), Work, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "expired approval cannot publish remediation");
      Assert (Work.State = Quality_Manager.Model.Awaiting_Approval,
         "expired approval cannot publish remediation");
      Approval.Approval_Id := To_Unbounded_String ("approval-maintenance");
      Approval.Expires_At := 100;
      Quality_Manager.Storage.Records.Save (Store, Approval, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "current exact maintenance approval is durable");
      Quality_Manager.Maintenance.Reconcile_Authorized_Work
        (Context, "7", 50, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success,
         "maintenance publishes and executes exact authorized work: "
         & Quality_Manager.Results.Message (Result));
      Quality_Manager.Storage.Decoding.Read_Work
        (Store, To_String (Remediation_Work), Work, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "authorized maintenance completes independent verification, got "
         & Quality_Manager.Model.Work_State'Image (Work.State));
      Assert (Work.State = Quality_Manager.Model.Verified,
         "authorized maintenance completes independent verification, got "
         & Quality_Manager.Model.Work_State'Image (Work.State));
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Verification_Record, Values, 10, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "maintenance retains exact post-remediation verification evidence");
      Assert (Natural (Values.Length) = 1,
         "maintenance retains exact post-remediation verification evidence");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Values.First_Element.Payload), """assessment_run"":4") > 0,
         "maintenance retains exact post-remediation verification evidence");
   end;
   declare
      Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
         7, To_Unbounded_String ("/project"));

      function Failure_Work
        (Name : String; State : Quality_Manager.Model.Work_State)
         return Quality_Manager.Storage.Schema.Work_Item is
        ((Work_Id => To_Unbounded_String ("work:maintenance-" & Name),
          Global_Remediation => To_Unbounded_String ("remediation:maintenance-" & Name),
          Project => Project, Origin => Quality_Manager.Model.Maintenance,
          Finding_Identities => To_Unbounded_String ("AQ-FAIL"), Priority => 100,
          Baseline_Assessment_Run => 2,
          Improve_Plan_Id => To_Unbounded_String ("PLAN-001"), Improve_Revision => 1,
          Improve_Task_Id => To_Unbounded_String ("IMP-001"),
          Improve_Content_SHA256 => To_Unbounded_String
            ("plan-content-sha256-v2:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
          Planned_Source_Fingerprint => To_Unbounded_String ("obsolete-source"),
          Effective_Policy_Digest => To_Unbounded_String ("policy"),
          State => State, Outcome => Quality_Manager.Model.No_Outcome));

      procedure Save_Mapping
        (Work : Quality_Manager.Storage.Schema.Work_Item; Native_Task : String) is
         Mapping : constant Quality_Manager.Storage.Schema.Dispatch :=
           (Dispatch_Id => To_Unbounded_String ("dispatch:" & To_String (Work.Work_Id)),
            Work_Id => Work.Work_Id, Logical_Remediation => Work.Global_Remediation,
            Improve_Task =>
              (Plan_Id => Work.Improve_Plan_Id, Revision => 1, Task_Id => Work.Improve_Task_Id),
            Native_Task_Id => To_Unbounded_String (Native_Task),
            Authorization_Id => To_Unbounded_String ("approval"),
            State => Quality_Manager.Model.Published, Active => True);
      begin
         Quality_Manager.Dispatch.Bind_Published_Task (Store, Mapping, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success,
                 "maintenance failure dispatch is persisted");
      end Save_Mapping;

      Stale_Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        Failure_Work ("stale", Quality_Manager.Model.Published);
      Invalid_Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        Failure_Work ("invalid", Quality_Manager.Model.Published);
      Executing_Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        Failure_Work ("executing", Quality_Manager.Model.Executing);
      Missing_Baseline_Work : Quality_Manager.Storage.Schema.Work_Item :=
        Failure_Work ("baseline-missing", Quality_Manager.Model.Awaiting_Assessment);
      Loaded_Work : Quality_Manager.Storage.Schema.Work_Item;
   begin
      Quality_Manager.Storage.Records.Save (Store, Stale_Work, Result);
      Save_Mapping (Stale_Work, "TASK-001");
      Quality_Manager.Maintenance.Reconcile_Authorized_Work (Context, "7", 50, Result);
      Quality_Manager.Storage.Decoding.Read_Work
        (Store, To_String (Stale_Work.Work_Id), Loaded_Work, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "maintenance blocks remediation whose assessed source is stale");
      Assert (Loaded_Work.State = Quality_Manager.Model.Blocked,
         "maintenance blocks remediation whose assessed source is stale");

      Quality_Manager.Storage.Records.Save (Store, Invalid_Work, Result);
      Save_Mapping (Invalid_Work, "TASK-OTHER");
      Quality_Manager.Maintenance.Reconcile_Authorized_Work (Context, "7", 50, Result);
      Quality_Manager.Storage.Decoding.Read_Work
        (Store, To_String (Invalid_Work.Work_Id), Loaded_Work, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "maintenance escalates an invalid native publication mapping");
      Assert (Loaded_Work.State = Quality_Manager.Model.Needs_Intervention,
         "maintenance escalates an invalid native publication mapping");

      Quality_Manager.Storage.Records.Save (Store, Executing_Work, Result);
      Quality_Manager.Maintenance.Reconcile_Authorized_Work (Context, "7", 50, Result);
      Quality_Manager.Storage.Decoding.Read_Work
        (Store, To_String (Executing_Work.Work_Id), Loaded_Work, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "maintenance durably blocks an executing remediation without a native mapping");
      Assert (Loaded_Work.State = Quality_Manager.Model.Blocked,
         "maintenance durably blocks an executing remediation without a native mapping");

      Missing_Baseline_Work.Baseline_Assessment_Run := 0;
      Quality_Manager.Storage.Records.Save (Store, Missing_Baseline_Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "maintenance verification fixture without a baseline persists");
      Quality_Manager.Maintenance.Reconcile_Authorized_Work (Context, "7", 50, Result);
      Quality_Manager.Storage.Decoding.Read_Work
        (Store, To_String (Missing_Baseline_Work.Work_Id), Loaded_Work, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "maintenance cannot verify remediation without exact baseline evidence");
      Assert (Loaded_Work.State = Quality_Manager.Model.Needs_Intervention,
         "maintenance cannot verify remediation without exact baseline evidence");
   end;
   declare
      Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
         7, To_Unbounded_String ("/project"));
      Cycle : constant Quality_Manager.Storage.Schema.Cycle :=
        (Cycle_Id => To_Unbounded_String ("duplicate-cycle"),
         Workflow => Quality_Manager.Model.Maintenance,
         Trigger => To_Unbounded_String ("test"), Project => Project,
         Policy_Digest => To_Unbounded_String ("policy"),
         State => Quality_Manager.Model.Queued);
      Work_A : constant Quality_Manager.Storage.Schema.Work_Item :=
        (Work_Id => To_Unbounded_String ("work:duplicate-cycle-a"),
         Global_Remediation => To_Unbounded_String ("assessment:duplicate-cycle"),
         Project => Project, Origin => Quality_Manager.Model.Maintenance,
         Finding_Identities => To_Unbounded_String ("__assessment__"), Priority => 1,
         Baseline_Assessment_Run => 0, Improve_Plan_Id => Null_Unbounded_String,
         Improve_Revision => 0, Improve_Task_Id => Null_Unbounded_String,
         Improve_Content_SHA256 => Null_Unbounded_String,
         Planned_Source_Fingerprint => Null_Unbounded_String,
         Effective_Policy_Digest => Null_Unbounded_String,
         State => Quality_Manager.Model.Verified, Outcome => Quality_Manager.Model.Satisfied);
      Work_B : Quality_Manager.Storage.Schema.Work_Item := Work_A;
   begin
      Work_B.Work_Id := To_Unbounded_String ("work:duplicate-cycle-b");
      Work_B.State := Quality_Manager.Model.Inconclusive;
      Work_B.Outcome := Quality_Manager.Model.Evidence_Unavailable;
      Quality_Manager.Storage.Records.Save (Store, Cycle, Result);
      Quality_Manager.Storage.Records.Save (Store, Work_A, Result);
      Quality_Manager.Storage.Records.Save (Store, Work_B, Result);
      Quality_Manager.Maintenance.Reconcile_Cycles (Context, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "cycle reconciliation rejects multiple physical assessment work items");
   end;
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Maintenance_Cycle;

