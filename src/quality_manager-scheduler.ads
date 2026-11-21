with Ada.Strings.Unbounded;
with Interfaces;
with Quality_Manager.Priorities;
with Quality_Manager.Results;
with Quality_Manager.Storage;

package Quality_Manager.Scheduler is
   type Scheduler_Type is limited private;
   type Store_Access is access all Quality_Manager.Storage.Store;
   type Work_Resource is (Assessment_Resource, Agent_Resource, Integration_Resource);

   type Eligibility_Facts is record
      Project_Enabled       : Boolean := False;
      Project_Identity_Valid : Boolean := False;
      Task_Nonterminal      : Boolean := False;
      Dependencies_Satisfied : Boolean := False;
      Evidence_Applicable   : Boolean := False;
      Plan_Current          : Boolean := False;
      Approval_Valid        : Boolean := False;
      Native_Task_Ready     : Boolean := False;
      Budget_Available      : Boolean := False;
      Project_Lock_Available : Boolean := False;
      Autonomy_Permits      : Boolean := False;
   end record;

   procedure Evaluate_Eligibility
     (Facts  : Eligibility_Facts;
      Ready  : out Boolean;
      Reason : out Ada.Strings.Unbounded.Unbounded_String);

   procedure Initialize (Item : in out Scheduler_Type);

   procedure Configure
     (Item               : in out Scheduler_Type;
      Store              : Store_Access;
      Assessment_Workers : Positive := 4;
      Agent_Workers      : Positive := 1);

   procedure Enqueue
     (Item    : in out Scheduler_Type;
      Work_Id : String);

   procedure Enqueue_Work
     (Item             : in out Scheduler_Type;
      Work_Id          : String;
      Project_Resource : String;
      Class            : Quality_Manager.Priorities.Priority_Class;
      Eligible_At      : Interfaces.Unsigned_64;
      Resource         : Work_Resource);

   procedure Evaluate_And_Queue
     (Item    : in out Scheduler_Type;
      Work_Id : String;
      Facts   : Eligibility_Facts);

   procedure Dispatch_Due (Item : in out Scheduler_Type);
   procedure Reconcile (Item : in out Scheduler_Type);

   procedure Take_Next
     (Item     : in out Scheduler_Type;
      Work_Id  : out Ada.Strings.Unbounded.Unbounded_String;
      Resource : out Work_Resource;
      Found    : out Boolean);

   procedure Complete
     (Item    : in out Scheduler_Type;
      Work_Id : String);

   function Pending_Count (Item : Scheduler_Type) return Natural;
   function Active_Count (Item : Scheduler_Type; Resource : Work_Resource) return Natural;
   function Last_Result (Item : Scheduler_Type) return Quality_Manager.Results.Operation_Result;

   procedure Request_Stop (Item : in out Scheduler_Type);
   procedure Resume (Item : in out Scheduler_Type);
   procedure Shutdown (Item : in out Scheduler_Type);
   function Is_Stopping (Item : Scheduler_Type) return Boolean;

private
   type Scheduler_Type is limited record
      Scheduler_Id       : Natural := 0;
      Database           : Store_Access := null;
      Assessment_Workers : Positive := 4;
      Agent_Workers      : Positive := 1;
      Status             : Quality_Manager.Results.Operation_Result;
   end record;
end Quality_Manager.Scheduler;
