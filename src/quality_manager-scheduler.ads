with Ada.Strings.Unbounded;
with Interfaces;
with Quality_Manager.Priorities;
with Quality_Manager.Results;
with Quality_Manager.Storage;

--  Coordinates bounded durable work and resource reservations.
package Quality_Manager.Scheduler is
   --  Public contract for this Quality Manager unit.
   type Scheduler_Type is limited private;
   --  Scheduler Type domain value.
   type Store_Access is access all Quality_Manager.Storage.Store;
   --  Store Access domain value.
   type Work_Resource is (Assessment_Resource, Agent_Resource, Integration_Resource);
   --  Work Resource values.
   --  @enum Assessment_Resource Assessment Resource.
   --  @enum Agent_Resource Agent Resource.
   --  @enum Integration_Resource Integration Resource.

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
   --  Eligibility Facts record.
   --  @field Project_Enabled Project Enabled.
   --  @field Project_Identity_Valid Project Identity Valid.
   --  @field Task_Nonterminal Task Nonterminal.
   --  @field Dependencies_Satisfied Dependencies Satisfied.
   --  @field Evidence_Applicable Evidence Applicable.
   --  @field Plan_Current Plan Current.
   --  @field Approval_Valid Approval Valid.
   --  @field Native_Task_Ready Native Task Ready.
   --  @field Budget_Available Budget Available.
   --  @field Project_Lock_Available Project Lock Available.
   --  @field Autonomy_Permits Autonomy Permits.

   procedure Evaluate_Eligibility
     (Facts  : Eligibility_Facts;
      Ready  : out Boolean;
      Reason : out Ada.Strings.Unbounded.Unbounded_String);
   --  Perform Evaluate Eligibility.
   --  @param Facts Facts.
   --  @param Ready Ready.
   --  @param Reason Reason.

   procedure Initialize (Item : in out Scheduler_Type);
   --  Perform Initialize.
   --  @param Item Item.

   procedure Configure
     (Item               : in out Scheduler_Type;
      Store              : Store_Access;
      Assessment_Workers : Positive := 4;
      Agent_Workers      : Positive := 1);
   --  Perform Configure.
   --  @param Item Item.
   --  @param Store Store.
   --  @param Assessment_Workers Assessment Workers.
   --  @param Agent_Workers Agent Workers.

   procedure Enqueue
     (Item    : in out Scheduler_Type;
      Work_Id : String);
   --  Perform Enqueue.
   --  @param Item Item.
   --  @param Work_Id Work Id.

   procedure Enqueue_Work
     (Item             : in out Scheduler_Type;
      Work_Id          : String;
      Project_Resource : String;
      Class            : Quality_Manager.Priorities.Priority_Class;
      Eligible_At      : Interfaces.Unsigned_64;
      Resource         : Work_Resource);
   --  Perform Enqueue Work.
   --  @param Item Item.
   --  @param Work_Id Work Id.
   --  @param Project_Resource Project Resource.
   --  @param Class Class.
   --  @param Eligible_At Eligible At.
   --  @param Resource Resource.

   procedure Evaluate_And_Queue
     (Item    : in out Scheduler_Type;
      Work_Id : String;
      Facts   : Eligibility_Facts);
   --  Perform Evaluate And Queue.
   --  @param Item Item.
   --  @param Work_Id Work Id.
   --  @param Facts Facts.

   procedure Dispatch_Due (Item : in out Scheduler_Type);
   --  Perform Dispatch Due.
   --  @param Item Item.
   procedure Reconcile (Item : in out Scheduler_Type);
   --  Perform Reconcile.
   --  @param Item Item.

   procedure Take_Next
     (Item     : in out Scheduler_Type;
      Work_Id  : out Ada.Strings.Unbounded.Unbounded_String;
      Resource : out Work_Resource;
      Found    : out Boolean);
   --  Perform Take Next.
   --  @param Item Item.
   --  @param Work_Id Work Id.
   --  @param Resource Resource.
   --  @param Found Found.

   procedure Complete
     (Item    : in out Scheduler_Type;
      Work_Id : String);
   --  Perform Complete.
   --  @param Item Item.
   --  @param Work_Id Work Id.

   function Pending_Count (Item : Scheduler_Type) return Natural;
   --  Return Pending Count.
   --  @param Item Item.
   --  @return Pending Count result.
   function Active_Count (Item : Scheduler_Type; Resource : Work_Resource) return Natural;
   --  Return Active Count.
   --  @param Item Item.
   --  @param Resource Resource.
   --  @return Active Count result.
   function Last_Result (Item : Scheduler_Type) return Quality_Manager.Results.Operation_Result;
   --  Return Last Result.
   --  @param Item Item.
   --  @return Last Result result.

   procedure Request_Stop (Item : in out Scheduler_Type);
   --  Perform Request Stop.
   --  @param Item Item.
   procedure Resume (Item : in out Scheduler_Type);
   --  Perform Resume.
   --  @param Item Item.
   procedure Shutdown (Item : in out Scheduler_Type);
   --  Perform Shutdown.
   --  @param Item Item.
   function Is_Stopping (Item : Scheduler_Type) return Boolean;
   --  Return Is Stopping.
   --  @param Item Item.
   --  @return Is Stopping result.

private
   type Scheduler_Type is limited record
      Scheduler_Id       : Natural := 0;
      Database           : Store_Access := null;
      Assessment_Workers : Positive := 4;
      Agent_Workers      : Positive := 1;
      Status             : Quality_Manager.Results.Operation_Result;
   end record;
end Quality_Manager.Scheduler;
