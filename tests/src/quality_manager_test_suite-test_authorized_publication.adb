separate (Quality_Manager_Test_Suite)
procedure Test_Authorized_Publication (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path : constant String := "/tmp/quality-manager-publication.database";
   Store : Quality_Manager.Storage.Store;
   Planner : Quality_Manager.Integrations.Improve.Adapter;
   Runner : Quality_Manager.Integrations.Runner.Adapter;
   Result : Quality_Manager.Results.Operation_Result;
   Snapshot : Quality_Manager.Integrations.Runner.Task_Snapshot;
   Loaded : Quality_Manager.Storage.Stored_Entity;
   Project : constant Quality_Manager.Identities.Project_Key :=
     (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
   Work : Quality_Manager.Storage.Schema.Work_Item :=
     (Work_Id => To_Unbounded_String ("work:publication"),
      Global_Remediation => To_Unbounded_String ("remediation:publication"),
      Project => Project, Origin => Quality_Manager.Model.Maintenance,
      Finding_Identities => To_Unbounded_String ("AQ-01"), Priority => 200,
      Baseline_Assessment_Run => 1,
      Improve_Plan_Id => To_Unbounded_String ("PLAN-001"), Improve_Revision => 1,
      Improve_Task_Id => To_Unbounded_String ("IMP-001"),
      Improve_Content_SHA256 => To_Unbounded_String
        ("plan-content-sha256-v2:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
      Planned_Source_Fingerprint => To_Unbounded_String ("candidate-source"),
      Effective_Policy_Digest => To_Unbounded_String ("policy-1"),
      State => Quality_Manager.Model.Awaiting_Approval,
      Outcome => Quality_Manager.Model.Authorization_Required);
   Approval : constant Quality_Manager.Storage.Schema.Approval :=
     (Approval_Id => To_Unbounded_String ("approval-publication"), Project => Project,
      Plan_Id => To_Unbounded_String ("PLAN-001"), Plan_Revision => 1,
      Content_Digest => Work.Improve_Content_SHA256,
      Authorized_Action => To_Unbounded_String ("publish"),
      Policy_Digest => To_Unbounded_String ("policy-1"),
      Approver => To_Unbounded_String ("release-manager"), Created_At => 1, Expires_At => 100);
   Published : Quality_Manager.Storage.Schema.Dispatch;
   Journals  : Quality_Manager.Storage.Entity_Vectors.Vector;

   procedure Cleanup is
   begin
      if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
      if Ada.Directories.Exists ("/tmp/qm-adapter-project-integrated") then
         Ada.Directories.Delete_File ("/tmp/qm-adapter-project-integrated");
      end if;
   end Cleanup;

   procedure Exercise_Publication_Failure (Name : String) is
      Failed_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Failed_Approval : Quality_Manager.Storage.Schema.Approval := Approval;
      Failed_Planner : Quality_Manager.Integrations.Improve.Adapter;
      Ignored : Quality_Manager.Storage.Schema.Dispatch;
   begin
      Failed_Work.Work_Id := To_Unbounded_String ("work:publication-" & Name);
      Failed_Work.Global_Remediation := To_Unbounded_String ("remediation:publication-" & Name);
      Failed_Approval.Approval_Id := To_Unbounded_String ("approval-publication-" & Name);
      Quality_Manager.Storage.Records.Save (Store, Failed_Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "publication failure work persists for " & Name);
      Quality_Manager.Storage.Records.Save (Store, Failed_Approval, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "publication failure approval persists for " & Name);
      Quality_Manager.Integrations.Improve.Initialize
        (Failed_Planner, "./bin/qm_adapter_fixture", "improve.toml",
         Name & ".db", "improve.db");
      Quality_Manager.Dispatch.Publish_Approved
        (Store, Failed_Planner, Failed_Work, Failed_Approval, 50, Ignored, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
         "publication contract failure is rejected for " & Name & ": " &
           Quality_Manager.Results.Result_Kind'Image (Result.Kind));
   end Exercise_Publication_Failure;

   procedure Exercise_Durable_Approval_Failure
     (Name    : String;
      Kind    : Quality_Manager.Storage.Record_Kind;
      State   : String;
      Payload : String) is
      Failed_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Failed_Approval : Quality_Manager.Storage.Schema.Approval := Approval;
      Stored : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1,
         Kind => Kind,
         Entity_Key => To_Unbounded_String ("approval:approval-durable-" & Name),
         State => To_Unbounded_String (State),
         Payload => To_Unbounded_String (Payload),
         Terminal => False,
         Generation => 1);
      Ignored : Quality_Manager.Storage.Schema.Dispatch;
   begin
      Failed_Work.Work_Id := To_Unbounded_String ("work:durable-" & Name);
      Failed_Work.Global_Remediation := To_Unbounded_String ("remediation:durable-" & Name);
      Failed_Approval.Approval_Id := To_Unbounded_String ("approval-durable-" & Name);
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "invalid durable approval fixture persists for " & Name);
      Quality_Manager.Dispatch.Publish_Approved
        (Store, Planner, Failed_Work, Failed_Approval, 50, Ignored, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Integrity_Error,
         "corrupt durable approval is rejected for " & Name & ": " &
           Quality_Manager.Results.Result_Kind'Image (Result.Kind));
   end Exercise_Durable_Approval_Failure;
begin
   Cleanup;
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "publication store opens");
   Quality_Manager.Integrations.Improve.Initialize
     (Planner, "./bin/qm_adapter_fixture", "improve.toml", "quality.db", "improve.db");
   declare
      Invalid_Mapping : Quality_Manager.Storage.Schema.Dispatch :=
        (Dispatch_Id => Null_Unbounded_String, Work_Id => Null_Unbounded_String,
         Logical_Remediation => Null_Unbounded_String,
         Improve_Task => (Null_Unbounded_String, 1, Null_Unbounded_String),
         Native_Task_Id => Null_Unbounded_String, Authorization_Id => Null_Unbounded_String,
         State => Quality_Manager.Model.Published, Active => True);
      Incomplete_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
   begin
      Quality_Manager.Dispatch.Bind_Published_Task (Store, Invalid_Mapping, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "incomplete publication mapping is rejected");
      Invalid_Mapping.Dispatch_Id := To_Unbounded_String ("dispatch:inactive");
      Invalid_Mapping.Work_Id := To_Unbounded_String ("work:inactive");
      Invalid_Mapping.Logical_Remediation := To_Unbounded_String ("remediation:inactive");
      Invalid_Mapping.Improve_Task :=
        (To_Unbounded_String ("PLAN"), 1, To_Unbounded_String ("TASK"));
      Invalid_Mapping.Native_Task_Id := To_Unbounded_String ("NATIVE");
      Invalid_Mapping.Active := False;
      Quality_Manager.Dispatch.Bind_Published_Task (Store, Invalid_Mapping, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "inactive new publication mapping is rejected");
      Incomplete_Work.Improve_Revision := 0;
      Quality_Manager.Dispatch.Publish_Approved
        (Store, Planner, Incomplete_Work, Approval, 50, Invalid_Mapping, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "incomplete publication work is rejected before authorization");
   end;
   Quality_Manager.Storage.Records.Save (Store, Work, Result);
   Quality_Manager.Integrations.Improve.Initialize
     (Planner, "./bin/qm_adapter_fixture", "improve.toml", "quality.db", "improve.db");
   Quality_Manager.Dispatch.Publish_Approved
     (Store, Planner, Work, Approval, 50, Published, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Authorization_Required,
      "an in-memory approval cannot bypass durable authorization");
   Exercise_Durable_Approval_Failure
     ("record", Quality_Manager.Storage.Project_Record, "APPROVED", "{}");
   Exercise_Durable_Approval_Failure
     ("json", Quality_Manager.Storage.Approval_Record, "APPROVED", "{");
   Exercise_Durable_Approval_Failure
     ("mismatch", Quality_Manager.Storage.Approval_Record, "APPROVED", "{}");
   Exercise_Durable_Approval_Failure
     ("timestamp-missing", Quality_Manager.Storage.Approval_Record, "APPROVED",
      "{""project"":{""quality_database_id"":""database-a"",""quality_project_id"":7," &
        """canonical_path"":""/project""},""plan_id"":""PLAN-001"",""plan_revision"":1," &
        """content_digest"":""plan-content-sha256-v2:" &
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
        """action"":""publish"",""policy_digest"":""policy-1""," &
        """approver"":""release-manager"",""expires_at"":100}");
   declare
      Expired_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Expired_Approval : Quality_Manager.Storage.Schema.Approval := Approval;
      Ignored : Quality_Manager.Storage.Schema.Dispatch;
   begin
      Expired_Work.Work_Id := To_Unbounded_String ("work:expired-approval");
      Expired_Work.Global_Remediation := To_Unbounded_String ("remediation:expired-approval");
      Expired_Approval.Approval_Id := To_Unbounded_String ("approval-expired-publication");
      Expired_Approval.Expires_At := 40;
      Quality_Manager.Storage.Records.Save (Store, Expired_Approval, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "expired publication approval remains durable audit evidence");
      Quality_Manager.Dispatch.Publish_Approved
        (Store, Planner, Expired_Work, Expired_Approval, 50, Ignored, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "expired durable approval cannot authorize publication");
   end;
   Quality_Manager.Storage.Records.Save (Store, Approval, Result);
   Quality_Manager.Dispatch.Publish_Approved
     (Store, Planner, Work, Approval, 50, Published, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then To_String (Published.Native_Task_Id) = "TASK-001"
      and then To_String (Published.Authorization_Id) = "approval-publication",
      "authorized publication retains Improve's native mapping");
   Quality_Manager.Storage.Read (Store, "work:publication", Loaded, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then To_String (Loaded.State) = Quality_Manager.Model.Published'Image,
      "authorized publication reaches the published coordinator state");
   Quality_Manager.Storage.Read
     (Store, "active-dispatch:" & To_String (Work.Global_Remediation), Loaded, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Ada.Strings.Fixed.Index (To_String (Loaded.Payload), "TASK-001") > 0,
      "authoritative native mapping is persisted as the active dispatch");
   Quality_Manager.Storage.List
     (Store, Quality_Manager.Storage.Journal_Record, Journals, 10, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Natural (Journals.Length) = 2
      and then (for all Journal of Journals =>
        To_String (Journal.State) = Quality_Manager.Journal.Committed'Image),
      "approval and publication side effects both commit durable journals");
   Exercise_Publication_Failure ("approval-mismatch");
   Exercise_Publication_Failure ("approval-string-type");
   Exercise_Publication_Failure ("approval-natural-type");
   Exercise_Publication_Failure ("approval-natural-range");
   Exercise_Publication_Failure ("approval-boolean-type");
   Exercise_Publication_Failure ("publication-identity");
   Exercise_Publication_Failure ("publication-empty");
   Exercise_Publication_Failure ("publication-bad-mapping");
   Exercise_Publication_Failure ("publication-no-match");
   Work.State := Quality_Manager.Model.Published;
   Quality_Manager.Dispatch.Publish_Approved
     (Store, Planner, Work, Approval, 50, Published, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "publication replay is idempotent");
   Quality_Manager.Integrations.Runner.Initialize (Runner, "./bin/qm_adapter_fixture");
   declare
      Stale_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
      Stale_Mapping : Quality_Manager.Storage.Schema.Dispatch := Published;
   begin
      Stale_Work.Work_Id := To_Unbounded_String ("work:publication-stale");
      Stale_Work.Global_Remediation := To_Unbounded_String ("remediation:publication-stale");
      Stale_Work.Planned_Source_Fingerprint := To_Unbounded_String ("obsolete-source");
      Stale_Mapping.Dispatch_Id := To_Unbounded_String ("dispatch:publication-stale");
      Stale_Mapping.Work_Id := Stale_Work.Work_Id;
      Stale_Mapping.Logical_Remediation := Stale_Work.Global_Remediation;
      Quality_Manager.Storage.Records.Save (Store, Stale_Work, Result);
      Quality_Manager.Dispatch.Bind_Published_Task (Store, Stale_Mapping, Result);
      Quality_Manager.Dispatch.Execute_Persisted
        (Store, Runner, "work:publication-stale", "coordinator:publication", 50, 100, 60,
         Snapshot, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Not_Ready,
         "published work cannot bypass durable scheduler queueing");
      Quality_Manager.Dispatch.Queue_Persisted
        (Store, Runner, "work:publication-stale", Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Stale_Evidence,
         "native source drift is rejected before queueing");
   end;
   Quality_Manager.Dispatch.Queue_Persisted
     (Store, Runner, "work:publication", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "published work is durably queued");
   Quality_Manager.Dispatch.Execute_Persisted
     (Store, Runner, "work:publication", "coordinator:publication", 50, 100, 60,
      Snapshot, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Snapshot.State = Quality_Manager.Integrations.Runner.Awaiting_Integration_State,
      "published mapping is reconstructed and executed from durable state: "
      & Quality_Manager.Results.Message (Result));
   Quality_Manager.Storage.Read (Store, "work:publication", Loaded, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then To_String (Loaded.State) = Quality_Manager.Model.Awaiting_Integration'Image,
      "native execution advances durable work to independent integration");
   Quality_Manager.Dispatch.Execute_Persisted
     (Store, Runner, "work:publication", "coordinator:publication", 60, 110, 60,
      Snapshot, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Not_Ready,
      "completed native execution cannot be dispatched twice");
   Quality_Manager.Dispatch.Integrate_Persisted
     (Store, Runner, "work:publication", "coordinator:publication", 60, 120,
      Snapshot, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then To_String (Snapshot.Workspace_State) = "integrated",
      "persisted native workspace is integrated through model_runner");
   Quality_Manager.Storage.Read (Store, "work:publication", Loaded, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then To_String (Loaded.State) = Quality_Manager.Model.Awaiting_Assessment'Image,
      "integrated remediation requires fresh independent assessment");
   Quality_Manager.Dispatch.Integrate_Persisted
     (Store, Runner, "work:publication", "coordinator:publication", 70, 130,
      Snapshot, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Not_Ready,
      "integrated workspace cannot be taken in twice");
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Authorized_Publication;

