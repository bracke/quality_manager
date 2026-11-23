with Interfaces;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.Runner;
with Quality_Manager.Model;
with Quality_Manager.Results;
with Quality_Manager.Storage;
with Quality_Manager.Storage.Schema;

--  Publishes, executes, and integrates authorized remediation tasks.
package Quality_Manager.Dispatch is
   --  Public contract for this Quality Manager unit.
   function Operation_Name
     (Operation : Quality_Manager.Identities.Operation_Id) return String;
   --  Return Operation Name.
   --  @param Operation Operation.
   --  @return Operation Name result.

   function Coordinator_State
     (State : Quality_Manager.Integrations.Runner.Execution_State)
      return Quality_Manager.Model.Work_State;
   --  Return Coordinator State.
   --  @param State State.
   --  @return Coordinator State result.

   procedure Bind_Published_Task
     (Store    : in out Quality_Manager.Storage.Store;
      Dispatch : Quality_Manager.Storage.Schema.Dispatch;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Bind Published Task.
   --  @param Store Store.
   --  @param Dispatch Dispatch.
   --  @param Result Result.

   procedure Publish_Approved
     (Store     : in out Quality_Manager.Storage.Store;
      Planner   : Quality_Manager.Integrations.Improve.Adapter;
      Work      : Quality_Manager.Storage.Schema.Work_Item;
      Approval  : Quality_Manager.Storage.Schema.Approval;
      Now       : Interfaces.Unsigned_64;
      Published : out Quality_Manager.Storage.Schema.Dispatch;
      Result    : out Quality_Manager.Results.Operation_Result);
   --  Perform Publish Approved.
   --  @param Store Store.
   --  @param Planner Planner.
   --  @param Work Work.
   --  @param Approval Approval.
   --  @param Now Now.
   --  @param Published Published.
   --  @param Result Result.

   procedure Execute_Or_Reconcile
     (Store                     : in out Quality_Manager.Storage.Store;
      Runner                    : Quality_Manager.Integrations.Runner.Adapter;
      Operation                 : Quality_Manager.Identities.Operation_Id;
      Dispatch_Id               : String;
      Project_Resource          : String;
      Lease_Owner               : String;
      Expected_Lease_Generation : Interfaces.Unsigned_64;
      New_Lease_Generation      : Interfaces.Unsigned_64;
      Lease_Expires_At          : Interfaces.Unsigned_64;
      Request                   : Quality_Manager.Integrations.Runner.Execution_Request;
      Snapshot                  : out Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result                    : out Quality_Manager.Results.Operation_Result);
   --  Perform Execute Or Reconcile.
   --  @param Store Store.
   --  @param Runner Runner.
   --  @param Operation Operation.
   --  @param Dispatch_Id Dispatch Id.
   --  @param Project_Resource Project Resource.
   --  @param Lease_Owner Lease Owner.
   --  @param Expected_Lease_Generation Expected Lease Generation.
   --  @param New_Lease_Generation New Lease Generation.
   --  @param Lease_Expires_At Lease Expires At.
   --  @param Request Request.
   --  @param Snapshot Snapshot.
   --  @param Result Result.

   procedure Execute_Persisted
     (Store            : in out Quality_Manager.Storage.Store;
      Runner           : Quality_Manager.Integrations.Runner.Adapter;
      Work_Id          : String;
      Lease_Owner      : String;
      Now              : Interfaces.Unsigned_64;
      Lease_Expires_At : Interfaces.Unsigned_64;
      Timeout_Seconds  : Positive;
      Snapshot         : out Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result           : out Quality_Manager.Results.Operation_Result);
   --  Perform Execute Persisted.
   --  @param Store Store.
   --  @param Runner Runner.
   --  @param Work_Id Work Id.
   --  @param Lease_Owner Lease Owner.
   --  @param Now Now.
   --  @param Lease_Expires_At Lease Expires At.
   --  @param Timeout_Seconds Timeout Seconds.
   --  @param Snapshot Snapshot.
   --  @param Result Result.

   procedure Queue_Persisted
     (Store   : in out Quality_Manager.Storage.Store;
      Runner  : Quality_Manager.Integrations.Runner.Adapter;
      Work_Id : String;
      Result  : out Quality_Manager.Results.Operation_Result);
   --  Perform Queue Persisted.
   --  @param Store Store.
   --  @param Runner Runner.
   --  @param Work_Id Work Id.
   --  @param Result Result.

   procedure Integrate_Persisted
     (Store            : in out Quality_Manager.Storage.Store;
      Runner           : Quality_Manager.Integrations.Runner.Adapter;
      Work_Id          : String;
      Lease_Owner      : String;
      Now              : Interfaces.Unsigned_64;
      Lease_Expires_At : Interfaces.Unsigned_64;
      Snapshot         : out Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result           : out Quality_Manager.Results.Operation_Result);
   --  Perform Integrate Persisted.
   --  @param Store Store.
   --  @param Runner Runner.
   --  @param Work_Id Work Id.
   --  @param Lease_Owner Lease Owner.
   --  @param Now Now.
   --  @param Lease_Expires_At Lease Expires At.
   --  @param Snapshot Snapshot.
   --  @param Result Result.

   procedure Integrate_Or_Reconcile
     (Store                     : in out Quality_Manager.Storage.Store;
      Runner                    : Quality_Manager.Integrations.Runner.Adapter;
      Journal_Operation         : Quality_Manager.Identities.Operation_Id;
      Project_Resource          : String;
      Lease_Owner               : String;
      Expected_Lease_Generation : Interfaces.Unsigned_64;
      New_Lease_Generation      : Interfaces.Unsigned_64;
      Lease_Expires_At          : Interfaces.Unsigned_64;
      Request                   : Quality_Manager.Integrations.Runner.Execution_Request;
      Snapshot                  : out Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result                    : out Quality_Manager.Results.Operation_Result);
   --  Perform Integrate Or Reconcile.
   --  @param Store Store.
   --  @param Runner Runner.
   --  @param Journal_Operation Journal Operation.
   --  @param Project_Resource Project Resource.
   --  @param Lease_Owner Lease Owner.
   --  @param Expected_Lease_Generation Expected Lease Generation.
   --  @param New_Lease_Generation New Lease Generation.
   --  @param Lease_Expires_At Lease Expires At.
   --  @param Request Request.
   --  @param Snapshot Snapshot.
   --  @param Result Result.
end Quality_Manager.Dispatch;
