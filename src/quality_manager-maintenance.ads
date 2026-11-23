with Ada.Strings.Unbounded;
with Interfaces;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Integrations.Runner;
with Quality_Manager.Results;
with Quality_Manager.Scheduler;

--  Runs persistent continuous quality-maintenance cycles.
package Quality_Manager.Maintenance is
   --  Public contract for this Quality Manager unit.
   Maintenance_Error : exception;
   --  Raised for Maintenance Error.

   type Assessment_Reason is
     (No_Assessment,
      Evidence_Incomplete,
      Source_Changed,
      Policy_Changed,
      Toolchain_Changed,
      Scheduled_Refresh,
      Evidence_Current);
   --  Assessment Reason values.
   --  @enum No_Assessment No Assessment.
   --  @enum Evidence_Incomplete Evidence Incomplete.
   --  @enum Source_Changed Source Changed.
   --  @enum Policy_Changed Policy Changed.
   --  @enum Toolchain_Changed Toolchain Changed.
   --  @enum Scheduled_Refresh Scheduled Refresh.
   --  @enum Evidence_Current Evidence Current.

   type Evidence_Identity is record
      Assessment_Run     : Natural := 0;
      Assessment_Complete : Boolean := False;
      Previous_Source    : Ada.Strings.Unbounded.Unbounded_String;
      Current_Source     : Ada.Strings.Unbounded.Unbounded_String;
      Previous_Policy    : Ada.Strings.Unbounded.Unbounded_String;
      Current_Policy     : Ada.Strings.Unbounded.Unbounded_String;
      Previous_Toolchain : Ada.Strings.Unbounded.Unbounded_String;
      Current_Toolchain  : Ada.Strings.Unbounded.Unbounded_String;
      Refresh_Due        : Boolean := False;
   end record;
   --  Evidence Identity record.
   --  @field Assessment_Run Assessment Run.
   --  @field Assessment_Complete Assessment Complete.
   --  @field Previous_Source Previous Source.
   --  @field Current_Source Current Source.
   --  @field Previous_Policy Previous Policy.
   --  @field Current_Policy Current Policy.
   --  @field Previous_Toolchain Previous Toolchain.
   --  @field Current_Toolchain Current Toolchain.
   --  @field Refresh_Due Refresh Due.

   function Due_Reason (Evidence : Evidence_Identity) return Assessment_Reason;
   --  Return Due Reason.
   --  @param Evidence Evidence.
   --  @return Due Reason result.
   function Assessment_Due (Evidence : Evidence_Identity) return Boolean;
   --  Return Assessment Due.
   --  @param Evidence Evidence.
   --  @return Assessment Due result.

   type Context is limited private;
   --  Context domain value.
   type Context_Access is access all Context;
   --  Context Access domain value.

   procedure Initialize
     (Item      : out Context;
      Store     : Quality_Manager.Scheduler.Store_Access;
      Scheduler : access Quality_Manager.Scheduler.Scheduler_Type;
      Quality   : Quality_Manager.Integrations.Quality.Adapter;
      Planner   : Quality_Manager.Integrations.Improve.Adapter;
      Runner    : Quality_Manager.Integrations.Runner.Adapter;
      Maximum_Task_Seconds : Positive := 3_600;
      Maximum_Attempts : Positive := 2);
   --  Perform Initialize.
   --  @param Item Item.
   --  @param Store Store.
   --  @param Scheduler Scheduler.
   --  @param Quality Quality.
   --  @param Planner Planner.
   --  @param Runner Runner.
   --  @param Maximum_Task_Seconds Maximum Task Seconds.
   --  @param Maximum_Attempts Maximum Attempts.

   procedure Run_Cycle
     (Item             : in out Context;
      Project_Selector : String := "";
      Dry_Run          : Boolean := False;
      Result           : out Quality_Manager.Results.Operation_Result);
   --  Perform Run Cycle.
   --  @param Item Item.
   --  @param Project_Selector Project Selector.
   --  @param Dry_Run Dry Run.
   --  @param Result Result.

   procedure Reconcile_Authorized_Work
     (Item             : in out Context;
      Project_Selector : String;
      Now              : Interfaces.Unsigned_64;
      Result           : out Quality_Manager.Results.Operation_Result);
   --  Perform Reconcile Authorized Work.
   --  @param Item Item.
   --  @param Project_Selector Project Selector.
   --  @param Now Now.
   --  @param Result Result.

   procedure Reconcile_Cycles
     (Item   : in out Context;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Reconcile Cycles.
   --  @param Item Item.
   --  @param Result Result.

   procedure Run_Cycle
     (Project_Selector : String := "";
      Dry_Run          : Boolean := False);
   --  Perform Run Cycle.
   --  @param Project_Selector Project Selector.
   --  @param Dry_Run Dry Run.

   procedure Run_Configured_Cycle
     (Project_Selector : String;
      Dry_Run          : Boolean;
      Config_Path      : String;
      Config_Required  : Boolean);
   --  Perform Run Configured Cycle.
   --  @param Project_Selector Project Selector.
   --  @param Dry_Run Dry Run.
   --  @param Config_Path Config Path.
   --  @param Config_Required Config Required.

private
   type Scheduler_Access is access all Quality_Manager.Scheduler.Scheduler_Type;
   type Context is limited record
      Database : Quality_Manager.Scheduler.Store_Access;
      Queue    : Scheduler_Access;
      Quality  : Quality_Manager.Integrations.Quality.Adapter;
      Planner  : Quality_Manager.Integrations.Improve.Adapter;
      Runner   : Quality_Manager.Integrations.Runner.Adapter;
      Maximum_Task_Seconds : Positive := 3_600;
      Maximum_Attempts : Positive := 2;
      Lease_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Lease_Generation : Interfaces.Unsigned_64 := 0;
      Lease_Seconds : Positive := 3_900;
   end record;
end Quality_Manager.Maintenance;
