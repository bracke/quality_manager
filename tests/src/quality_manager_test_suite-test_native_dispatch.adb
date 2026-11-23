separate (Quality_Manager_Test_Suite)
procedure Test_Native_Dispatch (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path     : constant String := "/tmp/quality-manager-native-dispatch.database";
   Store    : Quality_Manager.Storage.Store;
   Runner   : Quality_Manager.Integrations.Runner.Adapter;
   Result   : Quality_Manager.Results.Operation_Result;
   Snapshot : Quality_Manager.Integrations.Runner.Task_Snapshot;
   Loaded   : Quality_Manager.Storage.Stored_Entity;
   Request  : constant Quality_Manager.Integrations.Runner.Execution_Request :=
     (Project_Path                => To_Unbounded_String ("/project"),
      Task_Id                     => To_Unbounded_String ("TASK-001"),
      Operation_Id                => To_Unbounded_String ("qm-execution-1"),
      Expected_Task_Revision      => To_Unbounded_String ("task-revision"),
      Expected_Project_Identity   => To_Unbounded_String ("project-identity"),
      Expected_Source_Fingerprint => To_Unbounded_String ("source-fingerprint"),
      Execution_Policy            => To_Unbounded_String ("policy-fingerprint"),
      Timeout_Seconds             => 60);
   Mapping  : constant Quality_Manager.Storage.Schema.Dispatch :=
     (Dispatch_Id         => To_Unbounded_String ("dispatch:runner"),
      Work_Id             => To_Unbounded_String ("work:runner"),
      Logical_Remediation => To_Unbounded_String ("remediation:runner"),
      Improve_Task        =>
        (Plan_Id  => To_Unbounded_String ("PLAN-001"),
         Revision => 1,
         Task_Id  => To_Unbounded_String ("IMP-001")),
      Native_Task_Id      => To_Unbounded_String ("TASK-001"),
      Authorization_Id    => To_Unbounded_String ("approval-1"),
      State               => Quality_Manager.Model.Published,
      Active              => True);
   Project : constant Quality_Manager.Identities.Project_Key :=
     (Quality_Database_Id => To_Unbounded_String ("database:dispatch-boundary"),
      Quality_Project_Id => 7,
      Canonical_Path => To_Unbounded_String ("/project"));

   function Boundary_Work
     (Name   : String;
      State  : Quality_Manager.Model.Work_State;
      Source : String) return Quality_Manager.Storage.Schema.Work_Item is
     ((Work_Id => To_Unbounded_String ("work:" & Name),
       Global_Remediation => To_Unbounded_String ("remediation:" & Name),
       Project => Project,
       Origin => Quality_Manager.Model.Maintenance,
       Finding_Identities => To_Unbounded_String ("AQ-BOUNDARY"),
       Priority => 1,
       Baseline_Assessment_Run => 1,
       Improve_Plan_Id => To_Unbounded_String ("PLAN-001"),
       Improve_Revision => 1,
       Improve_Task_Id => To_Unbounded_String ("IMP-001"),
       Improve_Content_SHA256 => To_Unbounded_String ("content"),
       Planned_Source_Fingerprint => To_Unbounded_String (Source),
       Effective_Policy_Digest => To_Unbounded_String ("policy-fingerprint"),
       State => State,
       Outcome => Quality_Manager.Model.No_Outcome));

   function Boundary_Mapping
     (Name        : String;
      Work_Id     : String;
      Native_Task : String := "TASK-001") return Quality_Manager.Storage.Schema.Dispatch is
     ((Dispatch_Id => To_Unbounded_String ("dispatch:" & Name),
       Work_Id => To_Unbounded_String (Work_Id),
       Logical_Remediation => To_Unbounded_String ("remediation:" & Name),
       Improve_Task =>
         (Plan_Id => To_Unbounded_String ("PLAN-001"),
          Revision => 1,
          Task_Id => To_Unbounded_String ("IMP-001")),
       Native_Task_Id => To_Unbounded_String (Native_Task),
       Authorization_Id => To_Unbounded_String ("approval:" & Name),
       State => Quality_Manager.Model.Published,
       Active => True));

   procedure Persist_Boundary
     (Name         : String;
      State        : Quality_Manager.Model.Work_State;
      Source       : String;
      Native_Task  : String := "TASK-001";
      Mapping_Work : String := "") is
      Work : constant Quality_Manager.Storage.Schema.Work_Item := Boundary_Work (Name, State, Source);
      Published : constant Quality_Manager.Storage.Schema.Dispatch :=
        Boundary_Mapping
          (Name, (if Mapping_Work = "" then "work:" & Name else Mapping_Work), Native_Task);
   begin
      Quality_Manager.Storage.Records.Save (Store, Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "boundary work persisted: " & Name);
      Quality_Manager.Storage.Records.Save (Store, Published, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "boundary dispatch persisted: " & Name);
   end Persist_Boundary;

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
   Assert (Result.Kind = Quality_Manager.Results.Success, "native dispatch store opened");
   for State in Quality_Manager.Integrations.Runner.Execution_State loop
      declare
         Coordinator : constant Quality_Manager.Model.Work_State :=
           Quality_Manager.Dispatch.Coordinator_State (State);
         Expected : constant Quality_Manager.Model.Work_State :=
           (case State is
               when Quality_Manager.Integrations.Runner.Not_Ready_State
                  | Quality_Manager.Integrations.Runner.Blocked_State => Quality_Manager.Model.Blocked,
               when Quality_Manager.Integrations.Runner.Ready_State => Quality_Manager.Model.Queued,
               when Quality_Manager.Integrations.Runner.Executing_State => Quality_Manager.Model.Executing,
               when Quality_Manager.Integrations.Runner.Awaiting_Integration_State =>
                  Quality_Manager.Model.Awaiting_Integration,
               when Quality_Manager.Integrations.Runner.Verifying_State
                  | Quality_Manager.Integrations.Runner.Completed_State =>
                  Quality_Manager.Model.Awaiting_Assessment,
               when Quality_Manager.Integrations.Runner.Failed_State => Quality_Manager.Model.Failed,
               when Quality_Manager.Integrations.Runner.Cancelled_State => Quality_Manager.Model.Cancelled);
      begin
         Assert
           (Coordinator = Expected,
            "every native state has an explicit coordinator state");
      end;
   end loop;
   declare
      Invalid_Mapping : Quality_Manager.Storage.Schema.Dispatch := Mapping;
   begin
      Invalid_Mapping.Active := False;
      Quality_Manager.Dispatch.Bind_Published_Task (Store, Invalid_Mapping, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "inactive published mapping is rejected");
      Invalid_Mapping.Active := True;
      Invalid_Mapping.Native_Task_Id := Null_Unbounded_String;
      Quality_Manager.Dispatch.Bind_Published_Task (Store, Invalid_Mapping, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "incomplete published mapping is rejected");
   end;
   Quality_Manager.Dispatch.Bind_Published_Task (Store, Mapping, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "published native mapping retained exactly");
   Quality_Manager.Integrations.Runner.Initialize (Runner, "./bin/qm_adapter_fixture");

   Quality_Manager.Dispatch.Queue_Persisted (Store, Runner, "work:missing", Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing published work is explicit");
   Persist_Boundary ("wrong-state", Quality_Manager.Model.Planning, "candidate-source");
   Quality_Manager.Dispatch.Queue_Persisted (Store, Runner, "work:wrong-state", Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready, "nonpublished work is not queueable");
   Persist_Boundary ("missing-source", Quality_Manager.Model.Published, "");
   Quality_Manager.Dispatch.Queue_Persisted (Store, Runner, "work:missing-source", Result);
   Assert (Result.Kind = Quality_Manager.Results.Stale_Evidence, "missing planned source blocks queueing");
   declare
      Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        Boundary_Work ("missing-mapping", Quality_Manager.Model.Published, "candidate-source");
   begin
      Quality_Manager.Storage.Records.Save (Store, Work, Result);
      Quality_Manager.Dispatch.Queue_Persisted (Store, Runner, "work:missing-mapping", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing publication mapping blocks queueing");
   end;
   Persist_Boundary
     ("mapping-drift", Quality_Manager.Model.Published, "candidate-source",
      Mapping_Work => "work:different");
   Quality_Manager.Dispatch.Queue_Persisted (Store, Runner, "work:mapping-drift", Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "publication mapping drift is rejected");
   Persist_Boundary
     ("native-task-drift", Quality_Manager.Model.Published, "candidate-source", "TASK-OTHER");
   Quality_Manager.Dispatch.Queue_Persisted (Store, Runner, "work:native-task-drift", Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "native task drift is rejected");
   Persist_Boundary ("source-drift", Quality_Manager.Model.Published, "different-source");
   Quality_Manager.Dispatch.Queue_Persisted (Store, Runner, "work:source-drift", Result);
   Assert (Result.Kind = Quality_Manager.Results.Stale_Evidence, "native source drift is rejected");

   Quality_Manager.Dispatch.Execute_Persisted
     (Store, Runner, "", "owner", 10, 20, 60, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty persisted execution identity is rejected");
   Quality_Manager.Dispatch.Execute_Persisted
     (Store, Runner, "work:wrong-state", "owner", 10, 20, 60, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready, "nonqueued work cannot execute");
   declare
      Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        Boundary_Work ("execute-missing-source", Quality_Manager.Model.Queued, "");
   begin
      Quality_Manager.Storage.Records.Save (Store, Work, Result);
      Quality_Manager.Dispatch.Execute_Persisted
        (Store, Runner, "work:execute-missing-source", "owner", 10, 20, 60, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Stale_Evidence,
              "queued work without assessed source cannot execute");
   end;
   Persist_Boundary ("execute-map-drift", Quality_Manager.Model.Queued, "candidate-source",
                     Mapping_Work => "work:different");
   Quality_Manager.Dispatch.Execute_Persisted
     (Store, Runner, "work:execute-map-drift", "owner", 10, 20, 60, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
           "persisted execution rejects publication mapping drift");
   Persist_Boundary
     ("execute-task-drift", Quality_Manager.Model.Queued, "candidate-source", "TASK-OTHER");
   Quality_Manager.Dispatch.Execute_Persisted
     (Store, Runner, "work:execute-task-drift", "owner", 10, 20, 60, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
           "persisted execution rejects native task drift");
   Persist_Boundary ("execute-source-drift", Quality_Manager.Model.Queued, "different-source");
   Quality_Manager.Dispatch.Execute_Persisted
     (Store, Runner, "work:execute-source-drift", "owner", 10, 20, 60, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Stale_Evidence,
           "persisted execution rejects native source drift");
   declare
      procedure Exercise_Execution_Outcome
        (Name           : String;
         Path_Value     : String;
         Expected       : Quality_Manager.Results.Result_Kind;
         Expected_State : Quality_Manager.Model.Work_State) is
         Work : Quality_Manager.Storage.Schema.Work_Item :=
           Boundary_Work (Name, Quality_Manager.Model.Queued, "candidate-source");
         Published : constant Quality_Manager.Storage.Schema.Dispatch :=
           Boundary_Mapping (Name, "work:" & Name);
         Loaded_Work : Quality_Manager.Storage.Schema.Work_Item;
      begin
         Work.Project.Canonical_Path := To_Unbounded_String (Path_Value);
         Quality_Manager.Storage.Records.Save (Store, Work, Result);
         Quality_Manager.Storage.Records.Save (Store, Published, Result);
         Quality_Manager.Dispatch.Execute_Persisted
           (Store, Runner, "work:" & Name, "owner", 10, 100, 60, Snapshot, Result);
         Assert (Result.Kind = Expected, "persisted execution classifies " & Name);
         Quality_Manager.Storage.Decoding.Read_Work (Store, "work:" & Name, Loaded_Work, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
            "persisted execution records the coordinator state for " & Name);
         Assert (Loaded_Work.State = Expected_State,
            "persisted execution records the coordinator state for " & Name);
      end Exercise_Execution_Outcome;
   begin
      Exercise_Execution_Outcome
        ("cancelled-outcome", "/cancelled", Quality_Manager.Results.Interrupted,
         Quality_Manager.Model.Cancelled);
      Exercise_Execution_Outcome
        ("failed-outcome", "/failed", Quality_Manager.Results.Negative_Result,
         Quality_Manager.Model.Failed);
      Exercise_Execution_Outcome
        ("integrated-outcome", "/integrated", Quality_Manager.Results.Success,
         Quality_Manager.Model.Awaiting_Assessment);
      Exercise_Execution_Outcome
        ("invalid-outcome", "/invalid-state", Quality_Manager.Results.Incompatible_Contract,
         Quality_Manager.Model.Executing);
      Exercise_Execution_Outcome
        ("missing-identity-outcome", "/missing-identity",
         Quality_Manager.Results.Incompatible_Contract, Quality_Manager.Model.Queued);
   end;
   declare
      procedure Exercise_Lease_Failure
        (Name       : String;
         Kind       : Quality_Manager.Storage.Record_Kind;
         Lease_Owner : String;
         Payload    : String;
         Generation : Interfaces.Unsigned_64;
         Expected   : Quality_Manager.Results.Result_Kind) is
         Work : Quality_Manager.Storage.Schema.Work_Item :=
           Boundary_Work (Name, Quality_Manager.Model.Queued, "candidate-source");
         Published : constant Quality_Manager.Storage.Schema.Dispatch :=
           Boundary_Mapping (Name, "work:" & Name);
         Path_Value : constant String := "/lease-" & Name;
         Resource : constant String :=
           "project-execution:" &
           Quality_Manager.Identities.Canonical_Digest
             ([Quality_Manager.Identities.Text_Value
                 (To_String (Work.Project.Quality_Database_Id)),
               Quality_Manager.Identities.Number_Value
                 (Interfaces.Unsigned_64 (Work.Project.Quality_Project_Id)),
               Quality_Manager.Identities.Text_Value (Path_Value)]);
         Lease : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Kind,
            Entity_Key => To_Unbounded_String ("lease:" & Resource),
            State => To_Unbounded_String (Lease_Owner),
            Payload => To_Unbounded_String (Payload),
            Terminal => False, Generation => Generation);
      begin
         Work.Project.Canonical_Path := To_Unbounded_String (Path_Value);
         Quality_Manager.Storage.Records.Save (Store, Work, Result);
         Quality_Manager.Storage.Records.Save (Store, Published, Result);
         Quality_Manager.Storage.Put (Store, Lease, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success,
                 "execution lease fixture persists for " & Name);
         Quality_Manager.Dispatch.Execute_Persisted
           (Store, Runner, "work:" & Name, "owner", 10, 100, 60, Snapshot, Result);
         Assert
           (Result.Kind = Expected,
            "execution lease failure is classified for " & Name & ": " &
              Quality_Manager.Results.Result_Kind'Image (Result.Kind));
      end Exercise_Lease_Failure;
   begin
      Exercise_Lease_Failure
        ("wrong-lease-kind", Quality_Manager.Storage.Project_Record,
         "owner", "100", 1, Quality_Manager.Results.Integrity_Error);
      Exercise_Lease_Failure
        ("malformed-lease", Quality_Manager.Storage.Lease_Record,
         "owner", "not-a-time", 1, Quality_Manager.Results.Integrity_Error);
      Exercise_Lease_Failure
        ("owned-lease", Quality_Manager.Storage.Lease_Record,
         "another-owner", "100", 1, Quality_Manager.Results.Not_Ready);
      Exercise_Lease_Failure
        ("exhausted-lease", Quality_Manager.Storage.Lease_Record,
         "owner", "100", Interfaces.Unsigned_64 (Interfaces.Integer_64'Last),
         Quality_Manager.Results.Integrity_Error);
   end;
   declare
      Work : Quality_Manager.Storage.Schema.Work_Item :=
        Boundary_Work ("blocked-native", Quality_Manager.Model.Published, "candidate-source");
      Published : constant Quality_Manager.Storage.Schema.Dispatch :=
        Boundary_Mapping ("blocked-native", "work:blocked-native");
   begin
      Work.Project.Canonical_Path := To_Unbounded_String ("/blocked");
      Quality_Manager.Storage.Records.Save (Store, Work, Result);
      Quality_Manager.Storage.Records.Save (Store, Published, Result);
      Quality_Manager.Dispatch.Queue_Persisted (Store, Runner, "work:blocked-native", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "native readiness blocks queueing before an agent starts");
   end;

   Quality_Manager.Dispatch.Integrate_Persisted
     (Store, Runner, "", "owner", 10, 20, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "empty persisted integration identity is rejected");
   Quality_Manager.Dispatch.Integrate_Persisted
     (Store, Runner, "work:wrong-state", "owner", 10, 20, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
           "work not awaiting integration cannot be integrated");
   declare
      Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        Boundary_Work ("integrate-missing-map", Quality_Manager.Model.Awaiting_Integration,
                       "candidate-source");
   begin
      Quality_Manager.Storage.Records.Save (Store, Work, Result);
      Quality_Manager.Dispatch.Integrate_Persisted
        (Store, Runner, "work:integrate-missing-map", "owner", 10, 20, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "integration requires an active publication mapping");
   end;
   Persist_Boundary
     ("integrate-map-drift", Quality_Manager.Model.Awaiting_Integration, "candidate-source",
      Mapping_Work => "work:different");
   Quality_Manager.Dispatch.Integrate_Persisted
     (Store, Runner, "work:integrate-map-drift", "owner", 10, 20, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
           "integration rejects publication mapping drift");
   Persist_Boundary
     ("integrate-task-drift", Quality_Manager.Model.Awaiting_Integration, "candidate-source", "TASK-OTHER");
   Quality_Manager.Dispatch.Integrate_Persisted
     (Store, Runner, "work:integrate-task-drift", "owner", 10, 20, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
           "integration rejects execution task drift");
   Persist_Boundary
     ("integrate-source-drift", Quality_Manager.Model.Awaiting_Integration, "different-source");
   Quality_Manager.Dispatch.Integrate_Persisted
     (Store, Runner, "work:integrate-source-drift", "owner", 10, 20, Snapshot, Result);
   Assert (Result.Kind = Quality_Manager.Results.Stale_Evidence,
           "integration rejects execution source drift");
   declare
      procedure Exercise_Integration_Lease_Failure
        (Name        : String;
         Kind        : Quality_Manager.Storage.Record_Kind;
         Lease_Owner : String;
         Payload     : String;
         Generation  : Interfaces.Unsigned_64;
         Expected    : Quality_Manager.Results.Result_Kind) is
         Work : Quality_Manager.Storage.Schema.Work_Item :=
           Boundary_Work (Name, Quality_Manager.Model.Awaiting_Integration, "candidate-source");
         Published : constant Quality_Manager.Storage.Schema.Dispatch :=
           Boundary_Mapping (Name, "work:" & Name);
         Path_Value : constant String := "/integration-lease-" & Name;
         Resource : constant String :=
           "project-integration:" &
           Quality_Manager.Identities.Canonical_Digest
             ([Quality_Manager.Identities.Text_Value
                 (To_String (Work.Project.Quality_Database_Id)),
               Quality_Manager.Identities.Number_Value
                 (Interfaces.Unsigned_64 (Work.Project.Quality_Project_Id)),
               Quality_Manager.Identities.Text_Value (Path_Value)]);
         Lease : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Kind,
            Entity_Key => To_Unbounded_String ("lease:" & Resource),
            State => To_Unbounded_String (Lease_Owner),
            Payload => To_Unbounded_String (Payload),
            Terminal => False, Generation => Generation);
      begin
         Work.Project.Canonical_Path := To_Unbounded_String (Path_Value);
         Quality_Manager.Storage.Records.Save (Store, Work, Result);
         Quality_Manager.Storage.Records.Save (Store, Published, Result);
         Quality_Manager.Storage.Put (Store, Lease, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success,
                 "integration lease fixture persists for " & Name);
         Quality_Manager.Dispatch.Integrate_Persisted
           (Store, Runner, "work:" & Name, "owner", 10, 100, Snapshot, Result);
         Assert
           (Result.Kind = Expected,
            "integration lease failure is classified for " & Name & ": " &
              Quality_Manager.Results.Result_Kind'Image (Result.Kind));
      end Exercise_Integration_Lease_Failure;
   begin
      Exercise_Integration_Lease_Failure
        ("integration-wrong-lease-kind", Quality_Manager.Storage.Project_Record,
         "owner", "100", 1, Quality_Manager.Results.Integrity_Error);
      Exercise_Integration_Lease_Failure
        ("integration-malformed-lease", Quality_Manager.Storage.Lease_Record,
         "owner", "not-a-time", 1, Quality_Manager.Results.Integrity_Error);
      Exercise_Integration_Lease_Failure
        ("integration-owned-lease", Quality_Manager.Storage.Lease_Record,
         "another-owner", "100", 1, Quality_Manager.Results.Not_Ready);
      Exercise_Integration_Lease_Failure
        ("integration-exhausted-lease", Quality_Manager.Storage.Lease_Record,
         "owner", "100", Interfaces.Unsigned_64 (Interfaces.Integer_64'Last),
         Quality_Manager.Results.Integrity_Error);
   end;

   Quality_Manager.Dispatch.Execute_Or_Reconcile
     (Store, Runner, 0, "", "", "", 0, 1, 100, Request, Snapshot, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Invalid_Request,
      "incomplete execution coordination identity is rejected");
   Quality_Manager.Dispatch.Execute_Or_Reconcile
     (Store, Runner, 99, "dispatch:runner", "project:invalid", "coordinator:test",
      0, 1, 100, Request, Snapshot, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Invalid_Request,
      "mismatched external operation identity is rejected");
   Quality_Manager.Dispatch.Integrate_Or_Reconcile
     (Store, Runner, 0, "", "", 0, 1, 100, Request, Snapshot, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Invalid_Request,
      "incomplete integration coordination identity is rejected");

   Quality_Manager.Dispatch.Execute_Or_Reconcile
     (Store                     => Store,
      Runner                    => Runner,
      Operation                 => 1,
      Dispatch_Id               => "dispatch:runner",
      Project_Resource          => "project:runner:execution",
      Lease_Owner               => "coordinator:test",
      Expected_Lease_Generation => 0,
      New_Lease_Generation      => 1,
      Lease_Expires_At          => 100,
      Request                   => Request,
      Snapshot                  => Snapshot,
      Result                    => Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "native execution is journaled and independently awaits integration");
   Assert (Snapshot.State = Quality_Manager.Integrations.Runner.Awaiting_Integration_State,
      "native execution is journaled and independently awaits integration");
   Quality_Manager.Storage.Read (Store, "journal:1", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "confirmed native outcome commits the durable journal");
   Assert (To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
        (Quality_Manager.Journal.Committed),
      "confirmed native outcome commits the durable journal");
   Quality_Manager.Storage.Read (Store, "attempt:1", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "native attempt outcome is persisted");
   Assert (Loaded.Kind = Quality_Manager.Storage.Attempt_Record,
      "native attempt outcome is persisted");

   Quality_Manager.Dispatch.Execute_Or_Reconcile
     (Store                     => Store,
      Runner                    => Runner,
      Operation                 => 1,
      Dispatch_Id               => "dispatch:runner",
      Project_Resource          => "project:runner:execution",
      Lease_Owner               => "coordinator:test",
      Expected_Lease_Generation => 0,
      New_Lease_Generation      => 1,
      Lease_Expires_At          => 100,
      Request                   => Request,
      Snapshot                  => Snapshot,
      Result                    => Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success,
      "repeated coordinator recovery adopts status without another execution");

   Quality_Manager.Dispatch.Integrate_Or_Reconcile
     (Store                     => Store,
      Runner                    => Runner,
      Journal_Operation         => 100,
      Project_Resource          => "project:runner:integration",
      Lease_Owner               => "coordinator:test",
      Expected_Lease_Generation => 0,
      New_Lease_Generation      => 1,
      Lease_Expires_At          => 100,
      Request                   => Request,
      Snapshot                  => Snapshot,
      Result                    => Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "native integration is separately leased, journaled, and awaiting independent assessment");
   Assert (To_String (Snapshot.Workspace_State) = "integrated",
      "native integration is separately leased, journaled, and awaiting independent assessment");
   Assert (Quality_Manager.Dispatch.Coordinator_State (Snapshot.State) =
        Quality_Manager.Model.Awaiting_Assessment,
      "native integration is separately leased, journaled, and awaiting independent assessment");
   Quality_Manager.Storage.Read (Store, "journal:100", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "confirmed native integration commits its own durable journal");
   Assert (To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
        (Quality_Manager.Journal.Committed),
      "confirmed native integration commits its own durable journal");

   declare
      Recovery_Request : Quality_Manager.Integrations.Runner.Execution_Request := Request;
   begin
      Recovery_Request.Operation_Id := To_Unbounded_String ("qm-execution-2");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store                     => Store,
         Runner                    => Runner,
         Operation                 => 2,
         Dispatch_Id               => "dispatch:runner",
         Project_Resource          => "project:runner:recovery",
         Lease_Owner               => "coordinator:test",
         Expected_Lease_Generation => 0,
         New_Lease_Generation      => 1,
         Lease_Expires_At          => 100,
         Request                   => Recovery_Request,
         Snapshot                  => Snapshot,
         Result                    => Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Not_Ready,
         "running native operation remains at the invoking recovery boundary");
      Quality_Manager.Storage.Close (Store, Result);
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "dispatch store reopened after interruption");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store                     => Store,
         Runner                    => Runner,
         Operation                 => 2,
         Dispatch_Id               => "dispatch:runner",
         Project_Resource          => "project:runner:recovery",
         Lease_Owner               => "coordinator:test",
         Expected_Lease_Generation => 0,
         New_Lease_Generation      => 1,
         Lease_Expires_At          => 100,
         Request                   => Recovery_Request,
         Snapshot                  => Snapshot,
         Result                    => Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "restart queries durable status instead of executing the agent again");
      Assert (To_String (Snapshot.Audit_Reference) = "status-audit",
         "restart queries durable status instead of executing the agent again");
   end;
   declare
      Terminal_Request : Quality_Manager.Integrations.Runner.Execution_Request := Request;
   begin
      Terminal_Request.Operation_Id := To_Unbounded_String ("qm-execution-4");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 4, "dispatch:runner", "project:runner:cancelled",
         "coordinator:test", 0, 1, 100, Terminal_Request, Snapshot, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Interrupted,
         "cancelled native execution is recorded as interrupted");
      Terminal_Request.Operation_Id := To_Unbounded_String ("qm-execution-5");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 5, "dispatch:runner", "project:runner:failed",
         "coordinator:test", 0, 1, 100, Terminal_Request, Snapshot, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Negative_Result,
         "failed native execution remains a negative workflow outcome");
   end;
   declare
      Changed : Quality_Manager.Integrations.Runner.Execution_Request := Request;
   begin
      Changed.Execution_Policy := To_Unbounded_String ("another-policy");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 1, "dispatch:runner", "project:runner:execution",
         "coordinator:test", 0, 1, 100, Changed, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "a durable operation cannot be rebound to changed execution intent");
   end;
   declare
      Interrupted_Request : Quality_Manager.Integrations.Runner.Execution_Request := Request;
   begin
      Interrupted_Request.Operation_Id := To_Unbounded_String ("qm-execution-6");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 6, "dispatch:runner", "project:runner:aborted",
         "coordinator:test", 0, 1, 100, Interrupted_Request, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "an executing operation retains its invoking journal state");
      Quality_Manager.Storage.Advance_Operation
        (Store, 6, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Aborted,
         "qm-execution-6", "operator aborted execution", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "test execution journal aborted");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 6, "dispatch:runner", "project:runner:aborted",
         "coordinator:test", 0, 1, 100, Interrupted_Request, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Negative_Result,
              "aborted native operation remains terminal on replay");

      Interrupted_Request.Operation_Id := To_Unbounded_String ("qm-execution-7");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 7, "dispatch:runner", "project:runner:intervention",
         "coordinator:test", 0, 1, 100, Interrupted_Request, Snapshot, Result);
      Quality_Manager.Storage.Advance_Operation
        (Store, 7, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Needs_Intervention,
         "qm-execution-7", "operator review required", Result);
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 7, "dispatch:runner", "project:runner:intervention",
         "coordinator:test", 0, 1, 100, Interrupted_Request, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "intervention journal cannot be replayed automatically");
   end;
   declare
      Wrong_Kind : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Project_Record,
         Entity_Key => To_Unbounded_String ("journal:8"),
         State => To_Unbounded_String ("PREPARED"), Payload => Null_Unbounded_String,
         Terminal => False, Generation => 1);
      Invalid_Request : Quality_Manager.Integrations.Runner.Execution_Request := Request;
   begin
      Quality_Manager.Storage.Put (Store, Wrong_Kind, Result);
      Invalid_Request.Operation_Id := To_Unbounded_String ("qm-execution-8");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 8, "dispatch:runner", "project:runner:wrong-kind",
         "coordinator:test", 0, 1, 100, Invalid_Request, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "journal key with the wrong record kind is rejected");
   end;
   declare
      Pending : Quality_Manager.Integrations.Runner.Execution_Request := Request;
   begin
      Pending.Operation_Id := To_Unbounded_String ("qm-execution-8");
      Quality_Manager.Dispatch.Integrate_Or_Reconcile
        (Store, Runner, 108, "project:runner:pending-integration", "coordinator:test",
         0, 1, 100, Pending, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "native workspace pending integration remains recoverable");
      Quality_Manager.Dispatch.Integrate_Or_Reconcile
        (Store, Runner, 108, "project:runner:pending-integration", "coordinator:test",
         0, 1, 100, Pending, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "integration recovery queries and re-enters only the native operation");
   end;
   declare
      Changed : Quality_Manager.Integrations.Runner.Execution_Request := Request;
   begin
      Changed.Operation_Id := To_Unbounded_String ("qm-execution-9");
      Changed.Execution_Policy := To_Unbounded_String ("changed-policy");
      Quality_Manager.Dispatch.Integrate_Or_Reconcile
        (Store, Runner, 109, "project:runner:policy-change", "coordinator:test",
         0, 1, 100, Changed, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "integration policy drift requires intervention");
      Quality_Manager.Dispatch.Integrate_Or_Reconcile
        (Store, Runner, 109, "project:runner:policy-change", "coordinator:test",
         0, 1, 100, Changed, Snapshot, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "intervention remains durable across integration replay");
   end;
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;

   declare
      procedure Exercise_Failure
        (Name     : String;
         Expected : Quality_Manager.Results.Result_Kind) is
         Scenario_Path : constant String := "/tmp/quality-manager-maintenance-" & Name & ".database";
         Scenario_Store : aliased Quality_Manager.Storage.Store;
         Scenario_Scheduler : aliased Quality_Manager.Scheduler.Scheduler_Type;
         Scenario_Quality : Quality_Manager.Integrations.Quality.Adapter;
         Scenario_Planner : Quality_Manager.Integrations.Improve.Adapter;
         Scenario_Runner : Quality_Manager.Integrations.Runner.Adapter;
         Scenario_Context : Quality_Manager.Maintenance.Context;
         Scenario_Result : Quality_Manager.Results.Operation_Result;
      begin
         if Ada.Directories.Exists (Scenario_Path) then
            Ada.Directories.Delete_File (Scenario_Path);
         end if;
         Quality_Manager.Storage.Open (Scenario_Store, Scenario_Path, True, Scenario_Result);
         Assert (Scenario_Result.Kind = Quality_Manager.Results.Success,
                 "maintenance failure store opens: " & Name);
         Quality_Manager.Scheduler.Initialize (Scenario_Scheduler);
         Quality_Manager.Scheduler.Configure
           (Scenario_Scheduler, Scenario_Store'Unchecked_Access, 1, 1);
         Quality_Manager.Integrations.Quality.Initialize
           (Scenario_Quality, "./bin/qm_adapter_fixture", Name & "-quality.db");
         Quality_Manager.Integrations.Improve.Initialize
           (Scenario_Planner, "./bin/qm_adapter_fixture", "improve.toml",
            Name & "-quality.db", "improve.db");
         Quality_Manager.Integrations.Runner.Initialize
           (Scenario_Runner, "./bin/qm_adapter_fixture");
         Quality_Manager.Maintenance.Initialize
           (Scenario_Context, Scenario_Store'Unchecked_Access,
            Scenario_Scheduler'Unchecked_Access, Scenario_Quality, Scenario_Planner,
            Scenario_Runner, 60);
         Quality_Manager.Maintenance.Run_Cycle
           (Scenario_Context, "7", False, Scenario_Result);
         Assert
           (Scenario_Result.Kind = Expected,
            "maintenance failure is classified for " & Name & ": " &
              Quality_Manager.Results.Result_Kind'Image (Scenario_Result.Kind) & " " &
              Quality_Manager.Results.Message (Scenario_Result));
         Quality_Manager.Scheduler.Shutdown (Scenario_Scheduler);
         Quality_Manager.Storage.Close (Scenario_Store, Scenario_Result);
         if Ada.Directories.Exists (Scenario_Path) then
            Ada.Directories.Delete_File (Scenario_Path);
         end if;
      exception
         when others =>  --  AQ: audited exception boundary
            Quality_Manager.Scheduler.Shutdown (Scenario_Scheduler);
            Quality_Manager.Storage.Close (Scenario_Store, Scenario_Result);
            if Ada.Directories.Exists (Scenario_Path) then
               Ada.Directories.Delete_File (Scenario_Path);
            end if;
            raise;
      end Exercise_Failure;
   begin
      Exercise_Failure ("inventory-invalid", Quality_Manager.Results.Invalid_Request);
      Exercise_Failure ("inventory-schema", Quality_Manager.Results.Incompatible_Contract);
      Exercise_Failure ("inventory-project", Quality_Manager.Results.Incompatible_Contract);
      Exercise_Failure ("plan-invalid", Quality_Manager.Results.Success);
      Exercise_Failure ("assessment-invalid", Quality_Manager.Results.Success);
   end;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Native_Dispatch;

