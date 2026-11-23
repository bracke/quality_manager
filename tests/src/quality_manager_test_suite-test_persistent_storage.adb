separate (Quality_Manager_Test_Suite)
procedure Test_Persistent_Storage (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path      : constant String := "/tmp/quality-manager-phase2.database";
   Nested_Root : constant String := "/tmp/quality-manager-parent-creation";
   Nested_Path : constant String := Nested_Root & "/nested/coordinator.database";
   Crash_Path  : constant String := "/tmp/quality-manager-crash-recovery.database";
   Fixture_Path : constant String :=
     (if Ada.Directories.Exists (Ada.Directories.Current_Directory & "/tests/bin/qm_adapter_fixture")
      then Ada.Directories.Current_Directory & "/tests/bin/qm_adapter_fixture"
      else Ada.Directories.Current_Directory & "/bin/qm_adapter_fixture");
   Store     : Quality_Manager.Storage.Store;
   Contender : Quality_Manager.Storage.Store;
   Crash_Store : Quality_Manager.Storage.Store;
   Result    : Quality_Manager.Results.Operation_Result;
   Work      : Quality_Manager.Storage.Stored_Entity :=
     (Internal_Id => 1,
      Kind => Quality_Manager.Storage.Work_Item_Record,
      Entity_Key => To_Unbounded_String ("work:test"),
      State => To_Unbounded_String (Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Discovered)),
      Payload => To_Unbounded_String ("finding=AQ-01"),
      Terminal => False,
      Generation => 1);
   Loaded    : Quality_Manager.Storage.Stored_Entity;
   Identity  : Unbounded_String;
   Recovery  : Quality_Manager.Storage.Entity_Vectors.Vector;

   procedure Remove (Name : String) is
   begin
      if Ada.Directories.Exists (Name) then
         Ada.Directories.Delete_File (Name);
      end if;
   end Remove;

   procedure Cleanup is
   begin
      Remove (Path);
      Remove (Path & ".wal");
      Remove (Path & ".journal");
      Remove (Path & ".lock");
      Remove (Crash_Path);
      Remove (Crash_Path & ".wal");
      Remove (Crash_Path & ".journal");
      Remove (Crash_Path & ".lock");
   end Cleanup;

begin
   if Ada.Directories.Exists (Nested_Root) then
      Ada.Directories.Delete_Tree (Nested_Root);
   end if;
   Quality_Manager.Storage.Open (Store, Nested_Path, True, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success,
      "writable store creates its configured parent path: " & Quality_Manager.Results.Message (Result));
   Assert (Ada.Directories.Exists (Nested_Path), "nested coordinator database was created");
   Quality_Manager.Storage.Close (Store, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "nested coordinator database closes");
   Ada.Directories.Delete_Tree (Nested_Root);

   Cleanup;
   declare
      Request  : Quality_Manager.Integrations.Processes.Request;
      Response : Quality_Manager.Integrations.Processes.Execution_Result;
   begin
      Request.Executable := To_Unbounded_String (Fixture_Path);
      Request.Arguments.Append (To_Unbounded_String ("coordinator-crash"));
      Request.Arguments.Append (To_Unbounded_String (Crash_Path));
      Request.Timeout_Seconds := 10;
      Request.Output_Limit := 4_096;
      Quality_Manager.Integrations.Processes.Execute (Request, Response);
