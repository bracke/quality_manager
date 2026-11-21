with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Hostkit.Process;

package body Quality_Manager.Integrations.Quality is
   function Image (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   procedure Initialize
     (Item              : out Adapter;
      Executable        : String;
      Database_Path     : String;
      Working_Directory : String := "") is
      Path : Hostkit.UString;
   begin
      Item.Executable := To_Unbounded_String (Executable);
      Item.Database_Path := To_Unbounded_String (Database_Path);
      Item.Working_Directory := To_Unbounded_String (Working_Directory);
      if Hostkit.Process.Environment_Value ("PATH", Path) then
         Item.Environment.Append (To_Unbounded_String ("PATH=" & To_String (Path)));
      end if;
   end Initialize;

   procedure Resolve_Database_Identity
     (Item     : Adapter;
      Identity : out Ada.Strings.Unbounded.Unbounded_String;
      Result   : out Quality_Manager.Results.Operation_Result) is
      pragma Unreferenced (Item);
   begin
      Identity := Null_Unbounded_String;
      Result := Quality_Manager.Results.Make_Result
        (Quality_Manager.Results.Incompatible_Contract,
         "Ada Quality does not expose a durable database identity",
         "qm.quality.database-identity-unavailable");
   end Resolve_Database_Identity;

   procedure Invoke
     (Item : Adapter; Arguments : Processes.String_Vectors.Vector; Result : out JSON_CLI.Response;
      Kind : String := "") is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("--database"));
      Args.Append (Item.Database_Path);
      for Argument of Arguments loop
         Args.Append (Argument);
      end loop;
      JSON_CLI.Execute
        (To_String (Item.Executable), Args, To_String (Item.Working_Directory), Item.Environment,
         JSON_CLI.Ada_Quality_Contract, 1, 3_600, 16 * 1_024 * 1_024, Result,
         (if Kind = "" then "" else "kind"), Kind);
   end Invoke;

   procedure List_Projects (Item : Adapter; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("project"));
      Args.Append (To_Unbounded_String ("list"));
      Args.Append (To_Unbounded_String ("--json"));
      Invoke (Item, Args, Result, "project-list");
   end List_Projects;

   procedure Inspect_Project (Item : Adapter; Project : String; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("project")); Args.Append (To_Unbounded_String ("show"));
      Args.Append (To_Unbounded_String (Project)); Args.Append (To_Unbounded_String ("--json"));
      Invoke (Item, Args, Result, "project-list");
   end Inspect_Project;

   procedure Check
     (Item : Adapter; Project, Profile : String; Reuse_Unchanged, Dry_Run : Boolean;
      Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("check")); Args.Append (To_Unbounded_String ("--project"));
      Args.Append (To_Unbounded_String (Project)); Args.Append (To_Unbounded_String ("--profile"));
      Args.Append (To_Unbounded_String (Profile));
      if Reuse_Unchanged then Args.Append (To_Unbounded_String ("--reuse-unchanged")); end if;
      if Dry_Run then Args.Append (To_Unbounded_String ("--dry-run")); end if;
      Args.Append (To_Unbounded_String ("--json"));
      Invoke (Item, Args, Result, (if Dry_Run then "check-plan" else ""));
   end Check;

   procedure Plan_Check
     (Item : Adapter; Project, Profile : String; Reuse_Unchanged : Boolean; Result : out JSON_CLI.Response) is
   begin
      Check (Item, Project, Profile, Reuse_Unchanged, True, Result);
   end Plan_Check;

   procedure Run_Check
     (Item : Adapter; Project, Profile : String; Reuse_Unchanged : Boolean; Result : out JSON_CLI.Response) is
   begin
      Check (Item, Project, Profile, Reuse_Unchanged, False, Result);
   end Run_Check;

   procedure Read_Assessment (Item : Adapter; Run : Positive; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("assessment")); Args.Append (To_Unbounded_String ("show"));
      Args.Append (To_Unbounded_String (Image (Run))); Args.Append (To_Unbounded_String ("--json"));
      Invoke (Item, Args, Result);
   end Read_Assessment;

   procedure Compare (Item : Adapter; Baseline, Current : Positive; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("assessment")); Args.Append (To_Unbounded_String ("diff"));
      Args.Append (To_Unbounded_String (Image (Baseline))); Args.Append (To_Unbounded_String (Image (Current)));
      Args.Append (To_Unbounded_String ("--json")); Invoke (Item, Args, Result, "assessment-comparison");
   end Compare;

   procedure Check_Environment (Item : Adapter; Project : String; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("doctor")); Args.Append (To_Unbounded_String ("--project"));
      Args.Append (To_Unbounded_String (Project)); Args.Append (To_Unbounded_String ("--json"));
      Invoke (Item, Args, Result, "doctor-report");
   end Check_Environment;
end Quality_Manager.Integrations.Quality;
