with Interfaces;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.Runner;
with Quality_Manager.Model;
with Quality_Manager.Results;
with Quality_Manager.Storage;
with Quality_Manager.Storage.Schema;

package Quality_Manager.Dispatch is
   function Operation_Name
     (Operation : Quality_Manager.Identities.Operation_Id) return String;

   function Coordinator_State
     (State : Quality_Manager.Integrations.Runner.Execution_State)
      return Quality_Manager.Model.Work_State;

   procedure Bind_Published_Task
     (Store    : in out Quality_Manager.Storage.Store;
      Dispatch : Quality_Manager.Storage.Schema.Dispatch;
      Result   : out Quality_Manager.Results.Operation_Result);

   procedure Publish_Approved
     (Store     : in out Quality_Manager.Storage.Store;
      Planner   : Quality_Manager.Integrations.Improve.Adapter;
      Work      : Quality_Manager.Storage.Schema.Work_Item;
      Approval  : Quality_Manager.Storage.Schema.Approval;
      Now       : Interfaces.Unsigned_64;
      Published : out Quality_Manager.Storage.Schema.Dispatch;
      Result    : out Quality_Manager.Results.Operation_Result);

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

   procedure Queue_Persisted
     (Store   : in out Quality_Manager.Storage.Store;
      Runner  : Quality_Manager.Integrations.Runner.Adapter;
      Work_Id : String;
      Result  : out Quality_Manager.Results.Operation_Result);

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
end Quality_Manager.Dispatch;
