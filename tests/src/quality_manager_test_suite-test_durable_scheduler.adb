separate (Quality_Manager_Test_Suite)
procedure Test_Durable_Scheduler (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path      : constant String := "/tmp/quality-manager-phase7.database";
   Store     : aliased Quality_Manager.Storage.Store;
   Scheduler : Quality_Manager.Scheduler.Scheduler_Type;
   Result    : Quality_Manager.Results.Operation_Result;
   Work_Id   : Unbounded_String;
   Resource  : Quality_Manager.Scheduler.Work_Resource;
   Found     : Boolean;
   Ready     : Boolean;
   Reason    : Unbounded_String;
   Loaded    : Quality_Manager.Storage.Stored_Entity;
   Project_1 : constant Quality_Manager.Identities.Project_Key :=
     (To_Unbounded_String ("database-a"), 1, To_Unbounded_String ("/project/one"));
   Project_2 : constant Quality_Manager.Identities.Project_Key :=
     (To_Unbounded_String ("database-a"), 2, To_Unbounded_String ("/project/two"));
   Work_1 : constant Quality_Manager.Storage.Schema.Work_Item :=
     (Work_Id => To_Unbounded_String ("work:scheduler:one"),
      Global_Remediation => To_Unbounded_String ("remediation:one"),
      Project => Project_1, Origin => Quality_Manager.Model.Maintenance,
      Finding_Identities => To_Unbounded_String ("AQ-01"), Priority => 510,
      Baseline_Assessment_Run => 1,
      Improve_Plan_Id => To_Unbounded_String ("plan-1"), Improve_Revision => 1,
      Improve_Task_Id => To_Unbounded_String ("task-1"), Improve_Content_SHA256 => Null_Unbounded_String,
      Planned_Source_Fingerprint => Null_Unbounded_String,
      Effective_Policy_Digest => Null_Unbounded_String,
      State => Quality_Manager.Model.Queued,
      Outcome => Quality_Manager.Model.No_Outcome);
   Work_2 : constant Quality_Manager.Storage.Schema.Work_Item :=
     (Work_Id => To_Unbounded_String ("work:scheduler:two"),
      Global_Remediation => To_Unbounded_String ("remediation:two"),
      Project => Project_2, Origin => Quality_Manager.Model.Campaign,
      Finding_Identities => To_Unbounded_String ("TST-03"), Priority => 150,
      Baseline_Assessment_Run => 1,
      Improve_Plan_Id => To_Unbounded_String ("plan-2"), Improve_Revision => 1,
      Improve_Task_Id => To_Unbounded_String ("task-2"), Improve_Content_SHA256 => Null_Unbounded_String,
      Planned_Source_Fingerprint => Null_Unbounded_String,
      Effective_Policy_Digest => Null_Unbounded_String,
      State => Quality_Manager.Model.Queued,
      Outcome => Quality_Manager.Model.No_Outcome);

   procedure Cleanup is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Cleanup;
begin
   Quality_Manager.Scheduler.Evaluate_Eligibility
     ((Project_Enabled => True, Project_Identity_Valid => True, Task_Nonterminal => True,
       Dependencies_Satisfied => True, Evidence_Applicable => True, Plan_Current => True,
       Approval_Valid => False, Native_Task_Ready => True, Budget_Available => True,
       Project_Lock_Available => True, Autonomy_Permits => True), Ready, Reason);
   Assert (not Ready and then To_String (Reason) = "approval-missing-or-stale",
           "missing eligibility information is a specific blocked reason");
   Quality_Manager.Scheduler.Evaluate_Eligibility
     ((others => True), Ready, Reason);
   Assert (Ready and then Length (Reason) = 0, "complete eligibility facts are ready");
   declare
      Facts : Quality_Manager.Scheduler.Eligibility_Facts := (others => True);
   begin
      Facts.Native_Task_Ready := False;
      Quality_Manager.Scheduler.Evaluate_Eligibility (Facts, Ready, Reason);
      Assert (To_String (Reason) = "native-task-not-ready", "native readiness fails closed");
      Facts.Native_Task_Ready := True;
      Facts.Budget_Available := False;
      Quality_Manager.Scheduler.Evaluate_Eligibility (Facts, Ready, Reason);
      Assert (To_String (Reason) = "resource-budget-exhausted", "budget eligibility is explicit");
      Facts.Budget_Available := True;
      Facts.Project_Lock_Available := False;
      Quality_Manager.Scheduler.Evaluate_Eligibility (Facts, Ready, Reason);
      Assert (To_String (Reason) = "project-lock-unavailable", "project lock eligibility is explicit");
      Facts.Project_Lock_Available := True;
      Facts.Autonomy_Permits := False;
      Quality_Manager.Scheduler.Evaluate_Eligibility (Facts, Ready, Reason);
      Assert (To_String (Reason) = "authorization-required", "autonomy eligibility is explicit");
   end;

   Quality_Manager.Scheduler.Enqueue_Work
     (Scheduler, "uninitialized", "project:none", Quality_Manager.Priorities.Campaign_Work,
      1, Quality_Manager.Scheduler.Agent_Resource);
   Assert (Quality_Manager.Scheduler.Last_Result (Scheduler).Kind = Quality_Manager.Results.Not_Ready,
           "uninitialized scheduler rejects direct queue insertion");
   Quality_Manager.Scheduler.Take_Next (Scheduler, Work_Id, Resource, Found);
   Assert (not Found and then Quality_Manager.Scheduler.Active_Count
             (Scheduler, Quality_Manager.Scheduler.Agent_Resource) = 0,
           "uninitialized scheduler has no active work");
   Quality_Manager.Scheduler.Dispatch_Due (Scheduler);
   Assert (Quality_Manager.Scheduler.Last_Result (Scheduler).Kind = Quality_Manager.Results.Not_Ready,
           "uninitialized scheduler cannot dispatch");
   Quality_Manager.Scheduler.Initialize (Scheduler);
   Quality_Manager.Scheduler.Enqueue_Work
     (Scheduler, "", "project:none", Quality_Manager.Priorities.Campaign_Work,
      1, Quality_Manager.Scheduler.Agent_Resource);
   Assert (Quality_Manager.Scheduler.Last_Result (Scheduler).Kind = Quality_Manager.Results.Invalid_Request,
           "queued work requires stable identities");
   Quality_Manager.Scheduler.Enqueue_Work
     (Scheduler, "work:low", "project:one", Quality_Manager.Priorities.Campaign_Work,
      1, Quality_Manager.Scheduler.Agent_Resource);
   Quality_Manager.Scheduler.Enqueue_Work
     (Scheduler, "work:critical", "project:two", Quality_Manager.Priorities.Critical_Regression,
      2, Quality_Manager.Scheduler.Agent_Resource);
   Quality_Manager.Scheduler.Take_Next (Scheduler, Work_Id, Resource, Found);
   Assert (Found and then To_String (Work_Id) = "work:critical",
           "critical regressions sort before older campaign work");
   Assert
     (Quality_Manager.Scheduler.Active_Count
        (Scheduler, Quality_Manager.Scheduler.Agent_Resource) = 1,
      "configured scheduler reports its reserved agent capacity");
   Quality_Manager.Scheduler.Take_Next (Scheduler, Work_Id, Resource, Found);
   Assert (not Found, "global agent execution limit is enforced");
   Quality_Manager.Scheduler.Complete (Scheduler, "work:critical");
   Quality_Manager.Scheduler.Take_Next (Scheduler, Work_Id, Resource, Found);
   Assert (Found and then To_String (Work_Id) = "work:low", "released capacity permits the next task");
   Quality_Manager.Scheduler.Request_Stop (Scheduler);
   Assert (Quality_Manager.Scheduler.Is_Stopping (Scheduler), "scheduler stop is cooperative and observable");

   Cleanup;
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "scheduler store opened");
   Quality_Manager.Storage.Records.Save (Store, Work_1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "first queued work persisted");
   Quality_Manager.Storage.Records.Save (Store, Work_2, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "second queued work persisted");
   Quality_Manager.Scheduler.Initialize (Scheduler);
   Quality_Manager.Scheduler.Configure (Scheduler, Store'Unchecked_Access, 4, 1);
   Quality_Manager.Scheduler.Evaluate_And_Queue
     (Scheduler, "work:scheduler:one", (others => True));
   Assert (Quality_Manager.Scheduler.Last_Result (Scheduler).Kind = Quality_Manager.Results.Success,
           "eligible persisted work enters the in-memory queue");
   Quality_Manager.Scheduler.Dispatch_Due (Scheduler);
   Assert
     (Quality_Manager.Scheduler.Last_Result (Scheduler).Kind = Quality_Manager.Results.Success
      and then Quality_Manager.Scheduler.Pending_Count (Scheduler) = 2,
      "restart reconstructs the in-memory queue from committed queued work");
   Quality_Manager.Scheduler.Take_Next (Scheduler, Work_Id, Resource, Found);
   Assert (Found and then To_String (Work_Id) = "work:scheduler:one",
           "persisted priority ordering is deterministic");
   Quality_Manager.Scheduler.Reconcile (Scheduler);
   Assert (Quality_Manager.Scheduler.Pending_Count (Scheduler) = 1,
           "reconciliation does not duplicate active execution");
   Quality_Manager.Scheduler.Evaluate_And_Queue
     (Scheduler, "work:scheduler:two",
      (Project_Enabled => True, Project_Identity_Valid => True, Task_Nonterminal => True,
       Dependencies_Satisfied => True, Evidence_Applicable => True, Plan_Current => True,
       Approval_Valid => False, Native_Task_Ready => True, Budget_Available => True,
       Project_Lock_Available => True, Autonomy_Permits => True));
   Quality_Manager.Storage.Read (Store, "work:scheduler:two", Loaded, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
        (Quality_Manager.Model.Blocked)
      and then Quality_Manager.Scheduler.Pending_Count (Scheduler) = 0,
      "failed eligibility is persisted with no stale queue entry");
   Quality_Manager.Scheduler.Resume (Scheduler);
   Assert (not Quality_Manager.Scheduler.Is_Stopping (Scheduler), "paused scheduling can resume");
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Durable_Scheduler;

