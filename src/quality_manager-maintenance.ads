with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Results;
with Quality_Manager.Scheduler;

package Quality_Manager.Maintenance is
   Maintenance_Error : exception;

   type Assessment_Reason is
     (No_Assessment,
      Evidence_Incomplete,
      Source_Changed,
      Policy_Changed,
      Toolchain_Changed,
      Scheduled_Refresh,
      Evidence_Current);

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

   function Due_Reason (Evidence : Evidence_Identity) return Assessment_Reason;
   function Assessment_Due (Evidence : Evidence_Identity) return Boolean;

   type Context is limited private;
   type Context_Access is access all Context;

   procedure Initialize
     (Item      : out Context;
      Store     : Quality_Manager.Scheduler.Store_Access;
      Scheduler : access Quality_Manager.Scheduler.Scheduler_Type;
      Quality   : Quality_Manager.Integrations.Quality.Adapter;
      Planner   : Quality_Manager.Integrations.Improve.Adapter);

   procedure Run_Cycle
     (Item             : in out Context;
      Project_Selector : String := "";
      Dry_Run          : Boolean := False;
      Result           : out Quality_Manager.Results.Operation_Result);

   procedure Run_Cycle
     (Project_Selector : String := "";
      Dry_Run          : Boolean := False);

   procedure Run_Configured_Cycle
     (Project_Selector : String;
      Dry_Run          : Boolean;
      Config_Path      : String;
      Config_Required  : Boolean);

private
   type Scheduler_Access is access all Quality_Manager.Scheduler.Scheduler_Type;
   type Context is limited record
      Database : Quality_Manager.Scheduler.Store_Access;
      Queue    : Scheduler_Access;
      Quality  : Quality_Manager.Integrations.Quality.Adapter;
      Planner  : Quality_Manager.Integrations.Improve.Adapter;
   end record;
end Quality_Manager.Maintenance;
