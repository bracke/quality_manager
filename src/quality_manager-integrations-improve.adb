with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Hostkit.Process;

package body Quality_Manager.Integrations.Improve is
   function Image (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   procedure Initialize
     (Item : out Adapter; Executable, Config_Path, Quality_Database, State_Database : String) is
      Value : Hostkit.UString;
   begin
      Item.Executable := To_Unbounded_String (Executable);
      Item.Config_Path := To_Unbounded_String (Config_Path);
      Item.Quality_Database := To_Unbounded_String (Quality_Database);
      Item.State_Database := To_Unbounded_String (State_Database);
      if Hostkit.Process.Environment_Value ("PATH", Value) then
         Item.Environment.Append (To_Unbounded_String ("PATH=" & To_String (Value)));
      end if;
      if Hostkit.Process.Environment_Value ("HOME", Value) then
         Item.Environment.Append (To_Unbounded_String ("HOME=" & To_String (Value)));
      end if;
   end Initialize;

   procedure Invoke
     (Item : Adapter; Command : Processes.String_Vectors.Vector; Expected_Command : String;
      Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("--config")); Args.Append (Item.Config_Path);
      Args.Append (To_Unbounded_String ("--database")); Args.Append (Item.Quality_Database);
      Args.Append (To_Unbounded_String ("--state")); Args.Append (Item.State_Database);
      Args.Append (To_Unbounded_String ("--format")); Args.Append (To_Unbounded_String ("json"));
      for Argument of Command loop Args.Append (Argument); end loop;
      JSON_CLI.Execute
        (To_String (Item.Executable), Args, "", Item.Environment, JSON_CLI.Improve_Contract,
         2, 3_600, 16 * 1_024 * 1_024, Result, "command", Expected_Command);
   end Invoke;

   procedure Generate_Plan
     (Item    : Adapter;
      Project : String;
      Run     : Natural;
      Result  : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("plan")); Args.Append (To_Unbounded_String ("--project"));
      Args.Append (To_Unbounded_String (Project));
      if Run > 0 then
         Args.Append (To_Unbounded_String ("--run"));
         Args.Append
           (To_Unbounded_String
              (Ada.Strings.Fixed.Trim (Natural'Image (Run), Ada.Strings.Both)));
      end if;
      Invoke (Item, Args, "plan", Result);
   end Generate_Plan;

   procedure Read_Plan
     (Item : Adapter; Plan_Id : String; Revision : Natural; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("plan")); Args.Append (To_Unbounded_String ("show"));
      Args.Append (To_Unbounded_String (Plan_Id));
      if Revision > 0 then
         Args.Append (To_Unbounded_String ("--revision")); Args.Append (To_Unbounded_String (Image (Revision)));
      end if;
      Invoke (Item, Args, "plan", Result);
   end Read_Plan;

   procedure Inspect_Approval
     (Item : Adapter; Plan_Id : String; Revision : Positive; Result : out JSON_CLI.Response) is
   begin
      Read_Plan (Item, Plan_Id, Revision, Result);
   end Inspect_Approval;

   procedure Approve_Exact_Revision
     (Item : Adapter; Plan_Id : String; Revision : Positive; Content_SHA256 : String;
      Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("plan"));
      Args.Append (To_Unbounded_String ("approve"));
      Args.Append (To_Unbounded_String (Plan_Id));
      Args.Append (To_Unbounded_String ("--revision"));
      Args.Append (To_Unbounded_String (Image (Revision)));
      Args.Append (To_Unbounded_String ("--content-sha256"));
      Args.Append (To_Unbounded_String (Content_SHA256));
      Invoke (Item, Args, "plan approve", Result);
   end Approve_Exact_Revision;

   procedure Publication
     (Item : Adapter; Plan_Id, Task_Id : String; Dry_Run : Boolean; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("apply")); Args.Append (To_Unbounded_String (Plan_Id));
      if Task_Id /= "" then
         Args.Append (To_Unbounded_String ("--task")); Args.Append (To_Unbounded_String (Task_Id));
      end if;
      if Dry_Run then Args.Append (To_Unbounded_String ("--dry-run")); end if;
      Invoke (Item, Args, "apply", Result);
   end Publication;

   procedure Preflight_Publication
     (Item : Adapter; Plan_Id, Task_Id : String; Result : out JSON_CLI.Response) is
   begin Publication (Item, Plan_Id, Task_Id, True, Result); end Preflight_Publication;
   procedure Publish_Task
     (Item : Adapter; Plan_Id, Task_Id : String; Result : out JSON_CLI.Response) is
   begin Publication (Item, Plan_Id, Task_Id, False, Result); end Publish_Task;

   procedure Read_Task_State
     (Item : Adapter; Task_Id : String; Revision : Natural; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("tasks")); Args.Append (To_Unbounded_String ("--task"));
      Args.Append (To_Unbounded_String (Task_Id));
      if Revision > 0 then Args.Append (To_Unbounded_String ("--revision"));
         Args.Append (To_Unbounded_String (Image (Revision))); end if;
      Invoke (Item, Args, "tasks", Result);
   end Read_Task_State;

   procedure Read_Plan_State (Item : Adapter; Plan_Id : String; Result : out JSON_CLI.Response) is
   begin Read_Plan (Item, Plan_Id, 0, Result); end Read_Plan_State;

   procedure Verify_Task
     (Item : Adapter; Task_Id : String; Revision, Run : Positive; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("verify")); Args.Append (To_Unbounded_String ("--task"));
      Args.Append (To_Unbounded_String (Task_Id)); Args.Append (To_Unbounded_String ("--revision"));
      Args.Append (To_Unbounded_String (Image (Revision))); Args.Append (To_Unbounded_String ("--run"));
      Args.Append (To_Unbounded_String (Image (Run))); Invoke (Item, Args, "verify", Result);
   end Verify_Task;

   procedure Verify_Project
     (Item : Adapter; Project : String; Revision, Run : Positive; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("verify")); Args.Append (To_Unbounded_String ("--project"));
      Args.Append (To_Unbounded_String (Project)); Args.Append (To_Unbounded_String ("--revision"));
      Args.Append (To_Unbounded_String (Image (Revision))); Args.Append (To_Unbounded_String ("--run"));
      Args.Append (To_Unbounded_String (Image (Run))); Invoke (Item, Args, "verify", Result);
   end Verify_Project;

   procedure Recover_Publication (Item : Adapter; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin Args.Append (To_Unbounded_String ("recover")); Invoke (Item, Args, "recover", Result); end Recover_Publication;

   procedure Export_Audit (Item : Adapter; Plan_Id : String; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("audit")); Args.Append (To_Unbounded_String (Plan_Id));
      Invoke (Item, Args, "audit", Result);
   end Export_Audit;
end Quality_Manager.Integrations.Improve;
