with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Database.Status;
with Database.UUIDs;
with Hostkit.Process;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;

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

   procedure Invoke
     (Item : Adapter; Arguments : Processes.String_Vectors.Vector; Result : out JSON_CLI.Response;
      Kind : String := ""; Schema_Version : Positive := 1);

   procedure Resolve_Database_Identity
     (Item     : Adapter;
      Identity : out Ada.Strings.Unbounded.Unbounded_String;
      Result   : out Quality_Manager.Results.Operation_Result) is
      use type Jsonlib.Documents.Value_Kind;
      use type Quality_Manager.Results.Result_Kind;
      Args     : Processes.String_Vectors.Vector;
      Response : JSON_CLI.Response;
   begin
      Identity := Null_Unbounded_String;
      Args.Append (To_Unbounded_String ("database"));
      Args.Append (To_Unbounded_String ("stats"));
      Args.Append (To_Unbounded_String ("--format"));
      Args.Append (To_Unbounded_String ("json"));
      Invoke (Item, Args, Response, "database-statistics", 2);
      Result := Response.Status;
      if Result.Kind /= Quality_Manager.Results.Success then
         return;
      end if;

      declare
         Document : Jsonlib.Documents.Document;
         Error    : Jsonlib.Errors.Error_Info;
      begin
         Jsonlib.Parsers.Parse
           (To_String (Response.Document), Document, Error,
            (Max_Depth => 64,
             Max_Length => 4 * 1_024 * 1_024,
             Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
         if Jsonlib.Errors.Failed (Error) then
            Result := Quality_Manager.Results.Make_Result
              (Quality_Manager.Results.Incompatible_Contract,
               "Ada Quality database identity response is invalid JSON",
               "qm.quality.database-identity-json");
            return;
         end if;

         declare
            Node : constant Jsonlib.Documents.Node :=
              Document.Member (Document.Root, "database_identity");
         begin
            if not Jsonlib.Documents.Is_Present (Node)
              or else Document.Kind (Node) /= Jsonlib.Documents.String_Value
            then
               Result := Quality_Manager.Results.Make_Result
                 (Quality_Manager.Results.Incompatible_Contract,
                  "database_identity must be a string",
                  "qm.quality.database-identity-missing");
               return;
            end if;
            Identity := To_Unbounded_String (Document.As_String (Node));
         end;
      end;

      declare
         Text   : constant String := To_String (Identity);
         Value  : Database.UUIDs.UUID;
         Status : constant Database.Status.Result := Database.UUIDs.Parse_UUID
           (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text), Value);
      begin
         if not Database.Status.Is_Ok (Status)
           or else Database.UUIDs.Compare (Value, Database.UUIDs.Nil_UUID) = 0
           or else Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
             (Database.UUIDs.UUID_To_String (Value)) /= Text
         then
            Identity := Null_Unbounded_String;
            Result := Quality_Manager.Results.Make_Result
              (Quality_Manager.Results.Incompatible_Contract,
               "database_identity is not a canonical non-nil UUID",
               "qm.quality.database-identity-invalid");
            return;
         end if;
      end;
      Result := Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success);
   end Resolve_Database_Identity;

   procedure Invoke
     (Item : Adapter; Arguments : Processes.String_Vectors.Vector; Result : out JSON_CLI.Response;
      Kind : String := ""; Schema_Version : Positive := 1) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("--database"));
      Args.Append (Item.Database_Path);
      for Argument of Arguments loop
         Args.Append (Argument);
      end loop;
      JSON_CLI.Execute
        (To_String (Item.Executable), Args, To_String (Item.Working_Directory), Item.Environment,
         JSON_CLI.Ada_Quality_Contract, Schema_Version, 3_600, 16 * 1_024 * 1_024, Result,
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