Assert (Response.Started,
         "crash fixture terminates without finalizing the coordinator store");
      Assert (not Response.Timed_Out,
         "crash fixture terminates without finalizing the coordinator store");
      Assert (Response.Exit_Status = 77,
         "crash fixture terminates without finalizing the coordinator store");
   end;
   Quality_Manager.Storage.Open (Crash_Store, Crash_Path, True, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success,
      "coordinator database reopens after abrupt process termination: " &
        Quality_Manager.Results.Message (Result));
   Quality_Manager.Storage.Recovery_Entries (Crash_Store, Recovery, 10, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "prepared journal intent survives abrupt process termination");
   Assert (Natural (Recovery.Length) = 1,
      "prepared journal intent survives abrupt process termination");
   Assert (To_String (Recovery.First_Element.State) =
        Quality_Manager.Journal.Journal_State'Image (Quality_Manager.Journal.Prepared),
      "prepared journal intent survives abrupt process termination");
   Quality_Manager.Storage.Close (Crash_Store, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "recovered crash database closes");
   Cleanup;

   Assert
     (Quality_Manager.Maintenance.Due_Reason
        ((Assessment_Run => 4, Assessment_Complete => True,
          Previous_Source => To_Unbounded_String ("source-a"),
          Current_Source => To_Unbounded_String ("source-b"),
          Previous_Policy => To_Unbounded_String ("policy"),
          Current_Policy => To_Unbounded_String ("policy"),
          Previous_Toolchain => To_Unbounded_String ("toolchain"),
          Current_Toolchain => To_Unbounded_String ("toolchain"), Refresh_Due => False))
      = Quality_Manager.Maintenance.Source_Changed,
      "source identity changes make authoritative assessment due");
   Assert
     (not Quality_Manager.Maintenance.Assessment_Due
        ((Assessment_Run => 4, Assessment_Complete => True,
          Previous_Source => To_Unbounded_String ("source"),
          Current_Source => To_Unbounded_String ("source"),
          Previous_Policy => To_Unbounded_String ("policy"),
          Current_Policy => To_Unbounded_String ("policy"),
          Previous_Toolchain => To_Unbounded_String ("toolchain"),
          Current_Toolchain => To_Unbounded_String ("toolchain"), Refresh_Due => False)),
      "compatible current evidence is reusable");
   declare
      Evidence : Quality_Manager.Maintenance.Evidence_Identity :=
        (Assessment_Run => 0, Assessment_Complete => True,
         Previous_Source => To_Unbounded_String ("source"),
         Current_Source => To_Unbounded_String ("source"),
         Previous_Policy => To_Unbounded_String ("policy"),
         Current_Policy => To_Unbounded_String ("policy"),
         Previous_Toolchain => To_Unbounded_String ("toolchain"),
         Current_Toolchain => To_Unbounded_String ("toolchain"),
         Refresh_Due => False);
   begin
      Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                Quality_Manager.Maintenance.No_Assessment,
              "missing assessment is due");
      Evidence.Assessment_Run := 1;
      Evidence.Assessment_Complete := False;
      Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                Quality_Manager.Maintenance.Evidence_Incomplete,
              "incomplete assessment is due");
      Evidence.Assessment_Complete := True;
      Evidence.Current_Policy := To_Unbounded_String ("changed-policy");
      Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                Quality_Manager.Maintenance.Policy_Changed,
              "policy change is due");
      Evidence.Current_Policy := Evidence.Previous_Policy;
      Evidence.Current_Toolchain := To_Unbounded_String ("changed-toolchain");
      Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                Quality_Manager.Maintenance.Toolchain_Changed,
              "toolchain change is due");
      Evidence.Current_Toolchain := Evidence.Previous_Toolchain;
      Evidence.Refresh_Due := True;
      Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                Quality_Manager.Maintenance.Scheduled_Refresh,
              "scheduled refresh is due");
   end;
   Cleanup;
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "persistent store created: " &
           Quality_Manager.Results.Message (Result));
   Identity := To_Unbounded_String (Quality_Manager.Storage.Identity (Store));
   Assert (Length (Identity) > 0, "store has durable installation identity");

   declare
      Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
      Typed_Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        (Work_Id => To_Unbounded_String ("work:typed"),
         Global_Remediation => To_Unbounded_String ("remediation:AQ-02"),
         Project => Project,
         Origin => Quality_Manager.Model.Maintenance,
         Finding_Identities => To_Unbounded_String ("AQ-02"),
         Priority => 10,
         Baseline_Assessment_Run => 0,
         Improve_Plan_Id => Null_Unbounded_String,
         Improve_Revision => 0,
         Improve_Task_Id => Null_Unbounded_String,
         Improve_Content_SHA256 => Null_Unbounded_String,
         Planned_Source_Fingerprint => Null_Unbounded_String,
         Effective_Policy_Digest => Null_Unbounded_String,
         State => Quality_Manager.Model.Discovered,
         Outcome => Quality_Manager.Model.No_Outcome);
      Dispatch : Quality_Manager.Storage.Schema.Dispatch :=
        (Dispatch_Id => To_Unbounded_String ("dispatch:one"),
         Work_Id => To_Unbounded_String ("work:typed"),
         Logical_Remediation => To_Unbounded_String ("remediation:AQ-02"),
         Improve_Task =>
           (Plan_Id => To_Unbounded_String ("plan-1"), Revision => 1,
            Task_Id => To_Unbounded_String ("task-1")),
         Native_Task_Id => To_Unbounded_String ("native-1"),
         Authorization_Id => To_Unbounded_String ("approval-1"),
         State => Quality_Manager.Model.Published,
         Active => True);
   begin
      Quality_Manager.Storage.Records.Save (Store, Typed_Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "typed work operation persisted");
      Quality_Manager.Storage.Records.Save (Store, Dispatch, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "active dispatch persisted");
      Dispatch.Dispatch_Id := To_Unbounded_String ("dispatch:two");
      Dispatch.Native_Task_Id := To_Unbounded_String ("native-2");
      Quality_Manager.Storage.Records.Save (Store, Dispatch, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Integrity_Error,
         "second active dispatch for logical remediation is rejected");
      Dispatch.Active := False;
      Quality_Manager.Storage.Records.Save (Store, Dispatch, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "inactive dispatch history is retained");
      declare
         Invalid_Attempt : constant Quality_Manager.Storage.Schema.Attempt :=
           (Attempt => 0,
            Attempt_Number => 1,
            Dispatch_Id => Dispatch.Dispatch_Id,
            Execution_Identity => To_Unbounded_String ("execution:invalid"),
            Started_At => 0,
            Finished_At => 0,
            Timeout_Seconds => 1,
            Outcome => Quality_Manager.Model.No_Outcome);
      begin
         Quality_Manager.Storage.Records.Save (Store, Invalid_Attempt, Result);
         Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "zero attempt identity is rejected");
      end;
   end;

   Quality_Manager.Storage.Put (Store, Work, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "work persisted");
   Quality_Manager.Storage.Put (Store, Work, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "same work insert is idempotent");
   Work.Payload := To_Unbounded_String ("finding=different");
   Quality_Manager.Storage.Put (Store, Work, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "conflicting identity is rejected");
   Work.Payload := To_Unbounded_String ("finding=AQ-01");

   Quality_Manager.Storage.Transition_Work
     (Store, "work:test", Quality_Manager.Model.Discovered, Quality_Manager.Model.Planning,
      "event:test:planning", "test", "assessment:1", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "transition and event committed");
   Quality_Manager.Storage.Read (Store, "work:test", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "new work state persisted");
   Assert (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Planning),
      "new work state persisted");
   Quality_Manager.Storage.Read (Store, "event:test:planning", Loaded, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "transition event persisted atomically");
   Assert (Loaded.Kind = Quality_Manager.Storage.Event_Record,
      "transition event persisted atomically");
   Quality_Manager.Storage.Transition_Work
     (Store, "work:test", Quality_Manager.Model.Planning, Quality_Manager.Model.Awaiting_Approval,
      "event:test:planning", "duplicate event", "", Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "duplicate event aborts transition");
   Quality_Manager.Storage.Read (Store, "work:test", Loaded, Result);
   Assert
     (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Planning),
      "failed transaction leaves work state unchanged");

   Quality_Manager.Storage.Acquire_Lease (Store, "project:7", "owner-a", 0, 1, 100, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "initial lease acquired");
   Quality_Manager.Storage.Acquire_Lease (Store, "project:7", "owner-b", 0, 2, 200, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "obsolete lease generation rejected");
   Quality_Manager.Storage.Acquire_Lease (Store, "project:7", "owner-a", 1, 2, 200, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "current lease generation renewed");

   declare
      Generation : Interfaces.Unsigned_64 := 0;
   begin
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "coordinator", "owner-a", 100, 200, Generation, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "exclusive coordinator lease acquired");
      Assert (Generation = 1,
         "exclusive coordinator lease acquired");
      Quality_Manager.Storage.Open (Contender, Path, True, Result);
      if Result.Kind = Quality_Manager.Results.Success then
         Quality_Manager.Storage.Acquire_Exclusive_Lease
           (Contender, "coordinator", "owner-b", 150, 250, Generation, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Authorization_Required,
            "competing coordinator is rejected while the lease is active");
      else
         Assert
           (Result.Kind = Quality_Manager.Results.Temporarily_Unavailable,
            "database lock rejects a competing coordinator: " & Quality_Manager.Results.Message (Result));
      end if;
      Quality_Manager.Storage.Release_Lease
        (Store, "coordinator", "owner-a", 0, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Authorization_Required,
         "obsolete coordinator generation cannot release a lease");
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "coordinator", "owner-b", 201, 300, Generation, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "expired coordinator lease is recovered with a new fencing generation");
      Assert (Generation = 2,
         "expired coordinator lease is recovered with a new fencing generation");
      Quality_Manager.Storage.Release_Lease
        (Store, "coordinator", "owner-a", 1, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Authorization_Required,
         "previous coordinator cannot release the recovered lease");
      Quality_Manager.Storage.Release_Lease
        (Store, "coordinator", "owner-b", Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "current coordinator releases its lease");
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "coordinator", "owner-c", 202, 350, Generation, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "released coordinator lease is immediately reusable");
      Assert (Generation = 3,
         "released coordinator lease is immediately reusable");
      Quality_Manager.Storage.Release_Lease
        (Store, "coordinator", "owner-c", Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "recovered coordinator lease releases cleanly");
      for Attempt in 1 .. 128 loop
         Quality_Manager.Storage.Acquire_Exclusive_Lease
           (Store, "coordinator", "stress-owner", Interfaces.Unsigned_64 (Attempt),
            Interfaces.Unsigned_64 (Attempt + 60), Generation, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "lease stress acquisition succeeds");
         Quality_Manager.Storage.Release_Lease
           (Store, "coordinator", "stress-owner", Generation, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "lease stress release succeeds");
      end loop;
      if Quality_Manager.Storage.Is_Open (Contender) then
         Quality_Manager.Storage.Close (Contender, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "competing coordinator store closes");
      end if;
   end;

   Quality_Manager.Storage.Prepare_Operation
     (Store, 10, "assessment", "run authoritative check", "aq:operation-10", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "journal intent prepared");
   Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "prepared operation reconstructed for recovery");
   Assert (Natural (Recovery.Length) = 1,
      "prepared operation reconstructed for recovery");
   Quality_Manager.Storage.Advance_Operation
     (Store, 10, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
      "aq:operation-10", "", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "journal invocation recorded");
   Quality_Manager.Storage.Advance_Operation
     (Store, 10, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
      "aq:operation-10", "completed externally", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "journal reconciliation recorded");
   Quality_Manager.Storage.Advance_Operation
     (Store, 10, Quality_Manager.Journal.Reconciling, Quality_Manager.Journal.Committed,
      "aq:operation-10", "adopted", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "journal completion recorded");
   Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "committed operation excluded from recovery");
   Assert (Recovery.Is_Empty,
      "committed operation excluded from recovery");
   Quality_Manager.Storage.Advance_Operation
     (Store, 10, Quality_Manager.Journal.Committed, Quality_Manager.Journal.Invoking,
      "aq:operation-10", "", Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "terminal journal cannot reopen");
   Quality_Manager.Storage.Prepare_Operation
     (Store, 11, "publication", "publish authorized task", "improve:operation-11", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "interrupted operation prepared");

   Quality_Manager.Storage.Close (Store, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "store closed");
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "store reopened: " &
           Quality_Manager.Results.Message (Result));
   Assert (Quality_Manager.Storage.Identity (Store) = To_String (Identity), "store identity survives reopen");
   Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "interrupted operation reconstructed after restart");
   Assert (Natural (Recovery.Length) = 1,
      "interrupted operation reconstructed after restart");
   Quality_Manager.Storage.Advance_Operation
     (Store, 11, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
      "improve:operation-11", "", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "recovered prepared operation advances");
   Quality_Manager.Storage.Close (Store, Result);
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
Assert (Natural (Recovery.Length) = 1,
      "invoking boundary survives restart without reinvocation");
   Assert (To_String (Recovery.First_Element.State)
        = Quality_Manager.Journal.Journal_State'Image (Quality_Manager.Journal.Invoking),
      "invoking boundary survives restart without reinvocation");
   Quality_Manager.Storage.Advance_Operation
     (Store, 11, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
      "improve:operation-11", "external result found", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "recovered invocation enters reconciliation");
   Quality_Manager.Storage.Close (Store, Result);
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
Assert (Natural (Recovery.Length) = 1,
      "reconciling boundary survives restart for adoption");
   Assert (To_String (Recovery.First_Element.State)
        = Quality_Manager.Journal.Journal_State'Image (Quality_Manager.Journal.Reconciling),
      "reconciling boundary survives restart for adoption");
   Quality_Manager.Storage.Advance_Operation
     (Store, 11, Quality_Manager.Journal.Reconciling, Quality_Manager.Journal.Committed,
      "improve:operation-11", "adopted", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "recovered result committed");
   Quality_Manager.Storage.Read (Store, "work:test", Loaded, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "work survives reopen");
   Quality_Manager.Storage.Close (Store, Result);
   Quality_Manager.Storage.Open (Store, Path, False, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "read-only status store opened");
   Quality_Manager.Storage.Put (Store, Work, Result);
   Assert (Result.Kind = Quality_Manager.Results.Authorization_Required, "read-only store rejects mutation");
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Crash_Store, Result);
      Quality_Manager.Storage.Close (Contender, Result);
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Persistent_Storage;

