with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;
with Interfaces;

with Quality_Manager.CLI;
with Quality_Manager.Approvals;
with Quality_Manager.Campaigns;
with Quality_Manager.Config;
with Quality_Manager.Dispatch;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Integrations.Runner;
with Quality_Manager.Integrations.Summary;
with Quality_Manager.Journal;
with Quality_Manager.Maintenance;
with Quality_Manager.Model;
with Quality_Manager.Planning;
with Quality_Manager.Reporting;
with Quality_Manager.Releases;
with Quality_Manager.Results;
with Quality_Manager.Scheduler;
with Quality_Manager.Priorities;
with Quality_Manager.Policies;
with Quality_Manager.Schemas;
with Quality_Manager.Storage.Schema;
with Quality_Manager.Storage.Migrations;
with Quality_Manager.Storage.Records;
with Quality_Manager.Transitions;
with Quality_Manager.Verification;

package body Quality_Manager_Test_Suite is
   use type Quality_Manager.CLI.Command_Kind;
   use type Quality_Manager.CLI.Output_Format;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Journal.Recovery_Action;
   use type Quality_Manager.Identities.Operation_Id;
   use type Quality_Manager.Storage.Record_Kind;
   use type Quality_Manager.Integrations.Runner.Execution_State;
   use type Quality_Manager.Integrations.JSON_CLI.Exit_Contract;
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Model.Outcome_Kind;
   use type Quality_Manager.Model.Risk_Level;
   use type Quality_Manager.Verification.Retry_Action;
   use type Quality_Manager.Scheduler.Work_Resource;
   use type Quality_Manager.Maintenance.Assessment_Reason;
   use type Quality_Manager.Policies.Permission;
   use type Quality_Manager.Priorities.Priority_Class;
   use type Quality_Manager.Reporting.Operational_View;
   use type Interfaces.Unsigned_64;

   package Caller is new AUnit.Test_Caller (Fixture);

   Base_Path : constant String := "/tmp/quality-manager-phase1-test.toml";

   procedure Remove_Test_File is
   begin
      if Ada.Directories.Exists (Base_Path) then
         Ada.Directories.Delete_File (Base_Path);
      end if;
   end Remove_Test_File;

   procedure Write_Text (Text : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Remove_Test_File;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Base_Path);
      Ada.Text_IO.Put (File, Text);
      Ada.Text_IO.Close (File);
   end Write_Text;

   procedure Write_Invalid_UTF_8 is
      package IO renames Ada.Streams.Stream_IO;
      File : IO.File_Type;
      Data : constant Ada.Streams.Stream_Element_Array := [1 => 16#C3#, 2 => 16#28#];
   begin
      Remove_Test_File;
      IO.Create (File, IO.Out_File, Base_Path);
      IO.Write (File, Data);
      IO.Close (File);
   end Write_Invalid_UTF_8;

   procedure Test_Config_Validation (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Settings : Quality_Manager.Config.Settings;
      Result   : Quality_Manager.Results.Operation_Result;
   begin
      Quality_Manager.Config.Load ("/tmp/qm-no-such-config.toml", True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing required config is rejected");

      Write_Text ("[scheduler]" & ASCII.LF & "agent_workers = 0" & ASCII.LF);
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "out-of-range worker count is rejected");

      Write_Text ("[unknown]" & ASCII.LF & "key = true" & ASCII.LF);
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "unknown key is rejected");

      Write_Text ("[integrations]" & ASCII.LF & "model_runner = """"" & ASCII.LF);
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty model_runner executable is rejected");

      Write_Text ("[integrations]" & ASCII.LF & "ada_quality = """"" & ASCII.LF);
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty Ada Quality executable is rejected");

      Write_Text ("[integrations]" & ASCII.LF & "improve = """"" & ASCII.LF);
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty Improve executable is rejected");

      Write_Text ("[coordinator]" & ASCII.LF & "database = """"" & ASCII.LF);
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty coordinator path is rejected");

      Write_Text
        ("[coordinator]" & ASCII.LF & "database = ""/tmp/coordinator.db""" & ASCII.LF
         & "[quality]" & ASCII.LF & "database = ""/tmp/quality.db""" & ASCII.LF
         & "policy = ""/tmp/quality-policy.toml""" & ASCII.LF
         & "[integrations]" & ASCII.LF & "ada_quality = ""ada-quality-fixture""" & ASCII.LF
         & "improve = ""improve-fixture""" & ASCII.LF
         & "improve_config = ""/tmp/improve.toml""" & ASCII.LF
         & "improve_state = ""/tmp/improve.db""" & ASCII.LF
         & "model_runner = ""model-runner-fixture""" & ASCII.LF
         & "[scheduler]" & ASCII.LF & "assessment_workers = 3" & ASCII.LF
         & "agent_workers = 2" & ASCII.LF & "maximum_task_seconds = 120" & ASCII.LF
         & "remediation_attempts = 4" & ASCII.LF
         & "[autonomy]" & ASCII.LF & "dry_run = false" & ASCII.LF);
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Settings.Assessment_Workers = 3
         and then Settings.Agent_Workers = 2
         and then Settings.Maximum_Task_Seconds = 120
         and then Settings.Remediation_Attempts = 4
         and then To_String (Settings.Quality_Policy) = "/tmp/quality-policy.toml"
         and then To_String (Settings.Improve_Executable) = "improve-fixture"
         and then To_String (Settings.Improve_Config) = "/tmp/improve.toml"
         and then To_String (Settings.Improve_State) = "/tmp/improve.db"
         and then not Settings.Dry_Run,
         "complete valid configuration is retained");

      Quality_Manager.Config.Load ("/tmp/qm-no-such-optional.toml", False, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "missing optional configuration uses defaults");
      Quality_Manager.Config.Load ("", False, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "empty optional path uses defaults");

      Write_Text ("[scheduler" & ASCII.LF);
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "malformed TOML is rejected");
      Remove_Test_File;
   end Test_Config_Validation;

   procedure Test_Config_Encoding (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Settings : Quality_Manager.Config.Settings;
      Result   : Quality_Manager.Results.Operation_Result;
   begin
      Write_Invalid_UTF_8;
      Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "invalid UTF-8 is rejected");
      Assert (not Quality_Manager.Config.Is_Valid_UTF_8 (Character'Val (16#C0#) & Character'Val (16#AF#)),
              "overlong UTF-8 is rejected");
      Assert (Quality_Manager.Config.Is_Valid_UTF_8 ("quality"), "ASCII is valid UTF-8");
      Assert
        (Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#C2#) & Character'Val (16#A2#)),
         "valid two-byte UTF-8 is accepted");
      Assert
        (Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#E0#) & Character'Val (16#A0#) & Character'Val (16#80#))
         and then Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#E1#) & Character'Val (16#80#) & Character'Val (16#80#))
         and then Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#ED#) & Character'Val (16#9F#) & Character'Val (16#BF#)),
         "valid three-byte UTF-8 ranges are accepted");
      Assert
        (Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#F0#) & Character'Val (16#90#)
            & Character'Val (16#80#) & Character'Val (16#80#))
         and then Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#F1#) & Character'Val (16#80#)
            & Character'Val (16#80#) & Character'Val (16#80#))
         and then Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#F4#) & Character'Val (16#8F#)
            & Character'Val (16#BF#) & Character'Val (16#BF#)),
         "valid four-byte UTF-8 ranges are accepted");
      Assert
        (not Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#E0#) & Character'Val (16#80#) & Character'Val (16#80#))
         and then not Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#E1#) & Character'Val (16#41#) & Character'Val (16#80#))
         and then not Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#ED#) & Character'Val (16#A0#) & Character'Val (16#80#)),
         "invalid three-byte UTF-8 ranges are rejected");
      Assert
        (not Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#F0#) & Character'Val (16#80#)
            & Character'Val (16#80#) & Character'Val (16#80#))
         and then not Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#F1#) & Character'Val (16#41#)
            & Character'Val (16#80#) & Character'Val (16#80#))
         and then not Quality_Manager.Config.Is_Valid_UTF_8
           (Character'Val (16#F4#) & Character'Val (16#90#)
            & Character'Val (16#80#) & Character'Val (16#80#)),
         "invalid four-byte UTF-8 ranges are rejected");
      Remove_Test_File;
   end Test_Config_Encoding;

   procedure Test_Path_Normalization (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert (Quality_Manager.Config.Normalize_Path ("/a/./b/../c//") = "/a/c", "absolute path normalized");
      Assert (Quality_Manager.Config.Normalize_Path ("") = "", "empty path remains empty");
   end Test_Path_Normalization;

   procedure Test_CLI (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Args    : Quality_Manager.CLI.Argument_Vectors.Vector;
      Options : Quality_Manager.CLI.Options;
      Result  : Quality_Manager.Results.Operation_Result;
   begin
      Args.Append ("--config");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing option value rejected");

      Args.Clear;
      Args.Append ("--format=json");
      Args.Append ("--format");
      Args.Append ("terminal");
      Args.Append ("doctor");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate option rejected");

      Args.Clear;
      Args.Append ("maintenance");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Options.Command = Quality_Manager.CLI.Maintenance_Command,
         "one-shot maintenance command is accepted");

      Args.Clear;
      Args.Append ("--once");
      Args.Append ("maintenance");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "daemon-only option scope is enforced");

      Args.Clear;
      Args.Append ("doctor");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "doctor accepted");
      Assert (Options.Command = Quality_Manager.CLI.Doctor_Command, "doctor selected");

      Args.Clear;
      Args.Append ("release-create");
      Args.Append ("7");
      Args.Append ("release");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Options.Command = Quality_Manager.CLI.Release_Create_Command
         and then To_String (Options.Primary_Value) = "7"
         and then To_String (Options.Secondary_Value) = "release",
         "release creation retains its exact operands");

      Args.Clear;
      Args.Append ("campaign-start");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing workflow operand rejected");

      Args.Clear;
      Args.Append ("status");
      Args.Append ("unexpected");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "read-only view rejects operands");

      Args.Clear;
      Args.Append ("doctor");
      Args.Append ("version");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate command is rejected");

      Args.Clear;
      Args.Append ("release-export");
      Args.Append ("release-1");
      Args.Append ("evidence.json");
      Args.Append ("extra");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "excess operands are rejected");

      for Format in Quality_Manager.CLI.Output_Format loop
         declare
            Name : constant String :=
              (case Format is
                  when Quality_Manager.CLI.Terminal_Output => "terminal",
                  when Quality_Manager.CLI.JSON_Output => "json",
                  when Quality_Manager.CLI.Markdown_Output => "markdown");
         begin
            Args.Clear;
            Args.Append ("--format=" & Name);
            Args.Append ("doctor");
            Quality_Manager.CLI.Parse (Args, Options, Result);
            Assert (Result.Kind = Quality_Manager.Results.Success, "supported output format is accepted");
         end;
      end loop;

      Args.Clear;
      Args.Append ("--format=xml");
      Args.Append ("doctor");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "unknown output format is rejected");

      Args.Clear;
      Args.Append ("--format");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing format value is rejected");

      Args.Clear;
      Args.Append ("--config=/tmp/one.toml");
      Args.Append ("--config");
      Args.Append ("/tmp/two.toml");
      Args.Append ("doctor");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate config is rejected");

      Args.Clear;
      Args.Append ("--project");
      Args.Append ("one");
      Args.Append ("--project");
      Args.Append ("two");
      Args.Append ("maintenance");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate project selector is rejected");

      Args.Clear;
      Args.Append ("--project");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing project selector is rejected");

      Args.Clear;
      Args.Append ("--project");
      Args.Append ("one");
      Args.Append ("doctor");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "project selector scope is enforced");

      Args.Clear;
      Args.Append ("operand");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "operand before command is rejected");

      Args.Clear;
      Args.Append ("--unknown");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "unknown option is rejected");
   end Test_CLI;

   procedure Test_Operational_Control (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path       : constant String := "/tmp/quality-manager-operations.database";
      Definition : constant String := "/tmp/quality-manager-approval.json";
      Store      : Quality_Manager.Storage.Store;
      Result     : Quality_Manager.Results.Operation_Result;
      Output     : Unbounded_String;
      Loaded     : Quality_Manager.Storage.Stored_Entity;

      procedure Cleanup is
      begin
         if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
         if Ada.Directories.Exists (Definition) then Ada.Directories.Delete_File (Definition); end if;
      end Cleanup;

      procedure Write_Approval (Decision : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Definition);
         Ada.Text_IO.Put
           (File,
            "{""schema_version"":1,""decision"":""" & Decision & """," &
            """approval_id"":""approval-operator-1""," &
            """quality_database_id"":""database-a""," &
            """quality_project_id"":7,""canonical_path"":""/project""," &
            """plan_id"":""PLAN-001"",""plan_revision"":2," &
            """content_sha256"":""content-digest""," &
            """authorized_action"":""publish""," &
            """policy_sha256"":""policy-digest"",""approver"":""operator""," &
            """created_at"":10,""expires_at"":100}");
         Ada.Text_IO.Close (File);
      end Write_Approval;

      procedure Write_Raw (Text : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Definition);
         Ada.Text_IO.Put (File, Text);
         Ada.Text_IO.Close (File);
      end Write_Raw;
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "operations store opened");
      Output := To_Unbounded_String
        (Quality_Manager.Reporting.Operational
           (Store, Quality_Manager.Reporting.Overall_Status,
            Quality_Manager.CLI.JSON_Output, Result));
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Ada.Strings.Fixed.Index (To_String (Output), """count"":0") > 0,
         "empty operational status is valid structured output");
      Quality_Manager.Schemas.Validate_Versioned_JSON (To_String (Output), 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "operational JSON is versioned");

      Quality_Manager.Approvals.Apply_Decision
        (Store, "/tmp/no-such-approval.json", True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing approval record is rejected");
      Write_Raw ("{");
      Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "malformed approval JSON is rejected");
      Write_Raw ("{""schema_version"":1}");
      Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "incomplete approval record is rejected");
      Write_Approval ("reject");
      Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Invalid_Request,
         "administrative command cannot contradict signed decision content");
      Write_Approval ("approve");
      Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "exact approval record imported");
      Quality_Manager.Storage.Read (Store, "approval:approval-operator-1", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Ada.Strings.Fixed.Index (To_String (Loaded.Payload), """expires_at"":100") > 0,
         "persisted approval retains its audit lifetime");
      Output := To_Unbounded_String
        (Quality_Manager.Reporting.Operational
           (Store, Quality_Manager.Reporting.Approval_Status,
            Quality_Manager.CLI.JSON_Output, Result));
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Ada.Strings.Fixed.Index (To_String (Output), "approval:approval-operator-1") > 0,
         "approval status exposes the durable decision");
      Quality_Manager.Storage.Prepare_Operation
        (Store, 999, "operator-recovery", "intent", "external-999", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "recoverable operation prepared");
      for View in Quality_Manager.Reporting.Operational_View loop
         for Format in Quality_Manager.CLI.Output_Format loop
            Output := To_Unbounded_String
              (Quality_Manager.Reporting.Operational (Store, View, Format, Result));
            Assert
              (Result.Kind = Quality_Manager.Results.Success and then Length (Output) > 0,
               "every operational view supports every output format");
            if Format = Quality_Manager.CLI.JSON_Output then
               Quality_Manager.Schemas.Validate_Versioned_JSON (To_String (Output), 1, Result);
               Assert
                 (Result.Kind = Quality_Manager.Results.Success,
                  "operational JSON output remains versioned");
               if View = Quality_Manager.Reporting.Recovery_Status then
                  Assert
                    (Ada.Strings.Fixed.Index
                       (To_String (Output), "INVOKE_AFTER_REVALIDATION") > 0,
                     "recovery view reports the safe next action");
               end if;
            end if;
         end loop;
      end loop;
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Operational_Control;

   procedure Test_CLI_Executable (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Database_Path : constant String := "/tmp/quality-manager-cli.database";
      Config_Path   : constant String := "/tmp/quality-manager-cli.toml";
      Approval_Path : constant String := "/tmp/quality-manager-cli-approval.json";
      Campaign_Path : constant String := "/tmp/quality-manager-cli-campaign.json";
      Fixture_Path  : constant String :=
        (if Ada.Directories.Exists (Ada.Directories.Current_Directory & "/tests/bin/qm_adapter_fixture")
         then Ada.Directories.Current_Directory & "/tests/bin/qm_adapter_fixture"
         else Ada.Directories.Current_Directory & "/bin/qm_adapter_fixture");
      Store         : Quality_Manager.Storage.Store;
      Result        : Quality_Manager.Results.Operation_Result;

      procedure Remove (Path : String) is
      begin
         if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
      end Remove;

      procedure Cleanup is
      begin
         Remove (Database_Path);
         Remove (Database_Path & ".wal");
         Remove (Database_Path & ".journal");
         Remove (Database_Path & ".lock");
         Remove (Config_Path);
         Remove (Approval_Path);
         Remove (Campaign_Path);
      end Cleanup;

      procedure Write_File (Path, Text : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
         Ada.Text_IO.Put (File, Text);
         Ada.Text_IO.Close (File);
      end Write_File;

      function Run
        (Arguments : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
         Expected  : Integer := 0) return String is
         Request  : Quality_Manager.Integrations.Processes.Request;
         Response : Quality_Manager.Integrations.Processes.Execution_Result;
      begin
         Request.Executable := To_Unbounded_String
           ((if Ada.Directories.Exists ("bin/quality-manager")
             then "bin/quality-manager" else "../bin/quality-manager"));
         Request.Arguments := Arguments;
         Request.Working_Directory := To_Unbounded_String (Ada.Directories.Current_Directory);
         Request.Environment.Append
           (To_Unbounded_String
              ("PATH=" & Ada.Environment_Variables.Value ("PATH", "/usr/bin:/bin")));
         if Ada.Environment_Variables.Exists ("HOME") then
            Request.Environment.Append
              (To_Unbounded_String ("HOME=" & Ada.Environment_Variables.Value ("HOME")));
         end if;
         Request.Timeout_Seconds := 30;
         Request.Output_Limit := 1_048_576;
         Quality_Manager.Integrations.Processes.Execute (Request, Response);
         Assert (Response.Started and then not Response.Timed_Out, "CLI process completed");
         Assert
           (Response.Exit_Status = Expected,
            "CLI exit status matched for " & To_String (Arguments (Arguments.First_Index))
            & " (got" & Integer'Image (Response.Exit_Status)
            & ", expected" & Integer'Image (Expected) & "): "
            & To_String (Response.Error_Output) & To_String (Response.Standard_Output));
         return To_String (Response.Standard_Output);
      end Run;

      function Args
        (First : String;
         Second : String := "";
         Third : String := "";
         Fourth : String := "";
         Fifth : String := "")
         return Quality_Manager.Integrations.Processes.String_Vectors.Vector is
         Values : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      begin
         Values.Append (To_Unbounded_String (First));
         if Second'Length > 0 then Values.Append (To_Unbounded_String (Second)); end if;
         if Third'Length > 0 then Values.Append (To_Unbounded_String (Third)); end if;
         if Fourth'Length > 0 then Values.Append (To_Unbounded_String (Fourth)); end if;
         if Fifth'Length > 0 then Values.Append (To_Unbounded_String (Fifth)); end if;
         return Values;
      end Args;

      Output : Unbounded_String;
      Views  : constant array (Positive range <>) of Unbounded_String :=
        [To_Unbounded_String ("status"),
         To_Unbounded_String ("queue"),
         To_Unbounded_String ("approvals"),
         To_Unbounded_String ("history"),
         To_Unbounded_String ("events"),
         To_Unbounded_String ("recover")];
   begin
      Cleanup;
      Assert (Ada.Directories.Exists (Fixture_Path), "fixture exists at " & Fixture_Path);
      Quality_Manager.Storage.Open (Store, Database_Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "CLI database initialized");
      Quality_Manager.Storage.Close (Store, Result);
      Write_File
        (Config_Path,
         "[coordinator]" & ASCII.LF & "database = """ & Database_Path & """" & ASCII.LF &
         "[quality]" & ASCII.LF & "database = ""quality.db""" & ASCII.LF &
         "[integrations]" & ASCII.LF & "ada_quality = """ & Fixture_Path & """" & ASCII.LF &
         "model_runner = """ & Fixture_Path & """" & ASCII.LF &
         "[autonomy]" & ASCII.LF & "dry_run = true" & ASCII.LF);

      Output := To_Unbounded_String (Run (Args ("help")));
      Assert (Ada.Strings.Fixed.Index (To_String (Output), "Usage:") > 0, "help route executes");
      Output := To_Unbounded_String (Run (Args ("version")));
      Assert (Ada.Strings.Fixed.Index (To_String (Output), "quality-manager") > 0, "version route executes");
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "--format=json", "doctor")));
      Assert (Ada.Strings.Fixed.Index (To_String (Output), """status"": ""ready""") > 0,
              "doctor route negotiates the fixture");

      for Command of Views loop
         Output := To_Unbounded_String
           (Run (Args ("--config", Config_Path, "--format=json", To_String (Command))));
         Quality_Manager.Schemas.Validate_Versioned_JSON (To_String (Output), 1, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success,
            To_String (Command) & " emits versioned JSON");
      end loop;

      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "maintenance", "--dry-run")));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "daemon", "--once")));

      Write_File
        (Campaign_Path,
         "{""schema_version"":1,""campaign_id"":""cli-campaign""," &
         """definition_revision"":1,""projects"":[" &
         "{""quality_database_id"":""123e4567-e89b-12d3-a456-426614174000""," &
         """project_id"":7,""path"":""/project"",""baseline_assessment"":1}]," &
         """indicators"":[""TST-03""],""target"":""pass"",""work_budget"":2," &
         """priority_rule"":""campaign"",""autonomy_policy_digest"":""policy""}");
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "campaign-create", Campaign_Path)));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "campaign-start", "cli-campaign")));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "campaign-pause", "cli-campaign")));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "campaign-resume", "cli-campaign")));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "campaign-reconcile", "cli-campaign")));

      Write_File
        (Approval_Path,
         "{""schema_version"":1,""decision"":""approve""," &
         """approval_id"":""cli-approval"",""quality_database_id"":""database-a""," &
         """quality_project_id"":7,""canonical_path"":""/project""," &
         """plan_id"":""PLAN-001"",""plan_revision"":1," &
         """content_sha256"":""content"",""authorized_action"":""publish""," &
         """policy_sha256"":""policy"",""approver"":""operator""," &
         """created_at"":1,""expires_at"":2}");
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "approve", Approval_Path)));
      Write_File
        (Approval_Path,
         "{""schema_version"":1,""decision"":""reject""," &
         """approval_id"":""cli-rejection"",""quality_database_id"":""database-a""," &
         """quality_project_id"":7,""canonical_path"":""/project""," &
         """plan_id"":""PLAN-002"",""plan_revision"":1," &
         """content_sha256"":""content"",""authorized_action"":""publish""," &
         """policy_sha256"":""policy"",""approver"":""operator""," &
         """created_at"":1,""expires_at"":2}");
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "reject", Approval_Path)));

      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "release-qualify", "missing"), 1));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "release-export", "missing"), 1));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "release-export", "missing",
                    "/tmp/quality-manager-missing-evidence.json"), 1));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "release-create", "missing", "release"), 1));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "maintenance", "--project", "missing"), 1));
      Output := To_Unbounded_String
        (Run (Args ("--config", Config_Path, "approve", "/tmp/no-such-decision.json"), 1));
      Output := To_Unbounded_String
        (Run (Args ("--config", "/tmp/no-such-quality-manager-config.toml", "status"), 1));
      Output := To_Unbounded_String (Run (Args ("unknown-command"), 1));
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_CLI_Executable;

   procedure Test_JSON_Contract (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Result : Quality_Manager.Results.Operation_Result;
   begin
      Quality_Manager.Schemas.Validate_Versioned_JSON
        ("{""schema_version"":1}", 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "matching schema accepted");

      Quality_Manager.Schemas.Validate_Versioned_JSON
        ("{""schema_version"":2}", 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract, "unknown schema rejected");

      Quality_Manager.Schemas.Validate_Versioned_JSON
        ("{""schema_version"":1,""schema_version"":1}", 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate JSON member rejected");

      Quality_Manager.Schemas.Validate_Versioned_JSON
        ("{""schema_version"":1,""kind"":""project-list""}", 1, Result,
         "kind", "project-list");
      Assert (Result.Kind = Quality_Manager.Results.Success, "matching discriminator accepted");

      Quality_Manager.Schemas.Validate_Versioned_JSON
        ("{""schema_version"":1,""kind"":""findings""}", 1, Result,
         "kind", "project-list");
      Assert
        (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
         "mismatched document kind rejected");
   end Test_JSON_Contract;

   procedure Test_Doctor_Output (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Settings : constant Quality_Manager.Config.Settings := Quality_Manager.Config.Defaults;
      Runner   : constant Quality_Manager.Results.Operation_Result :=
        Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success);
      Output   : constant String := Quality_Manager.Reporting.Doctor
        (Settings, Quality_Manager.CLI.JSON_Output, Runner);
      Result   : Quality_Manager.Results.Operation_Result;
   begin
      Quality_Manager.Schemas.Validate_Versioned_JSON (Output, 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "doctor JSON is versioned JSON");
      Assert (Ada.Strings.Fixed.Index (Output, """native_execution"": ""available""") > 0,
              "doctor reports the negotiated native execution contract");
      declare
         Failed : constant Quality_Manager.Results.Operation_Result :=
           Quality_Manager.Results.Make_Result
             (Quality_Manager.Results.Incompatible_Contract,
              "runner contract mismatch", "qm.test.runner");
      begin
         for Format in Quality_Manager.CLI.Output_Format loop
            declare
               Blocked : constant String := Quality_Manager.Reporting.Doctor
                 (Settings, Format, Failed);
            begin
               Assert
                 (Ada.Strings.Fixed.Index (Blocked, "runner contract mismatch") > 0,
                  "every doctor format reports a blocked runner diagnostic");
            end;
         end loop;
         Assert
           (Ada.Strings.Fixed.Index
              (Quality_Manager.Reporting.Doctor
                 (Settings, Quality_Manager.CLI.Terminal_Output, Runner), "ready") > 0
            and then Ada.Strings.Fixed.Index
              (Quality_Manager.Reporting.Doctor
                 (Settings, Quality_Manager.CLI.Markdown_Output, Runner), "ready") > 0,
            "successful doctor output supports terminal and Markdown formats");
      end;
   end Test_Doctor_Output;

   procedure Test_Identities (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Left : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
      Same : constant Quality_Manager.Identities.Project_Key := Left;
      Other : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database-b"), 7, To_Unbounded_String ("/project"));
   begin
      Assert (Quality_Manager.Identities.Equal (Left, Same), "same qualified identity matches");
      Assert (not Quality_Manager.Identities.Equal (Left, Other), "database identity is authoritative");
   end Test_Identities;

   procedure Test_Deterministic_Identities (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
      First : constant String := Quality_Manager.Identities.Work_Identity
        (Project, 3, "AQ-01" & ASCII.LF & "AQ-02", "maintenance:cycle-1");
      Again : constant String := Quality_Manager.Identities.Work_Identity
        (Project, 3, "AQ-01" & ASCII.LF & "AQ-02", "maintenance:cycle-1");
      Campaign : constant String := Quality_Manager.Identities.Work_Identity
        (Project, 3, "AQ-01" & ASCII.LF & "AQ-02", "campaign:coverage");
      Global : constant String := Quality_Manager.Identities.Global_Remediation_Identity
        (Project, 3, "AQ-01" & ASCII.LF & "AQ-02");
   begin
      Assert (First'Length = 64, "SHA-256 identity uses 64 lowercase hex digits");
      Assert (First = Again, "logical identity is deterministic");
      Assert (First /= Campaign, "workflow objectives retain distinct identities");
      Assert (Global /= First and then Global /= Campaign, "global remediation identity is separately framed");
      Assert
        (Quality_Manager.Identities.Operation_Identity ("assessment", First) /= 0
         and then Quality_Manager.Identities.Operation_Identity ("assessment", First)
           = Quality_Manager.Identities.Operation_Identity ("assessment", First)
         and then Quality_Manager.Identities.Operation_Identity ("assessment", First)
           /= Quality_Manager.Identities.Operation_Identity ("publication", First),
         "operation identities are deterministic, nonzero, and purpose-qualified");
      Assert
        (Quality_Manager.Identities.Execution_Identity
           (Quality_Manager.Identities.Dispatch_Identity (First, "plan", 2, "task"), 1)
         /= Quality_Manager.Identities.Execution_Identity
           (Quality_Manager.Identities.Dispatch_Identity (First, "plan", 2, "task"), 2),
         "attempt number participates in execution identity");
   end Test_Deterministic_Identities;

   procedure Test_Transitions_And_Journal (Item : in out Fixture) is
      pragma Unreferenced (Item);
      use Quality_Manager.Model;
      use Quality_Manager.Journal;
      Validation : Quality_Manager.Results.Operation_Result;
   begin
      Assert (Quality_Manager.Transitions.Allowed (Discovered, Planning), "discovered work may enter planning");
      Assert (not Quality_Manager.Transitions.Allowed (Verified, Planning), "verified work cannot reopen");
      Validation := Quality_Manager.Transitions.Validate (Verified, Planning);
      Assert (Validation.Kind = Quality_Manager.Results.Invalid_Request, "terminal transition reports a value error");

      Assert (Action_For (Prepared) = Invoke_After_Revalidation, "prepared operation is revalidated before invoke");
      Assert (Action_For (Invoking) = Query_External_Identity, "invoking operation is queried before retry");
      Assert (Action_For (Reconciling) = Adopt_Confirmed_Result, "confirmed result is adopted");
      Assert (Allowed (Prepared, Invoking), "journal may begin invocation");
      Assert (not Allowed (Committed, Invoking), "committed operation cannot reopen");

      for From_State in Quality_Manager.Journal.Journal_State loop
         for To_State in Quality_Manager.Journal.Journal_State loop
            declare
               Permitted : constant Boolean := Allowed (From_State, To_State);
            begin
               Assert
                 ((From_State = To_State) or else Permitted or else not Permitted,
                  "journal transition table is total");
            end;
         end loop;
         declare
            Action : constant Quality_Manager.Journal.Recovery_Action := Action_For (From_State);
         begin
            Assert
              (Action in Invoke_After_Revalidation | Query_External_Identity
                 | Adopt_Confirmed_Result | No_Action | Preserve_Failure | Escalate,
               "every journal state has an explicit recovery action");
         end;
      end loop;

      for From_State in Quality_Manager.Model.Work_State loop
         for To_State in Quality_Manager.Model.Work_State loop
            declare
               Permitted : constant Boolean := Quality_Manager.Transitions.Allowed
                 (From_State, To_State);
            begin
               Assert
                 ((From_State = To_State) or else Permitted or else not Permitted,
                  "work transition table is total");
            end;
         end loop;
      end loop;
      Validation := Quality_Manager.Transitions.Validate (Discovered, Published);
      Assert
        (Validation.Kind = Quality_Manager.Results.Invalid_Request,
         "invalid nonterminal transition has an explicit diagnostic");

      declare
         Values : constant array (Positive range <>) of Natural :=
           [0, 99, 100, 199, 200, 299, 300, 399, 400, 499, 500];
      begin
         for Value of Values loop
            declare
               Class : constant Quality_Manager.Priorities.Priority_Class :=
                 Quality_Manager.Priorities.From_Persisted_Priority (Value);
            begin
               Assert
                 ((Value < 100 and then Class = Quality_Manager.Priorities.Long_Standing_Deficiency)
                  or else (Value in 100 .. 199 and then Class = Quality_Manager.Priorities.Campaign_Work)
                  or else (Value in 200 .. 299 and then Class = Quality_Manager.Priorities.New_Regression)
                  or else (Value in 300 .. 399
                           and then Class = Quality_Manager.Priorities.Security_Or_Correctness)
                  or else (Value in 400 .. 499 and then Class = Quality_Manager.Priorities.Release_Blocker)
                  or else (Value >= 500 and then Class = Quality_Manager.Priorities.Critical_Regression),
                  "persisted priority mapping is total");
            end;
         end loop;
      end;
      Assert
        (Quality_Manager.Priorities.Before
           ((To_Unbounded_String ("b"), Quality_Manager.Priorities.Critical_Regression, 2),
            (To_Unbounded_String ("a"), Quality_Manager.Priorities.Release_Blocker, 1)),
         "priority class orders before age");
      Assert
        (Quality_Manager.Priorities.Before
           ((To_Unbounded_String ("b"), Quality_Manager.Priorities.Campaign_Work, 1),
            (To_Unbounded_String ("a"), Quality_Manager.Priorities.Campaign_Work, 2)),
         "age orders within a priority class");
      Assert
        (Quality_Manager.Priorities.Before
           ((To_Unbounded_String ("a"), Quality_Manager.Priorities.Campaign_Work, 1),
            (To_Unbounded_String ("b"), Quality_Manager.Priorities.Campaign_Work, 1)),
         "stable identity breaks equal-priority ties");

      declare
         Schema_Check : Quality_Manager.Storage.Schema.Metadata;
      begin
         Assert (Schema_Check.Schema_Version = 1, "logical schema version is explicit");
      end;
      Assert (Quality_Manager.Storage.Migrations.Can_Migrate (0, 1), "initial schema migration is registered");
      Validation := Quality_Manager.Storage.Migrations.Validate_Current (2);
      Assert (Validation.Kind = Quality_Manager.Results.Incompatible_Contract, "newer schema is rejected");
   end Test_Transitions_And_Journal;

   procedure Test_Persistent_Storage (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path      : constant String := "/tmp/quality-manager-phase2.database";
      Nested_Root : constant String := "/tmp/quality-manager-parent-creation";
      Nested_Path : constant String := Nested_Root & "/nested/coordinator.database";
      Store     : Quality_Manager.Storage.Store;
      Result    : Quality_Manager.Results.Operation_Result;
      Work      : Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1,
         Kind => Quality_Manager.Storage.Work_Item_Record,
         Entity_Key => To_Unbounded_String ("work:test"),
         State => To_Unbounded_String (Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Discovered)),
         Payload => To_Unbounded_String ("finding=AQ-01"),
         Terminal => False,
         Generation => 1);
      Loaded    : Quality_Manager.Storage.Stored_Entity;
      Identity  : Unbounded_String;
      Recovery  : Quality_Manager.Storage.Entity_Vectors.Vector;

      procedure Remove (Name : String) is
      begin
         if Ada.Directories.Exists (Name) then
            Ada.Directories.Delete_File (Name);
         end if;
      end Remove;

      procedure Cleanup is
      begin
         Remove (Path);
         Remove (Path & ".wal");
         Remove (Path & ".journal");
         Remove (Path & ".lock");
      end Cleanup;

   begin
      if Ada.Directories.Exists (Nested_Root) then
         Ada.Directories.Delete_Tree (Nested_Root);
      end if;
      Quality_Manager.Storage.Open (Store, Nested_Path, True, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success,
         "writable store creates its configured parent path: " & Quality_Manager.Results.Message (Result));
      Assert (Ada.Directories.Exists (Nested_Path), "nested coordinator database was created");
      Quality_Manager.Storage.Close (Store, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "nested coordinator database closes");
      Ada.Directories.Delete_Tree (Nested_Root);

      Assert
        (Quality_Manager.Maintenance.Due_Reason
           ((Assessment_Run => 4, Assessment_Complete => True,
             Previous_Source => To_Unbounded_String ("source-a"),
             Current_Source => To_Unbounded_String ("source-b"),
             Previous_Policy => To_Unbounded_String ("policy"),
             Current_Policy => To_Unbounded_String ("policy"),
             Previous_Toolchain => To_Unbounded_String ("toolchain"),
             Current_Toolchain => To_Unbounded_String ("toolchain"), Refresh_Due => False))
         = Quality_Manager.Maintenance.Source_Changed,
         "source identity changes make authoritative assessment due");
      Assert
        (not Quality_Manager.Maintenance.Assessment_Due
           ((Assessment_Run => 4, Assessment_Complete => True,
             Previous_Source => To_Unbounded_String ("source"),
             Current_Source => To_Unbounded_String ("source"),
             Previous_Policy => To_Unbounded_String ("policy"),
             Current_Policy => To_Unbounded_String ("policy"),
             Previous_Toolchain => To_Unbounded_String ("toolchain"),
             Current_Toolchain => To_Unbounded_String ("toolchain"), Refresh_Due => False)),
         "compatible current evidence is reusable");
      declare
         Evidence : Quality_Manager.Maintenance.Evidence_Identity :=
           (Assessment_Run => 0, Assessment_Complete => True,
            Previous_Source => To_Unbounded_String ("source"),
            Current_Source => To_Unbounded_String ("source"),
            Previous_Policy => To_Unbounded_String ("policy"),
            Current_Policy => To_Unbounded_String ("policy"),
            Previous_Toolchain => To_Unbounded_String ("toolchain"),
            Current_Toolchain => To_Unbounded_String ("toolchain"),
            Refresh_Due => False);
      begin
         Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                   Quality_Manager.Maintenance.No_Assessment,
                 "missing assessment is due");
         Evidence.Assessment_Run := 1;
         Evidence.Assessment_Complete := False;
         Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                   Quality_Manager.Maintenance.Evidence_Incomplete,
                 "incomplete assessment is due");
         Evidence.Assessment_Complete := True;
         Evidence.Current_Policy := To_Unbounded_String ("changed-policy");
         Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                   Quality_Manager.Maintenance.Policy_Changed,
                 "policy change is due");
         Evidence.Current_Policy := Evidence.Previous_Policy;
         Evidence.Current_Toolchain := To_Unbounded_String ("changed-toolchain");
         Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                   Quality_Manager.Maintenance.Toolchain_Changed,
                 "toolchain change is due");
         Evidence.Current_Toolchain := Evidence.Previous_Toolchain;
         Evidence.Refresh_Due := True;
         Assert (Quality_Manager.Maintenance.Due_Reason (Evidence) =
                   Quality_Manager.Maintenance.Scheduled_Refresh,
                 "scheduled refresh is due");
      end;
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "persistent store created: " &
              Quality_Manager.Results.Message (Result));
      Identity := To_Unbounded_String (Quality_Manager.Storage.Identity (Store));
      Assert (Length (Identity) > 0, "store has durable installation identity");

      declare
         Project : constant Quality_Manager.Identities.Project_Key :=
           (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
         Typed_Work : constant Quality_Manager.Storage.Schema.Work_Item :=
           (Work_Id => To_Unbounded_String ("work:typed"),
            Global_Remediation => To_Unbounded_String ("remediation:AQ-02"),
            Project => Project,
            Origin => Quality_Manager.Model.Maintenance,
            Finding_Identities => To_Unbounded_String ("AQ-02"),
            Priority => 10,
            Improve_Plan_Id => Null_Unbounded_String,
            Improve_Revision => 0,
            Improve_Task_Id => Null_Unbounded_String,
            State => Quality_Manager.Model.Discovered,
            Outcome => Quality_Manager.Model.No_Outcome);
         Dispatch : Quality_Manager.Storage.Schema.Dispatch :=
           (Dispatch_Id => To_Unbounded_String ("dispatch:one"),
            Work_Id => To_Unbounded_String ("work:typed"),
            Logical_Remediation => To_Unbounded_String ("remediation:AQ-02"),
            Improve_Task =>
              (Plan_Id => To_Unbounded_String ("plan-1"), Revision => 1,
               Task_Id => To_Unbounded_String ("task-1")),
            Native_Task_Id => To_Unbounded_String ("native-1"),
            Authorization_Id => To_Unbounded_String ("approval-1"),
            State => Quality_Manager.Model.Published,
            Active => True);
      begin
         Quality_Manager.Storage.Records.Save (Store, Typed_Work, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "typed work operation persisted");
         Quality_Manager.Storage.Records.Save (Store, Dispatch, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "active dispatch persisted");
         Dispatch.Dispatch_Id := To_Unbounded_String ("dispatch:two");
         Dispatch.Native_Task_Id := To_Unbounded_String ("native-2");
         Quality_Manager.Storage.Records.Save (Store, Dispatch, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Integrity_Error,
            "second active dispatch for logical remediation is rejected");
      end;

      Quality_Manager.Storage.Put (Store, Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "work persisted");
      Quality_Manager.Storage.Put (Store, Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "same work insert is idempotent");
      Work.Payload := To_Unbounded_String ("finding=different");
      Quality_Manager.Storage.Put (Store, Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "conflicting identity is rejected");
      Work.Payload := To_Unbounded_String ("finding=AQ-01");

      Quality_Manager.Storage.Transition_Work
        (Store, "work:test", Quality_Manager.Model.Discovered, Quality_Manager.Model.Planning,
         "event:test:planning", "test", "assessment:1", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "transition and event committed");
      Quality_Manager.Storage.Read (Store, "work:test", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Planning),
         "new work state persisted");
      Quality_Manager.Storage.Read (Store, "event:test:planning", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Loaded.Kind = Quality_Manager.Storage.Event_Record,
         "transition event persisted atomically");
      Quality_Manager.Storage.Transition_Work
        (Store, "work:test", Quality_Manager.Model.Planning, Quality_Manager.Model.Awaiting_Approval,
         "event:test:planning", "duplicate event", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "duplicate event aborts transition");
      Quality_Manager.Storage.Read (Store, "work:test", Loaded, Result);
      Assert
        (To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Planning),
         "failed transaction leaves work state unchanged");

      Quality_Manager.Storage.Acquire_Lease (Store, "project:7", "owner-a", 0, 1, 100, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "initial lease acquired");
      Quality_Manager.Storage.Acquire_Lease (Store, "project:7", "owner-b", 0, 2, 200, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "obsolete lease generation rejected");
      Quality_Manager.Storage.Acquire_Lease (Store, "project:7", "owner-a", 1, 2, 200, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "current lease generation renewed");

      Quality_Manager.Storage.Prepare_Operation
        (Store, 10, "assessment", "run authoritative check", "aq:operation-10", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "journal intent prepared");
      Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Natural (Recovery.Length) = 1,
         "prepared operation reconstructed for recovery");
      Quality_Manager.Storage.Advance_Operation
        (Store, 10, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         "aq:operation-10", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "journal invocation recorded");
      Quality_Manager.Storage.Advance_Operation
        (Store, 10, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
         "aq:operation-10", "completed externally", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "journal reconciliation recorded");
      Quality_Manager.Storage.Advance_Operation
        (Store, 10, Quality_Manager.Journal.Reconciling, Quality_Manager.Journal.Committed,
         "aq:operation-10", "adopted", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "journal completion recorded");
      Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Recovery.Is_Empty,
         "committed operation excluded from recovery");
      Quality_Manager.Storage.Advance_Operation
        (Store, 10, Quality_Manager.Journal.Committed, Quality_Manager.Journal.Invoking,
         "aq:operation-10", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "terminal journal cannot reopen");
      Quality_Manager.Storage.Prepare_Operation
        (Store, 11, "publication", "publish authorized task", "improve:operation-11", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "interrupted operation prepared");

      Quality_Manager.Storage.Close (Store, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "store closed");
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "store reopened: " &
              Quality_Manager.Results.Message (Result));
      Assert (Quality_Manager.Storage.Identity (Store) = To_String (Identity), "store identity survives reopen");
      Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Natural (Recovery.Length) = 1,
         "interrupted operation reconstructed after restart");
      Quality_Manager.Storage.Advance_Operation
        (Store, 11, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         "improve:operation-11", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "recovered prepared operation advances");
      Quality_Manager.Storage.Close (Store, Result);
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
      Assert
        (Natural (Recovery.Length) = 1
         and then To_String (Recovery.First_Element.State)
           = Quality_Manager.Journal.Journal_State'Image (Quality_Manager.Journal.Invoking),
         "invoking boundary survives restart without reinvocation");
      Quality_Manager.Storage.Advance_Operation
        (Store, 11, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
         "improve:operation-11", "external result found", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "recovered invocation enters reconciliation");
      Quality_Manager.Storage.Close (Store, Result);
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Quality_Manager.Storage.Recovery_Entries (Store, Recovery, 10, Result);
      Assert
        (Natural (Recovery.Length) = 1
         and then To_String (Recovery.First_Element.State)
           = Quality_Manager.Journal.Journal_State'Image (Quality_Manager.Journal.Reconciling),
         "reconciling boundary survives restart for adoption");
      Quality_Manager.Storage.Advance_Operation
        (Store, 11, Quality_Manager.Journal.Reconciling, Quality_Manager.Journal.Committed,
         "improve:operation-11", "adopted", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "recovered result committed");
      Quality_Manager.Storage.Read (Store, "work:test", Loaded, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "work survives reopen");
      Quality_Manager.Storage.Close (Store, Result);
      Quality_Manager.Storage.Open (Store, Path, False, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "read-only status store opened");
      Quality_Manager.Storage.Put (Store, Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required, "read-only store rejects mutation");
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Persistent_Storage;

   procedure Test_Storage_Boundaries (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path   : constant String := "/tmp/quality-manager-storage-boundaries.database";
      Store  : Quality_Manager.Storage.Store;
      Result : Quality_Manager.Results.Operation_Result;
      Values : Quality_Manager.Storage.Entity_Vectors.Vector;
      Loaded : Quality_Manager.Storage.Stored_Entity;

      procedure Remove (Name : String) is
      begin
         if Ada.Directories.Exists (Name) then Ada.Directories.Delete_File (Name); end if;
      end Remove;

      procedure Cleanup is
      begin
         Remove (Path);
         Remove (Path & ".wal");
         Remove (Path & ".journal");
         Remove (Path & ".lock");
      end Cleanup;

      function Entity
        (Key : String;
         Kind : Quality_Manager.Storage.Record_Kind := Quality_Manager.Storage.Work_Item_Record)
         return Quality_Manager.Storage.Stored_Entity is
        ((Internal_Id => 1, Kind => Kind, Entity_Key => To_Unbounded_String (Key),
          State => To_Unbounded_String (Quality_Manager.Model.Work_State'Image
            (Quality_Manager.Model.Discovered)),
          Payload => To_Unbounded_String ("boundary"), Terminal => False, Generation => 1));
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, False, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found, "read-only open rejects a missing database");
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "boundary store created");
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "opening an open store safely reopens it");

      declare
         Invalid : Quality_Manager.Storage.Stored_Entity := Entity ("");
      begin
         Quality_Manager.Storage.Put (Store, Invalid, Result);
         Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty entity key is rejected");
         Invalid := Entity ("generation-zero");
         Invalid.Generation := 0;
         Quality_Manager.Storage.Put (Store, Invalid, Result);
         Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "zero generation is rejected");
         Invalid := Entity ("metadata:external", Quality_Manager.Storage.Metadata_Record);
         Quality_Manager.Storage.Put (Store, Invalid, Result);
         Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
                 "external metadata mutation is rejected");
         Invalid := Entity ("event:nonterminal", Quality_Manager.Storage.Event_Record);
         Quality_Manager.Storage.Put (Store, Invalid, Result);
         Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
                 "nonterminal append-only event is rejected");
         Invalid := Entity ("work:unknown-state");
         Invalid.State := To_Unbounded_String ("UNKNOWN");
         Quality_Manager.Storage.Put (Store, Invalid, Result);
         Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
                 "unknown persisted work state is rejected");
         Invalid := Entity ("journal:unknown", Quality_Manager.Storage.Journal_Record);
         Invalid.State := To_Unbounded_String ("UNKNOWN");
         Quality_Manager.Storage.Put (Store, Invalid, Result);
         Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
                 "unknown persisted journal state is rejected");
      end;

      Quality_Manager.Storage.Put_Current (Store, Entity ("work:not-current"), Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "append-only record class cannot use current-record replacement");
      declare
         Current : Quality_Manager.Storage.Stored_Entity :=
           Entity ("project:current-idempotent", Quality_Manager.Storage.Project_Record);
      begin
         Quality_Manager.Storage.Put_Current (Store, Current, Result);
         Quality_Manager.Storage.Read (Store, "project:current-idempotent", Loaded, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success and then Loaded.Generation = 1,
                 "new current record starts at generation one");
         Quality_Manager.Storage.Put_Current (Store, Current, Result);
         Quality_Manager.Storage.Read (Store, "project:current-idempotent", Loaded, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success and then Loaded.Generation = 1,
                 "idempotent current-record replay does not advance its fencing generation");
         Current.Payload := To_Unbounded_String ("changed");
         Quality_Manager.Storage.Put_Current (Store, Current, Result);
         Quality_Manager.Storage.Read (Store, "project:current-idempotent", Loaded, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success and then Loaded.Generation = 2,
                 "changed current-record content advances its generation once");
      end;
      Quality_Manager.Storage.Put (Store, Entity ("work:boundary-1"), Result);
      Quality_Manager.Storage.Put (Store, Entity ("work:boundary-2"), Result);
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Work_Item_Record, Values, 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "bounded scans fail on overflow");
      Quality_Manager.Storage.Read (Store, "missing", Loaded, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing entity read is explicit");
      Quality_Manager.Storage.Transition_Work
        (Store, "work:boundary-1", Quality_Manager.Model.Planning, Quality_Manager.Model.Queued,
         "event:boundary", "stale", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "stale transition precondition is rejected");
      Quality_Manager.Storage.Acquire_Lease
        (Store, "boundary", "owner", 1, 1, 10, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "lease generation must increase");
      Quality_Manager.Storage.Acquire_Lease
        (Store, "boundary", "owner", 1, 2, 10, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "new lease requires generation zero");
      Quality_Manager.Storage.Advance_Operation
        (Store, 500, Quality_Manager.Journal.Committed, Quality_Manager.Journal.Invoking,
         "external", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "invalid journal transition is rejected before mutation");
      Quality_Manager.Storage.Advance_Operation
        (Store, 500, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         "external", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "missing journal operation is explicit");

      Quality_Manager.Storage.Close (Store, Result);
      Quality_Manager.Storage.Put (Store, Entity ("work:closed"), Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "closed store cannot be mutated");
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Storage_Boundaries;

   procedure Test_Corrupt_Storage (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path   : constant String := "/tmp/quality-manager-corrupt.database";
      File   : Ada.Text_IO.File_Type;
      Store  : Quality_Manager.Storage.Store;
      Result : Quality_Manager.Results.Operation_Result;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (File, "not a coordinator database");
      Ada.Text_IO.Close (File);
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "corrupt database is rejected explicitly");
      Assert (not Quality_Manager.Storage.Is_Open (Store), "corrupt database is not silently repaired");
      Ada.Directories.Delete_File (Path);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Quality_Manager.Storage.Close (Store, Result);
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
         raise;
   end Test_Corrupt_Storage;

   procedure Test_Process_Adapter (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Request : Quality_Manager.Integrations.Processes.Request;
      Result  : Quality_Manager.Integrations.Processes.Execution_Result;
   begin
      Request.Executable := To_Unbounded_String ("/usr/bin/printf");
      Request.Arguments.Append (To_Unbounded_String ("%s"));
      Request.Arguments.Append (To_Unbounded_String ("literal;not-a-command"));
      Request.Output_Limit := 1_024;
      Quality_Manager.Integrations.Processes.Execute (Request, Result);
      Assert
        (Result.Started and then Result.Exit_Status = 0
         and then To_String (Result.Standard_Output) = "literal;not-a-command",
         "argument vector is executed without shell interpretation");

      Request.Arguments.Clear;
      Request.Executable := To_Unbounded_String ("/usr/bin/env");
      Request.Environment.Append (To_Unbounded_String ("QM_VISIBLE=yes"));
      Quality_Manager.Integrations.Processes.Execute (Request, Result);
      Assert
        (To_String (Result.Standard_Output) = "QM_VISIBLE=yes" & ASCII.LF,
         "child receives only the explicit environment allowlist");

      Request.Environment.Clear;
      Request.Executable := To_Unbounded_String ("/usr/bin/printf");
      Request.Arguments.Append (To_Unbounded_String ("12345678901234567890"));
      Request.Output_Limit := 8;
      Quality_Manager.Integrations.Processes.Execute (Request, Result);
      Assert
        (Result.Output_Exceeded and then Length (Result.Standard_Output) <= 8,
         "captured output is bounded");

      Request.Executable := To_Unbounded_String ("quality-manager-no-such-executable");
      Request.Arguments.Clear;
      Quality_Manager.Integrations.Processes.Execute (Request, Result);
      Assert (not Result.Started, "missing executable is classified before invocation");
   end Test_Process_Adapter;

   procedure Test_JSON_CLI_Contracts (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Args : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Env  : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Response : Quality_Manager.Integrations.JSON_CLI.Response;

      procedure Run
        (Exit_Code : String; JSON : String;
         Contract : Quality_Manager.Integrations.JSON_CLI.Exit_Contract;
         Version : Positive := 1) is
      begin
         Args.Clear;
         Args.Append (To_Unbounded_String (Exit_Code));
         Args.Append (To_Unbounded_String (JSON));
         Quality_Manager.Integrations.JSON_CLI.Execute
           ("./bin/qm_adapter_fixture", Args, "", Env, Contract, Version, 10, 4_096, Response);
      end Run;
   begin
      Run ("0", "{""schema_version"":1}", Quality_Manager.Integrations.JSON_CLI.Ada_Quality_Contract);
      Assert (Response.Status.Kind = Quality_Manager.Results.Success, "quality success normalized");
      Run ("1", "{""schema_version"":1}", Quality_Manager.Integrations.JSON_CLI.Ada_Quality_Contract);
      Assert (Response.Status.Kind = Quality_Manager.Results.Negative_Result, "violations are not execution failure");
      Run ("3", "{""schema_version"":1}", Quality_Manager.Integrations.JSON_CLI.Ada_Quality_Contract);
      Assert (Response.Status.Kind = Quality_Manager.Results.Stale_Evidence, "incomplete evidence is explicit");
      Run ("0", "{""schema_version"":999}", Quality_Manager.Integrations.JSON_CLI.Summary_Contract);
      Assert
        (Response.Status.Kind = Quality_Manager.Results.Incompatible_Contract,
         "unknown upstream schema prevents mutation");
      Run ("4", "", Quality_Manager.Integrations.JSON_CLI.Summary_Contract);
      Assert (Response.Status.Kind = Quality_Manager.Results.Integrity_Error, "summary database failure normalized");
      Run ("130", "", Quality_Manager.Integrations.JSON_CLI.Improve_Contract, 2);
      Assert (Response.Status.Kind = Quality_Manager.Results.Interrupted, "Improve interruption normalized");
      Run ("0", "invalid-utf8", Quality_Manager.Integrations.JSON_CLI.Ada_Quality_Contract);
      Assert (Response.Status.Kind = Quality_Manager.Results.Incompatible_Contract, "invalid UTF-8 rejected");

      declare
         Adapter : Quality_Manager.Integrations.Improve.Adapter;
      begin
         Quality_Manager.Integrations.Improve.Initialize
           (Adapter, "improve", "config.toml", "quality.db", "improve.db");
         Quality_Manager.Integrations.Improve.Approve_Exact_Revision
           (Adapter, "PLAN-001", 1, "digest", Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Incompatible_Contract,
            "autonomous approval fenced until atomic upstream contract exists");
      end;

      declare
         Quality_Adapter : Quality_Manager.Integrations.Quality.Adapter;
         Summary_Adapter : Quality_Manager.Integrations.Summary.Adapter;
         Improve_Adapter : Quality_Manager.Integrations.Improve.Adapter;
         Runner_Adapter  : Quality_Manager.Integrations.Runner.Adapter;
         Database_Identity : Unbounded_String;
         Identity_Result : Quality_Manager.Results.Operation_Result;
      begin
         Quality_Manager.Integrations.Quality.Initialize
           (Quality_Adapter, "./bin/qm_adapter_fixture", "quality.db");
         Quality_Manager.Integrations.Quality.Resolve_Database_Identity
           (Quality_Adapter, Database_Identity, Identity_Result);
         Assert
           (Identity_Result.Kind = Quality_Manager.Results.Success
            and then To_String (Database_Identity) = "123e4567-e89b-12d3-a456-426614174000",
            "Ada Quality durable database identity is validated and retained");
         Quality_Manager.Integrations.Quality.Initialize
           (Quality_Adapter, "./bin/qm_adapter_fixture", "missing-identity.db");
         Quality_Manager.Integrations.Quality.Resolve_Database_Identity
           (Quality_Adapter, Database_Identity, Identity_Result);
         Assert
           (Identity_Result.Kind = Quality_Manager.Results.Incompatible_Contract
            and then Length (Database_Identity) = 0,
            "missing Ada Quality database identity fails closed");
         Quality_Manager.Integrations.Quality.Initialize
           (Quality_Adapter, "./bin/qm_adapter_fixture", "invalid-identity.db");
         Quality_Manager.Integrations.Quality.Resolve_Database_Identity
           (Quality_Adapter, Database_Identity, Identity_Result);
         Assert
           (Identity_Result.Kind = Quality_Manager.Results.Incompatible_Contract
            and then Length (Database_Identity) = 0,
            "noncanonical Ada Quality database identity fails closed");
         Quality_Manager.Integrations.Quality.Initialize
           (Quality_Adapter, "./bin/qm_adapter_fixture", "quality.db");
         Quality_Manager.Integrations.Quality.List_Projects (Quality_Adapter, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), """projects""") > 0,
            "Ada Quality project inventory requires project-list-v1");
         Quality_Manager.Integrations.Quality.Plan_Check
           (Quality_Adapter, "7", "ci", False, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index
              (To_String (Response.Document), """source_fingerprint"":""candidate-source""") > 0
            and then Ada.Strings.Fixed.Index
              (To_String (Response.Document), """policy_fingerprint"":""policy""") > 0,
            "Ada Quality planning requires check-plan-v1");
         Quality_Manager.Integrations.Quality.Read_Assessment (Quality_Adapter, 4, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), "assessment show 4 --json") > 0,
            "Ada Quality assessment command is exact and versioned");
         Quality_Manager.Integrations.Quality.Compare (Quality_Adapter, 1, 2, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), """baseline_id"":1") > 0
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), """current_id"":2") > 0,
            "Ada Quality comparison preserves both selected assessments");
         Quality_Manager.Integrations.Quality.Check_Environment (Quality_Adapter, "7", Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), "doctor --project 7 --json") > 0,
            "Ada Quality doctor requires doctor-report-v1");

         Quality_Manager.Integrations.Summary.Initialize
           (Summary_Adapter, "./bin/qm_adapter_fixture", "quality.db");
         Quality_Manager.Integrations.Summary.Read_Problems (Summary_Adapter, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), "problems") > 0,
            "Summary problems command is versioned JSON");
         Quality_Manager.Integrations.Summary.Read_Portfolio (Summary_Adapter, Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Summary portfolio is exposed");
         Quality_Manager.Integrations.Summary.Read_Regressions (Summary_Adapter, Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Summary regressions are exposed");
         Quality_Manager.Integrations.Summary.Read_Indicators (Summary_Adapter, Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Summary indicators are exposed");
         Quality_Manager.Integrations.Summary.Read_Trends (Summary_Adapter, Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Summary trends are exposed");
         Quality_Manager.Integrations.Summary.Read_Project_Status (Summary_Adapter, "7", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Summary project status is exposed");

         Quality_Manager.Integrations.Improve.Initialize
           (Improve_Adapter, "./bin/qm_adapter_fixture", "improve.toml", "quality.db", "improve.db");
         Quality_Manager.Integrations.Improve.Read_Plan (Improve_Adapter, "PLAN-001", 2, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index
              (To_String (Response.Document), "plan show PLAN-001 --revision 2") > 0,
            "Improve exact-revision command uses schema version 2");
         Quality_Manager.Integrations.Improve.Generate_Plan (Improve_Adapter, "7", 4, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index
              (To_String (Response.Document), "plan --project 7 --run 4") > 0,
            "Improve planning binds the exact assessment run");
         Quality_Manager.Integrations.Improve.Inspect_Approval
           (Improve_Adapter, "PLAN-001", 2, Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve approval inspection is exposed");
         Quality_Manager.Integrations.Improve.Approve_Exact_Revision
           (Improve_Adapter, "PLAN-001", 2, "digest", Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Incompatible_Contract,
            "autonomous approval fails closed until Improve supports atomic exact revision approval");
         Quality_Manager.Integrations.Improve.Preflight_Publication
           (Improve_Adapter, "PLAN-001", "IMP-001", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve preflight is exposed");
         Quality_Manager.Integrations.Improve.Publish_Task
           (Improve_Adapter, "PLAN-001", "IMP-001", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve publication is exposed");
         Quality_Manager.Integrations.Improve.Read_Task_State
           (Improve_Adapter, "IMP-001", 2, Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve task state is exposed");
         Quality_Manager.Integrations.Improve.Read_Plan_State
           (Improve_Adapter, "PLAN-001", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve plan state is exposed");
         Quality_Manager.Integrations.Improve.Verify_Task
           (Improve_Adapter, "IMP-001", 2, 4, Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve task verification is exposed");
         Quality_Manager.Integrations.Improve.Verify_Project
           (Improve_Adapter, "7", 2, 4, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index
              (To_String (Response.Document), "verify --project 7 --revision 2 --run 4") > 0,
            "Improve project verification binds plan revision and assessment");
         Quality_Manager.Integrations.Improve.Recover_Publication (Improve_Adapter, Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve publication recovery is exposed");
         Quality_Manager.Integrations.Improve.Export_Audit (Improve_Adapter, "PLAN-001", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve audit export is exposed");

         Quality_Manager.Integrations.Runner.Initialize
           (Runner_Adapter, "./bin/qm_adapter_fixture");
         Quality_Manager.Integrations.Runner.Capabilities (Runner_Adapter, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success,
            "model_runner required headless capabilities are negotiated");
         Quality_Manager.Integrations.Runner.Inspect
           (Runner_Adapter, "/project", "TASK-001", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success,
                 "native task inspection is exposed");

         declare
            Request  : Quality_Manager.Integrations.Runner.Execution_Request :=
              (Project_Path                => To_Unbounded_String ("/project"),
               Task_Id                     => To_Unbounded_String ("TASK-001"),
               Operation_Id                => To_Unbounded_String ("qm-execution-1"),
               Expected_Task_Revision      => To_Unbounded_String ("task-revision"),
               Expected_Project_Identity   => To_Unbounded_String ("project-identity"),
               Expected_Source_Fingerprint => To_Unbounded_String ("source-fingerprint"),
               Execution_Policy            => To_Unbounded_String ("policy-fingerprint"),
               Timeout_Seconds             => 60);
            Snapshot : Quality_Manager.Integrations.Runner.Task_Snapshot;
            Checked  : Quality_Manager.Results.Operation_Result;
         begin
            Quality_Manager.Integrations.Runner.Execute (Runner_Adapter, Request, Response);
            Assert
              (Response.Status.Kind = Quality_Manager.Results.Success
               and then Ada.Strings.Fixed.Index
                 (To_String (Response.Document), "--operation-id qm-execution-1") > 0
               and then Ada.Strings.Fixed.Index
                 (To_String (Response.Document), "--noninteractive") > 0,
               "native execution binds the durable operation and is noninteractive");
            Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Checked);
            Assert
              (Checked.Kind = Quality_Manager.Results.Success
               and then Snapshot.State =
                 Quality_Manager.Integrations.Runner.Awaiting_Integration_State,
               "native state is explicitly normalized");
            Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
            Assert
              (Checked.Kind = Quality_Manager.Results.Success,
               "native outcome retains exact dispatch identities");

            Request.Expected_Source_Fingerprint := To_Unbounded_String ("changed-source");
            Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
            Assert
              (Checked.Kind = Quality_Manager.Results.Stale_Evidence,
               "changed source invalidates the native dispatch");

            Request.Expected_Source_Fingerprint := To_Unbounded_String ("source-fingerprint");
            Snapshot.Operation_Id := To_Unbounded_String ("different-operation");
            Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
            Assert (Checked.Kind = Quality_Manager.Results.Integrity_Error,
                    "native operation identity mismatch is rejected");
            Snapshot.Operation_Id := Request.Operation_Id;
            Snapshot.Task_Id := To_Unbounded_String ("different-task");
            Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
            Assert (Checked.Kind = Quality_Manager.Results.Integrity_Error,
                    "native task identity mismatch is rejected");
            Snapshot.Task_Id := Request.Task_Id;
            Snapshot.Task_Revision := To_Unbounded_String ("different-revision");
            Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
            Assert (Checked.Kind = Quality_Manager.Results.Stale_Evidence,
                    "native task revision mismatch is rejected");
            Snapshot.Task_Revision := Request.Expected_Task_Revision;
            Snapshot.Project_Identity := To_Unbounded_String ("different-project");
            Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
            Assert (Checked.Kind = Quality_Manager.Results.Integrity_Error,
                    "native project identity mismatch is rejected");
            Snapshot.Project_Identity := Request.Expected_Project_Identity;
            Snapshot.Execution_Policy := To_Unbounded_String ("different-policy");
            Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
            Assert (Checked.Kind = Quality_Manager.Results.Authorization_Required,
                    "native execution policy mismatch is rejected");
            Snapshot.Execution_Policy := Request.Execution_Policy;
            Request.Operation_Id := To_Unbounded_String ("qm-execution-3");
            Quality_Manager.Integrations.Runner.Execute (Runner_Adapter, Request, Response);
            Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Checked);
            Assert
              (Checked.Kind = Quality_Manager.Results.Incompatible_Contract,
               "unknown or explicitly incompatible native state fails closed");
         end;

         Quality_Manager.Integrations.Runner.Status
           (Runner_Adapter, "/project", "qm-execution-1", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "native status is queryable");
         Quality_Manager.Integrations.Runner.Status
           (Runner_Adapter, "/project", "missing-operation", Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Not_Found,
            "native error code is normalized independently of its process exit class");
         Quality_Manager.Integrations.Runner.Cancel
           (Runner_Adapter, "/project", "qm-execution-1", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "native cancellation is exposed");
         Quality_Manager.Integrations.Runner.Recover (Runner_Adapter, "/project", Response);
         Assert (Response.Status.Kind = Quality_Manager.Results.Success, "native recovery is exposed");
         Quality_Manager.Integrations.Runner.Integrate
           (Runner_Adapter, "/project", "qm-execution-1", Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index
              (To_String (Response.Document), "--authorization conflict-free") > 0,
            "integration is restricted to the conflict-free native gate");
      end;

      for Contract in Quality_Manager.Integrations.JSON_CLI.Exit_Contract loop
         for Status in 1 .. 9 loop
            Run
              (Ada.Strings.Fixed.Trim (Integer'Image (Status), Ada.Strings.Both),
               "", Contract, (if Contract = Quality_Manager.Integrations.JSON_CLI.Improve_Contract then 2 else 1));
            Assert
              (Response.Status.Kind /= Quality_Manager.Results.Success,
               "every nonzero upstream exit class is normalized explicitly");
         end loop;
      end loop;

      Args.Clear;
      Quality_Manager.Integrations.JSON_CLI.Execute
        ("/tmp/no-such-quality-manager-executable", Args, "", Env,
         Quality_Manager.Integrations.JSON_CLI.Ada_Quality_Contract,
         1, 1, 1_024, Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Execution_Error,
              "JSON CLI reports process start failures");

      Args.Append (To_Unbounded_String ("2"));
      Quality_Manager.Integrations.JSON_CLI.Execute
        ("/bin/sleep", Args, "", Env,
         Quality_Manager.Integrations.JSON_CLI.Ada_Quality_Contract,
         1, 1, 1_024, Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Temporarily_Unavailable,
              "JSON CLI reports process deadlines");
   end Test_JSON_CLI_Contracts;

   procedure Test_Native_Dispatch (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path     : constant String := "/tmp/quality-manager-native-dispatch.database";
      Store    : Quality_Manager.Storage.Store;
      Runner   : Quality_Manager.Integrations.Runner.Adapter;
      Result   : Quality_Manager.Results.Operation_Result;
      Snapshot : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Loaded   : Quality_Manager.Storage.Stored_Entity;
      Request  : constant Quality_Manager.Integrations.Runner.Execution_Request :=
        (Project_Path                => To_Unbounded_String ("/project"),
         Task_Id                     => To_Unbounded_String ("TASK-001"),
         Operation_Id                => To_Unbounded_String ("qm-execution-1"),
         Expected_Task_Revision      => To_Unbounded_String ("task-revision"),
         Expected_Project_Identity   => To_Unbounded_String ("project-identity"),
         Expected_Source_Fingerprint => To_Unbounded_String ("source-fingerprint"),
         Execution_Policy            => To_Unbounded_String ("policy-fingerprint"),
         Timeout_Seconds             => 60);
      Mapping  : constant Quality_Manager.Storage.Schema.Dispatch :=
        (Dispatch_Id         => To_Unbounded_String ("dispatch:runner"),
         Work_Id             => To_Unbounded_String ("work:runner"),
         Logical_Remediation => To_Unbounded_String ("remediation:runner"),
         Improve_Task        =>
           (Plan_Id  => To_Unbounded_String ("PLAN-001"),
            Revision => 1,
            Task_Id  => To_Unbounded_String ("IMP-001")),
         Native_Task_Id      => To_Unbounded_String ("TASK-001"),
         Authorization_Id    => To_Unbounded_String ("approval-1"),
         State               => Quality_Manager.Model.Published,
         Active              => True);

      procedure Cleanup is
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      end Cleanup;
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "native dispatch store opened");
      for State in Quality_Manager.Integrations.Runner.Execution_State loop
         declare
            Coordinator : constant Quality_Manager.Model.Work_State :=
              Quality_Manager.Dispatch.Coordinator_State (State);
            Expected : constant Quality_Manager.Model.Work_State :=
              (case State is
                  when Quality_Manager.Integrations.Runner.Not_Ready_State
                     | Quality_Manager.Integrations.Runner.Blocked_State => Quality_Manager.Model.Blocked,
                  when Quality_Manager.Integrations.Runner.Ready_State => Quality_Manager.Model.Queued,
                  when Quality_Manager.Integrations.Runner.Executing_State => Quality_Manager.Model.Executing,
                  when Quality_Manager.Integrations.Runner.Awaiting_Integration_State =>
                     Quality_Manager.Model.Awaiting_Integration,
                  when Quality_Manager.Integrations.Runner.Verifying_State
                     | Quality_Manager.Integrations.Runner.Completed_State =>
                     Quality_Manager.Model.Awaiting_Assessment,
                  when Quality_Manager.Integrations.Runner.Failed_State => Quality_Manager.Model.Failed,
                  when Quality_Manager.Integrations.Runner.Cancelled_State => Quality_Manager.Model.Cancelled);
         begin
            Assert
              (Coordinator = Expected,
               "every native state has an explicit coordinator state");
         end;
      end loop;
      declare
         Invalid_Mapping : Quality_Manager.Storage.Schema.Dispatch := Mapping;
      begin
         Invalid_Mapping.Active := False;
         Quality_Manager.Dispatch.Bind_Published_Task (Store, Invalid_Mapping, Result);
         Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
                 "inactive published mapping is rejected");
         Invalid_Mapping.Active := True;
         Invalid_Mapping.Native_Task_Id := Null_Unbounded_String;
         Quality_Manager.Dispatch.Bind_Published_Task (Store, Invalid_Mapping, Result);
         Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
                 "incomplete published mapping is rejected");
      end;
      Quality_Manager.Dispatch.Bind_Published_Task (Store, Mapping, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "published native mapping retained exactly");
      Quality_Manager.Integrations.Runner.Initialize (Runner, "./bin/qm_adapter_fixture");

      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 0, "", "", "", 0, 1, 100, Request, Snapshot, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Invalid_Request,
         "incomplete execution coordination identity is rejected");
      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store, Runner, 99, "dispatch:runner", "project:invalid", "coordinator:test",
         0, 1, 100, Request, Snapshot, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Invalid_Request,
         "mismatched external operation identity is rejected");
      Quality_Manager.Dispatch.Integrate_Or_Reconcile
        (Store, Runner, 0, "", "", 0, 1, 100, Request, Snapshot, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Invalid_Request,
         "incomplete integration coordination identity is rejected");

      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store                     => Store,
         Runner                    => Runner,
         Operation                 => 1,
         Dispatch_Id               => "dispatch:runner",
         Project_Resource          => "project:runner:execution",
         Lease_Owner               => "coordinator:test",
         Expected_Lease_Generation => 0,
         New_Lease_Generation      => 1,
         Lease_Expires_At          => 100,
         Request                   => Request,
         Snapshot                  => Snapshot,
         Result                    => Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Snapshot.State = Quality_Manager.Integrations.Runner.Awaiting_Integration_State,
         "native execution is journaled and independently awaits integration");
      Quality_Manager.Storage.Read (Store, "journal:1", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Committed),
         "confirmed native outcome commits the durable journal");
      Quality_Manager.Storage.Read (Store, "attempt:1", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Loaded.Kind = Quality_Manager.Storage.Attempt_Record,
         "native attempt outcome is persisted");

      Quality_Manager.Dispatch.Execute_Or_Reconcile
        (Store                     => Store,
         Runner                    => Runner,
         Operation                 => 1,
         Dispatch_Id               => "dispatch:runner",
         Project_Resource          => "project:runner:execution",
         Lease_Owner               => "coordinator:test",
         Expected_Lease_Generation => 0,
         New_Lease_Generation      => 1,
         Lease_Expires_At          => 100,
         Request                   => Request,
         Snapshot                  => Snapshot,
         Result                    => Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success,
         "repeated coordinator recovery adopts status without another execution");

      Quality_Manager.Dispatch.Integrate_Or_Reconcile
        (Store                     => Store,
         Runner                    => Runner,
         Journal_Operation         => 100,
         Project_Resource          => "project:runner:integration",
         Lease_Owner               => "coordinator:test",
         Expected_Lease_Generation => 0,
         New_Lease_Generation      => 1,
         Lease_Expires_At          => 100,
         Request                   => Request,
         Snapshot                  => Snapshot,
         Result                    => Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Snapshot.Workspace_State) = "integrated"
         and then Quality_Manager.Dispatch.Coordinator_State (Snapshot.State) =
           Quality_Manager.Model.Awaiting_Assessment,
         "native integration is separately leased, journaled, and awaiting independent assessment");
      Quality_Manager.Storage.Read (Store, "journal:100", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Committed),
         "confirmed native integration commits its own durable journal");

      declare
         Recovery_Request : Quality_Manager.Integrations.Runner.Execution_Request := Request;
      begin
         Recovery_Request.Operation_Id := To_Unbounded_String ("qm-execution-2");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store                     => Store,
            Runner                    => Runner,
            Operation                 => 2,
            Dispatch_Id               => "dispatch:runner",
            Project_Resource          => "project:runner:recovery",
            Lease_Owner               => "coordinator:test",
            Expected_Lease_Generation => 0,
            New_Lease_Generation      => 1,
            Lease_Expires_At          => 100,
            Request                   => Recovery_Request,
            Snapshot                  => Snapshot,
            Result                    => Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Not_Ready,
            "running native operation remains at the invoking recovery boundary");
         Quality_Manager.Storage.Close (Store, Result);
         Quality_Manager.Storage.Open (Store, Path, True, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "dispatch store reopened after interruption");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store                     => Store,
            Runner                    => Runner,
            Operation                 => 2,
            Dispatch_Id               => "dispatch:runner",
            Project_Resource          => "project:runner:recovery",
            Lease_Owner               => "coordinator:test",
            Expected_Lease_Generation => 0,
            New_Lease_Generation      => 1,
            Lease_Expires_At          => 100,
            Request                   => Recovery_Request,
            Snapshot                  => Snapshot,
            Result                    => Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success
            and then To_String (Snapshot.Audit_Reference) = "status-audit",
            "restart queries durable status instead of executing the agent again");
      end;
      declare
         Terminal_Request : Quality_Manager.Integrations.Runner.Execution_Request := Request;
      begin
         Terminal_Request.Operation_Id := To_Unbounded_String ("qm-execution-4");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store, Runner, 4, "dispatch:runner", "project:runner:cancelled",
            "coordinator:test", 0, 1, 100, Terminal_Request, Snapshot, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Interrupted,
            "cancelled native execution is recorded as interrupted");
         Terminal_Request.Operation_Id := To_Unbounded_String ("qm-execution-5");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store, Runner, 5, "dispatch:runner", "project:runner:failed",
            "coordinator:test", 0, 1, 100, Terminal_Request, Snapshot, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Negative_Result,
            "failed native execution remains a negative workflow outcome");
      end;
      declare
         Changed : Quality_Manager.Integrations.Runner.Execution_Request := Request;
      begin
         Changed.Execution_Policy := To_Unbounded_String ("another-policy");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store, Runner, 1, "dispatch:runner", "project:runner:execution",
            "coordinator:test", 0, 1, 100, Changed, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
                 "a durable operation cannot be rebound to changed execution intent");
      end;
      declare
         Interrupted_Request : Quality_Manager.Integrations.Runner.Execution_Request := Request;
      begin
         Interrupted_Request.Operation_Id := To_Unbounded_String ("qm-execution-6");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store, Runner, 6, "dispatch:runner", "project:runner:aborted",
            "coordinator:test", 0, 1, 100, Interrupted_Request, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
                 "an executing operation retains its invoking journal state");
         Quality_Manager.Storage.Advance_Operation
           (Store, 6, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Aborted,
            "qm-execution-6", "operator aborted execution", Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "test execution journal aborted");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store, Runner, 6, "dispatch:runner", "project:runner:aborted",
            "coordinator:test", 0, 1, 100, Interrupted_Request, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Negative_Result,
                 "aborted native operation remains terminal on replay");

         Interrupted_Request.Operation_Id := To_Unbounded_String ("qm-execution-7");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store, Runner, 7, "dispatch:runner", "project:runner:intervention",
            "coordinator:test", 0, 1, 100, Interrupted_Request, Snapshot, Result);
         Quality_Manager.Storage.Advance_Operation
           (Store, 7, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Needs_Intervention,
            "qm-execution-7", "operator review required", Result);
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store, Runner, 7, "dispatch:runner", "project:runner:intervention",
            "coordinator:test", 0, 1, 100, Interrupted_Request, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
                 "intervention journal cannot be replayed automatically");
      end;
      declare
         Wrong_Kind : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Project_Record,
            Entity_Key => To_Unbounded_String ("journal:8"),
            State => To_Unbounded_String ("PREPARED"), Payload => Null_Unbounded_String,
            Terminal => False, Generation => 1);
         Invalid_Request : Quality_Manager.Integrations.Runner.Execution_Request := Request;
      begin
         Quality_Manager.Storage.Put (Store, Wrong_Kind, Result);
         Invalid_Request.Operation_Id := To_Unbounded_String ("qm-execution-8");
         Quality_Manager.Dispatch.Execute_Or_Reconcile
           (Store, Runner, 8, "dispatch:runner", "project:runner:wrong-kind",
            "coordinator:test", 0, 1, 100, Invalid_Request, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
                 "journal key with the wrong record kind is rejected");
      end;
      declare
         Pending : Quality_Manager.Integrations.Runner.Execution_Request := Request;
      begin
         Pending.Operation_Id := To_Unbounded_String ("qm-execution-8");
         Quality_Manager.Dispatch.Integrate_Or_Reconcile
           (Store, Runner, 108, "project:runner:pending-integration", "coordinator:test",
            0, 1, 100, Pending, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
                 "native workspace pending integration remains recoverable");
         Quality_Manager.Dispatch.Integrate_Or_Reconcile
           (Store, Runner, 108, "project:runner:pending-integration", "coordinator:test",
            0, 1, 100, Pending, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
                 "integration recovery queries and re-enters only the native operation");
      end;
      declare
         Changed : Quality_Manager.Integrations.Runner.Execution_Request := Request;
      begin
         Changed.Operation_Id := To_Unbounded_String ("qm-execution-9");
         Changed.Execution_Policy := To_Unbounded_String ("changed-policy");
         Quality_Manager.Dispatch.Integrate_Or_Reconcile
           (Store, Runner, 109, "project:runner:policy-change", "coordinator:test",
            0, 1, 100, Changed, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
                 "integration policy drift requires intervention");
         Quality_Manager.Dispatch.Integrate_Or_Reconcile
           (Store, Runner, 109, "project:runner:policy-change", "coordinator:test",
            0, 1, 100, Changed, Snapshot, Result);
         Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
                 "intervention remains durable across integration replay");
      end;
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Native_Dispatch;

   procedure Test_Verification_Engine (Item : in out Fixture) is
      pragma Unreferenced (Item);

      function Assessment_JSON
        (Source : String;
         Complete : Boolean := True;
         Variant : Natural := 0) return String is
         Text : Unbounded_String := To_Unbounded_String
           ("{""schema_version"":1,""assessment_id"":2,""project_id"":7," &
            """project_path"":""/project"",""source_fingerprint"":""" & Source & """," &
            """policy_fingerprint"":""policy"",""toolchain_fingerprint"":""toolchain""," &
            """status"":""ASSESSMENT_COMPLETED"",""results"":[");
      begin
         for Index in 1 .. 33 loop
            if Index > 1 then
               Append (Text, ",");
            end if;
            declare
               Number : constant String := Ada.Strings.Fixed.Trim
                 (Natural'Image (Index), Ada.Strings.Both);
               Indicator : constant String :=
                 (if Variant = 2 and then Index = 1 then "bad"
                  elsif Variant = 4 and then Index = 1 then "PRF-01"
                  else "TST-" & (if Index < 10 then "0" else "") & Number);
               Compliance : constant String :=
                 (if Variant = 1 and then Index = 1 then "violation"
                  elsif Variant = 5 and then Index = 1 then "pass"
                  elsif Variant = 6 and then Index = 1 then "pass"
                  elsif not Complete and then Index = 1 then "unknown"
                  else "pass");
            begin
               Append
                 (Text,
                  "{""indicator"":""" & Indicator & """,""execution"":""" &
                  (if Variant = 5 and then Index = 1 then "failed" else "succeeded") &
                  """,""compliance"":""" & Compliance &
                  """,""applicable"":" &
                  (if Variant = 6 and then Index = 1 then "false" else "true") &
                  ",""summary"":""ok""," &
                  """evidence"":""fixture"",""measurement"":" &
                  (if Index = 3 and then Variant /= 3 then "{""basis_points"":9000}" else "{}") &
                  ",""findings"":[]}");
            end;
         end loop;
         Append (Text, "],""executions"":[]}");
         return To_String (Text);
      end Assessment_JSON;

      function Response (Text : String) return Quality_Manager.Integrations.JSON_CLI.Response is
        ((Status => Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success),
          Exit_Status => 0,
          Document => To_Unbounded_String (Text),
          Diagnostics => Null_Unbounded_String));

      Assessment : Quality_Manager.Verification.Assessment_Evidence;
      Regression : Quality_Manager.Verification.Regression_Evidence;
      Improve    : Quality_Manager.Verification.Improve_Evidence;
      Native     : Quality_Manager.Integrations.Runner.Task_Snapshot := (others => <>);
      Context    : Quality_Manager.Verification.Verification_Context :=
        (Project_Id            => 7,
         Project_Path          => To_Unbounded_String ("/project"),
         Candidate_Source      => To_Unbounded_String ("candidate-source"),
         Policy_Fingerprint    => To_Unbounded_String ("policy"),
         Toolchain_Fingerprint => To_Unbounded_String ("toolchain"),
         Baseline_Assessment   => 1,
         Current_Assessment    => 2,
         Improve_Plan_Id       => To_Unbounded_String ("PLAN-001"),
         Improve_Task_Id       => To_Unbounded_String ("IMP-001"));
      Decision : Quality_Manager.Verification.Verification_Decision;
      Result   : Quality_Manager.Results.Operation_Result;
   begin
      Quality_Manager.Verification.Decode_Assessment
        (Response (Assessment_JSON ("candidate-source")), Assessment, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Assessment.Complete,
         "complete 33-indicator assessment evidence is decoded");
      Quality_Manager.Verification.Decode_Regression
        (Response
           ("{""schema_version"":1,""kind"":""assessment-comparison"",""project_id"":7," &
            """status"":""comparison-available"",""baseline_id"":1,""current_id"":2," &
            """policy_changed"":false,""changes"":[]}"),
         Regression, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Regression.Regression_Count = 0,
         "explicit selected-baseline comparison is decoded");
      Quality_Manager.Verification.Decode_Improve
        (Response
           ("{""schema_version"":2,""command"":""verify"",""data"":{" &
            """plan_id"":""PLAN-001"",""baseline_run"":1,""verification_run"":2," &
            """outcome"":""verified"",""plan_outcome"":""verified""," &
            """project_outcome"":""verified"",""comparable"":true,""new_critical"":0," &
            """explanation"":""resolved"",""tasks"":[{""task_id"":""IMP-001""," &
            """outcome"":""verified"",""matched"":1,""total"":1," &
            """explanation"":""resolved""}]}}"),
         "IMP-001", Improve, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Improve.Task_Found,
         "exact Improve task verification is decoded");

      Native.State := Quality_Manager.Integrations.Runner.Completed_State;
      Native.Workspace_State := To_Unbounded_String ("integrated");
      Quality_Manager.Verification.Decide
        (Native, Assessment, Regression, Improve, Context, Decision);
      Assert
        (Decision.Verified and then Decision.Outcome = Quality_Manager.Model.Satisfied,
         "N and Q and R and F is the only verified outcome");

      Context.Candidate_Source := To_Unbounded_String ("different-source");
      Quality_Manager.Verification.Decide
        (Native, Assessment, Regression, Improve, Context, Decision);
      Assert
        (not Decision.Verified and then Decision.Outcome = Quality_Manager.Model.Evidence_Unavailable,
         "source mismatch invalidates otherwise successful evidence");
      Context.Candidate_Source := To_Unbounded_String ("candidate-source");
      Quality_Manager.Verification.Decode_Assessment
        (Response (Assessment_JSON ("candidate-source", False)), Assessment, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then not Assessment.Complete,
         "an assessment missing one indicator remains incomplete evidence");
      declare
         Incomplete_Response : constant Quality_Manager.Integrations.JSON_CLI.Response :=
           (Status => Quality_Manager.Results.Make_Result
              (Quality_Manager.Results.Stale_Evidence,
               "assessment completed with incomplete evidence",
               "fixture.incomplete"),
            Exit_Status => 3,
            Document => To_Unbounded_String
              (Assessment_JSON ("candidate-source", False)),
            Diagnostics => Null_Unbounded_String);
      begin
         Quality_Manager.Verification.Decode_Assessment
           (Incomplete_Response, Assessment, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success
            and then Assessment.Assessment_Id = 2
            and then Assessment.Completed
            and then not Assessment.Complete,
            "exit code 3 adopts the durable incomplete assessment");
      end;
      Quality_Manager.Verification.Decide
        (Native, Assessment, Regression, Improve, Context, Decision);
      Assert
        (Decision.Outcome = Quality_Manager.Model.Evidence_Unavailable,
         "incomplete assessment never satisfies verification");
      Quality_Manager.Verification.Decode_Assessment
        (Response (Assessment_JSON ("candidate-source")), Assessment, Result);
      Regression.Regression_Count := 1;
      Quality_Manager.Verification.Decide
        (Native, Assessment, Regression, Improve, Context, Decision);
      Assert
        (Decision.Outcome = Quality_Manager.Model.Regression,
         "a new regression rejects the candidate");
      Regression.Regression_Count := 0;
      Regression.Compatibility_Failure := True;
      Quality_Manager.Verification.Decide
        (Native, Assessment, Regression, Improve, Context, Decision);
      Assert
        (Decision.Outcome = Quality_Manager.Model.Policy_Incompatible,
         "incompatible baseline evidence is not reported as no regression");
      Assert
        (Quality_Manager.Verification.Retry_For (Decision.Outcome, 1, 2) =
           Quality_Manager.Verification.Establish_Compatible_Baseline,
         "policy or toolchain changes require a new compatible baseline");
      Regression.Compatibility_Failure := False;
      Improve.Task_Outcome := To_Unbounded_String ("still-failing");
      Quality_Manager.Verification.Decide
        (Native, Assessment, Regression, Improve, Context, Decision);
      Assert
        (Decision.Outcome = Quality_Manager.Model.Unresolved,
         "native completion without quality resolution is not verified");

      Assert
        (Quality_Manager.Verification.Retry_For (Quality_Manager.Model.Regression, 1, 2) =
           Quality_Manager.Verification.Reject_Candidate,
         "regressions reject rather than retry the same candidate");
      Assert
        (Quality_Manager.Verification.Retry_For (Quality_Manager.Model.Unresolved, 2, 2) =
           Quality_Manager.Verification.Block_Work,
         "attempt budget cannot be reset by replanning");

      Native.State := Quality_Manager.Integrations.Runner.Failed_State;
      Quality_Manager.Verification.Decide
        (Native, Assessment, Regression, Improve, Context, Decision);
      Assert (Decision.Outcome = Quality_Manager.Model.Execution_Failed,
              "native failure remains independent from quality evidence");

      for Outcome in Quality_Manager.Model.Outcome_Kind loop
         declare
            Action : constant Quality_Manager.Verification.Retry_Action :=
              Quality_Manager.Verification.Retry_For (Outcome, 0, 2);
            Expected : constant Quality_Manager.Verification.Retry_Action :=
              (case Outcome is
                  when Quality_Manager.Model.No_Outcome =>
                     Quality_Manager.Verification.Retry_Idempotent_Operation,
                  when Quality_Manager.Model.Unresolved =>
                     Quality_Manager.Verification.Replan_Remediation,
                  when Quality_Manager.Model.Regression =>
                     Quality_Manager.Verification.Reject_Candidate,
                  when Quality_Manager.Model.Evidence_Unavailable =>
                     Quality_Manager.Verification.Repair_Evidence,
                  when Quality_Manager.Model.Policy_Incompatible =>
                     Quality_Manager.Verification.Establish_Compatible_Baseline,
                  when Quality_Manager.Model.Execution_Failed =>
                     Quality_Manager.Verification.Start_New_Execution_Attempt,
                  when Quality_Manager.Model.Authorization_Required =>
                     Quality_Manager.Verification.Escalate,
                  when Quality_Manager.Model.Satisfied =>
                     Quality_Manager.Verification.No_Retry);
         begin
            Assert (Action = Expected, "every verification outcome has a cause-specific retry");
         end;
      end loop;

      Quality_Manager.Verification.Decode_Assessment
        (Response (Assessment_JSON ("candidate-source", Variant => 1)), Assessment, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Assessment.Violations = 1,
              "assessment violations remain evidence rather than process failures");
      for Variant in 2 .. 3 loop
         Quality_Manager.Verification.Decode_Assessment
           (Response (Assessment_JSON ("candidate-source", Variant => Variant)), Assessment, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success and then not Assessment.Complete,
                 "malformed indicator evidence remains explicitly incomplete");
      end loop;
      Quality_Manager.Verification.Decode_Assessment
        (Response (Assessment_JSON ("candidate-source", Variant => 4)), Assessment, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Assessment.Proof_Applicable and then Assessment.Proof_Passed,
         "proof applicability and outcome are retained from the exact indicator");
      for Variant in 5 .. 6 loop
         Quality_Manager.Verification.Decode_Assessment
           (Response (Assessment_JSON ("candidate-source", Variant => Variant)), Assessment, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success and then not Assessment.Complete,
                 "execution and applicability inconsistencies invalidate completeness");
      end loop;

      declare
         Upstream_Failure : constant Quality_Manager.Integrations.JSON_CLI.Response :=
           (Status => Quality_Manager.Results.Make_Result
              (Quality_Manager.Results.Execution_Error, "upstream failed", "fixture.failed"),
            Exit_Status => 4, Document => Null_Unbounded_String,
            Diagnostics => Null_Unbounded_String);
      begin
         Quality_Manager.Verification.Decode_Assessment
           (Upstream_Failure, Assessment, Result);
         Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
                 "assessment decoder preserves upstream execution failures");
         Quality_Manager.Verification.Decode_Regression
           (Upstream_Failure, Regression, Result);
         Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
                 "regression decoder preserves upstream execution failures");
         Quality_Manager.Verification.Decode_Improve
           (Upstream_Failure, "IMP-001", Improve, Result);
         Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
                 "Improve decoder preserves upstream execution failures");
      end;

      Quality_Manager.Verification.Decode_Assessment
        (Response ("{""schema_version"":1}"), Assessment, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "structurally incomplete assessment evidence fails closed");
      Quality_Manager.Verification.Decode_Regression
        (Response ("{""schema_version"":1}"), Regression, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "structurally incomplete regression evidence fails closed");
      Quality_Manager.Verification.Decode_Regression
        (Response
           ("{""schema_version"":1,""kind"":""assessment-comparison"",""project_id"":7," &
            """status"":""comparison-available"",""baseline_id"":1,""current_id"":2," &
            """policy_changed"":false,""changes"":[{""indicator"":""TST-03""," &
            """change"":""unknown-change"",""before"":""pass"",""after"":""violation""}]}"),
         Regression, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "unknown regression change kind is rejected");
      Quality_Manager.Verification.Decode_Improve
        (Response ("{""schema_version"":2,""command"":""verify"",""data"":{}}"),
         "IMP-001", Improve, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "structurally incomplete Improve evidence fails closed");
      Quality_Manager.Verification.Decode_Improve
        (Response
           ("{""schema_version"":2,""command"":""verify"",""data"":{" &
            """plan_id"":""PLAN-001"",""baseline_run"":1,""verification_run"":2," &
            """outcome"":""verified"",""plan_outcome"":""verified""," &
            """project_outcome"":""verified"",""comparable"":true,""new_critical"":0," &
            """explanation"":""resolved"",""tasks"":[{}]}}"),
         "IMP-001", Improve, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "malformed Improve task evidence is rejected");
      Quality_Manager.Verification.Decode_Improve
        (Response
           ("{""schema_version"":2,""command"":""verify"",""data"":{" &
            """plan_id"":""PLAN-001"",""baseline_run"":1,""verification_run"":2," &
            """outcome"":""verified"",""plan_outcome"":""verified""," &
            """project_outcome"":""verified"",""comparable"":true,""new_critical"":0," &
            """explanation"":""resolved"",""tasks"":[" &
            "{""task_id"":""IMP-001"",""outcome"":""verified"",""matched"":1," &
            """total"":1,""explanation"":""resolved""}," &
            "{""task_id"":""IMP-001"",""outcome"":""verified"",""matched"":1," &
            """total"":1,""explanation"":""duplicate""}]}}"),
         "IMP-001", Improve, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "duplicate Improve task evidence is rejected");

      Quality_Manager.Verification.Decode_Assessment
        (Response ("{"), Assessment, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "malformed assessment evidence fails closed");
      Quality_Manager.Verification.Decode_Regression
        (Response ("{"), Regression, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "malformed regression evidence fails closed");
      Quality_Manager.Verification.Decode_Improve
        (Response ("{"), "IMP-001", Improve, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "malformed Improve evidence fails closed");
   end Test_Verification_Engine;

   procedure Test_Verification_Workflow (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path      : constant String := "/tmp/quality-manager-verification.database";
      Store     : Quality_Manager.Storage.Store;
      Quality   : Quality_Manager.Integrations.Quality.Adapter;
      Planner   : Quality_Manager.Integrations.Improve.Adapter;
      Native    : Quality_Manager.Integrations.Runner.Task_Snapshot := (others => <>);
      Decision  : Quality_Manager.Verification.Verification_Decision;
      Result    : Quality_Manager.Results.Operation_Result;
      Loaded    : Quality_Manager.Storage.Stored_Entity;
      Project   : constant Quality_Manager.Identities.Project_Key :=
        (Quality_Database_Id => To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
         Quality_Project_Id  => 7,
         Canonical_Path      => To_Unbounded_String ("/project"));
      Work      : constant Quality_Manager.Storage.Schema.Work_Item :=
        (Work_Id            => To_Unbounded_String ("work:verification"),
         Global_Remediation => To_Unbounded_String ("remediation:verification"),
         Project            => Project,
         Origin             => Quality_Manager.Model.Maintenance,
         Finding_Identities => To_Unbounded_String ("AQ-01"),
         Priority           => 1,
         Improve_Plan_Id    => To_Unbounded_String ("PLAN-001"),
         Improve_Revision   => 1,
         Improve_Task_Id    => To_Unbounded_String ("IMP-001"),
         State              => Quality_Manager.Model.Awaiting_Assessment,
         Outcome            => Quality_Manager.Model.No_Outcome);
      Request   : constant Quality_Manager.Verification.Remediation_Request :=
        (Work_Id               => To_Unbounded_String ("work:verification"),
         Project               => Project,
         Project_Selector      => To_Unbounded_String ("7"),
         Profile               => To_Unbounded_String ("ci"),
         Candidate_Revision    => To_Unbounded_String ("candidate-commit"),
         Candidate_Source      => To_Unbounded_String ("candidate-source"),
         Policy_Fingerprint    => To_Unbounded_String ("policy"),
         Toolchain_Fingerprint => To_Unbounded_String ("toolchain"),
         Baseline_Assessment   => 1,
         Improve_Plan_Id       => To_Unbounded_String ("PLAN-001"),
         Improve_Plan_Revision => 1,
         Improve_Task_Id       => To_Unbounded_String ("IMP-001"),
         Contract_Digest       => To_Unbounded_String ("contract-digest"),
         Assessment_Operation  => 200,
         Improve_Operation     => 201,
         Attempts_Used         => 1,
         Maximum_Attempts      => 2);

      procedure Cleanup is
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      end Cleanup;
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "verification store opened");
      Quality_Manager.Storage.Records.Save (Store, Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "awaiting-assessment work persisted");
      Quality_Manager.Integrations.Quality.Initialize
        (Quality, "./bin/qm_adapter_fixture", "quality.db");
      Quality_Manager.Integrations.Improve.Initialize
        (Planner, "./bin/qm_adapter_fixture", "improve.toml", "quality.db", "improve.db");
      Native.State := Quality_Manager.Integrations.Runner.Completed_State;
      Native.Workspace_State := To_Unbounded_String ("integrated");

      Quality_Manager.Verification.Verify_Remediation
        (Store, Quality, Planner, Native, Request, Decision, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Decision.Verified,
         "fresh assessment, explicit comparison, and Improve verification complete autonomously");
      Quality_Manager.Storage.Read (Store, "work:verification", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Verified),
         "only the complete independent predicate marks work verified");
      Quality_Manager.Storage.Read (Store, "journal:200", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Committed),
         "authoritative assessment side effect is journaled");
      Quality_Manager.Storage.Read (Store, "journal:201", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Committed),
         "Improve verification side effect is journaled");
      Quality_Manager.Verification.Verify_Remediation
        (Store, Quality, Planner, Native, Request, Decision, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Decision.Verified,
         "repeated workflow recovery adopts the exact historical verification");

      declare
         Unresolved_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
         Unresolved      : Quality_Manager.Verification.Remediation_Request := Request;
      begin
         Unresolved_Work.Work_Id := To_Unbounded_String ("work:still-failing");
         Unresolved_Work.Global_Remediation := To_Unbounded_String ("remediation:still-failing");
         Unresolved_Work.Improve_Task_Id := To_Unbounded_String ("IMP-FAIL");
         Quality_Manager.Storage.Records.Save (Store, Unresolved_Work, Result);
         Unresolved.Work_Id := Unresolved_Work.Work_Id;
         Unresolved.Improve_Task_Id := To_Unbounded_String ("IMP-FAIL");
         Unresolved.Assessment_Operation := 204;
         Unresolved.Improve_Operation := 205;
         Quality_Manager.Verification.Verify_Remediation
           (Store, Quality, Planner, Native, Unresolved, Decision, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Negative_Result
            and then Decision.Outcome = Quality_Manager.Model.Unresolved,
            "native completion without resolving the finding remains unverified");
         Quality_Manager.Storage.Read (Store, "work:still-failing", Loaded, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success
            and then To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
              (Quality_Manager.Model.Planning),
            "an unresolved finding is sent to bounded replanning");
      end;

      declare
         Regression_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
         Regressed       : Quality_Manager.Verification.Remediation_Request := Request;
      begin
         Regression_Work.Work_Id := To_Unbounded_String ("work:regression");
         Regression_Work.Global_Remediation := To_Unbounded_String ("remediation:regression");
         Quality_Manager.Storage.Records.Save (Store, Regression_Work, Result);
         Regressed.Work_Id := Regression_Work.Work_Id;
         Regressed.Baseline_Assessment := 3;
         Regressed.Assessment_Operation := 206;
         Regressed.Improve_Operation := 207;
         Quality_Manager.Verification.Verify_Remediation
           (Store, Quality, Planner, Native, Regressed, Decision, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Negative_Result
            and then Decision.Outcome = Quality_Manager.Model.Regression,
            "resolved work with a new regression is not verified");
         Quality_Manager.Storage.Read (Store, "work:regression", Loaded, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success
            and then To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
              (Quality_Manager.Model.Blocked),
            "a regressed candidate is rejected and durably blocked");
      end;

      declare
         Interrupted_Work : Quality_Manager.Storage.Schema.Work_Item := Work;
         Interrupted      : Quality_Manager.Verification.Remediation_Request := Request;
      begin
         Interrupted_Work.Work_Id := To_Unbounded_String ("work:interrupted-assessment");
         Interrupted_Work.Global_Remediation := To_Unbounded_String ("remediation:interrupted-assessment");
         Quality_Manager.Storage.Records.Save (Store, Interrupted_Work, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "interrupted assessment work persisted");
         Interrupted.Work_Id := Interrupted_Work.Work_Id;
         Interrupted.Project_Selector := To_Unbounded_String ("99");
         Interrupted.Assessment_Operation := 202;
         Interrupted.Improve_Operation := 203;
         Quality_Manager.Verification.Verify_Remediation
           (Store, Quality, Planner, Native, Interrupted, Decision, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Invalid_Request,
            "invalid assessment output cannot become evidence");
         Quality_Manager.Verification.Verify_Remediation
           (Store, Quality, Planner, Native, Interrupted, Decision, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Authorization_Required,
            "ambiguous interrupted assessment is not blindly repeated");
         Quality_Manager.Storage.Read (Store, "journal:202", Loaded, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success
            and then To_String (Loaded.State) = Quality_Manager.Journal.Journal_State'Image
              (Quality_Manager.Journal.Needs_Intervention),
            "ambiguous assessment recovery is durably escalated");
      end;
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Verification_Workflow;

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
         Improve_Plan_Id => To_Unbounded_String ("plan-1"), Improve_Revision => 1,
         Improve_Task_Id => To_Unbounded_String ("task-1"), State => Quality_Manager.Model.Queued,
         Outcome => Quality_Manager.Model.No_Outcome);
      Work_2 : constant Quality_Manager.Storage.Schema.Work_Item :=
        (Work_Id => To_Unbounded_String ("work:scheduler:two"),
         Global_Remediation => To_Unbounded_String ("remediation:two"),
         Project => Project_2, Origin => Quality_Manager.Model.Campaign,
         Finding_Identities => To_Unbounded_String ("TST-03"), Priority => 150,
         Improve_Plan_Id => To_Unbounded_String ("plan-2"), Improve_Revision => 1,
         Improve_Task_Id => To_Unbounded_String ("task-2"), State => Quality_Manager.Model.Queued,
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
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Durable_Scheduler;

   procedure Test_Maintenance_Cycle (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path      : constant String := "/tmp/quality-manager-maintenance.database";
      Store     : aliased Quality_Manager.Storage.Store;
      Scheduler : aliased Quality_Manager.Scheduler.Scheduler_Type;
      Quality   : Quality_Manager.Integrations.Quality.Adapter;
      Planner   : Quality_Manager.Integrations.Improve.Adapter;
      Context   : Quality_Manager.Maintenance.Context;
      Result    : Quality_Manager.Results.Operation_Result;
      Values    : Quality_Manager.Storage.Entity_Vectors.Vector;

      procedure Cleanup is
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      end Cleanup;
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "maintenance store opened");
      Quality_Manager.Maintenance.Run_Cycle (Context, "", False, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "uninitialized maintenance context fails closed");
      Quality_Manager.Scheduler.Initialize (Scheduler);
      Quality_Manager.Scheduler.Configure (Scheduler, Store'Unchecked_Access, 4, 1);
      Quality_Manager.Integrations.Quality.Initialize
        (Quality, "./bin/qm_adapter_fixture", "quality.db");
      Quality_Manager.Integrations.Improve.Initialize
        (Planner, "./bin/qm_adapter_fixture", "improve.toml", "quality.db", "improve.db");
      Quality_Manager.Maintenance.Initialize
        (Context, Store'Unchecked_Access, Scheduler'Unchecked_Access, Quality, Planner);
      Quality_Manager.Maintenance.Run_Cycle (Context, "", False, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Quality_Manager.Scheduler.Pending_Count (Scheduler) = 0
         and then Quality_Manager.Scheduler.Active_Count
           (Scheduler, Quality_Manager.Scheduler.Assessment_Resource) = 0,
         "maintenance consumes due assessment work without blocking on disabled projects: "
         & Quality_Manager.Results.Message (Result)
         & " pending=" & Natural'Image (Quality_Manager.Scheduler.Pending_Count (Scheduler)));
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Project_Record, Values, 10, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Natural (Values.Length) = 3,
              "qualified project inventory is synchronized across multiple projects");
      declare
         Observed_Count : Natural := 0;
      begin
         for Value of Values loop
            if Ada.Strings.Fixed.Index (To_String (Value.Payload), """last_assessment_run"":2") > 0 then
               Observed_Count := Observed_Count + 1;
            end if;
         end loop;
         Assert
           (Observed_Count = 2,
            "complete and incomplete assessments remain the latest durable project observations");
      end;
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Cycle_Record, Values, 10, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Natural (Values.Length) = 3,
              "each selected project has independent durable cycle state");
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Work_Item_Record, Values, 10, Result);
      declare
         Verified_Count : Natural := 0;
         Inconclusive_Count : Natural := 0;
         Approval_Count : Natural := 0;
         Assessment_Work : Unbounded_String;
      begin
         for Value of Values loop
            if To_String (Value.State) = Quality_Manager.Model.Work_State'Image
              (Quality_Manager.Model.Verified)
            then
               Verified_Count := Verified_Count + 1;
               Assessment_Work := Value.Entity_Key;
            elsif To_String (Value.State) = Quality_Manager.Model.Work_State'Image
              (Quality_Manager.Model.Inconclusive)
            then
               Inconclusive_Count := Inconclusive_Count + 1;
            elsif To_String (Value.State) = Quality_Manager.Model.Work_State'Image
              (Quality_Manager.Model.Awaiting_Approval)
            then
               Approval_Count := Approval_Count + 1;
               Assert
                 (Ada.Strings.Fixed.Index (To_String (Value.Payload), """plan_id"":""PLAN-001""") > 0
                  and then Ada.Strings.Fixed.Index
                    (To_String (Value.Payload), """task_id"":""IMP-001""") > 0
                  and then Ada.Strings.Fixed.Index
                    (To_String (Value.Payload), "finding-a\nfinding-b") > 0,
                  "remediation work retains the exact plan task and canonical finding set");
            end if;
         end loop;
         Assert
           (Result.Kind = Quality_Manager.Results.Success
            and then Natural (Values.Length) = 3
            and then Verified_Count = 1
            and then Inconclusive_Count = 1
            and then Approval_Count = 1,
            "violations create approval-gated remediation while incomplete evidence remains inconclusive");
         Quality_Manager.Planning.Generate_Or_Reconcile
           (Store, Planner,
            (Quality_Database_Id => To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
             Quality_Project_Id => 7,
             Canonical_Path => To_Unbounded_String ("/project")),
            2, "candidate-source", Quality_Manager.Model.Maintenance,
            To_String (Assessment_Work), Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success,
            "committed planning recovery adopts the exact stored plan without duplicate work");
      end;
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Journal_Record, Values, 10, Result);
      declare
         Committed_Count : Natural := 0;
      begin
         for Value of Values loop
            if To_String (Value.State) = Quality_Manager.Journal.Journal_State'Image
              (Quality_Manager.Journal.Committed)
            then
               Committed_Count := Committed_Count + 1;
            end if;
         end loop;
         Assert
           (Result.Kind = Quality_Manager.Results.Success
            and then Natural (Values.Length) = 3
            and then Committed_Count = 3,
            "assessments and exact-run Improve planning retain committed durable identities");
      end;
      Quality_Manager.Maintenance.Run_Cycle (Context, "missing", True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "maintenance selector with no project is explicit");
      Quality_Manager.Maintenance.Run_Cycle (Context, "8", True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "disabled project can be observed in dry-run without dispatch");
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Maintenance_Cycle;

   procedure Test_Campaign_Workflow (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path    : constant String := "/tmp/quality-manager-campaign.database";
      Store   : aliased Quality_Manager.Storage.Store;
      Context : Quality_Manager.Campaigns.Context;
      Result  : Quality_Manager.Results.Operation_Result;
      Values  : Quality_Manager.Storage.Entity_Vectors.Vector;
      Loaded  : Quality_Manager.Storage.Stored_Entity;
      Shared  : Unbounded_String;
      Progress_Text : Unbounded_String;
      Found   : Boolean;
      Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
      Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        (Work_Id => To_Unbounded_String ("work:shared-campaign"),
         Global_Remediation => To_Unbounded_String ("global:coverage"), Project => Project,
         Origin => Quality_Manager.Model.Maintenance,
         Finding_Identities => To_Unbounded_String ("TST-03"), Priority => 150,
         Improve_Plan_Id => Null_Unbounded_String, Improve_Revision => 0,
         Improve_Task_Id => Null_Unbounded_String, State => Quality_Manager.Model.Planning,
         Outcome => Quality_Manager.Model.No_Outcome);

      function Definition
        (Id : String; Revision, Budget : Positive; Target_Value : String := "pass") return String is
        ("{""schema_version"":1,""campaign_id"":""" & Id
         & """,""definition_revision"":"
         & Ada.Strings.Fixed.Trim (Positive'Image (Revision), Ada.Strings.Both)
         & ",""projects"":["
         & "{""quality_database_id"":""database-a"",""project_id"":7,""path"":""/project"","
         & """baseline_assessment"":1},"
         & "{""quality_database_id"":""database-a"",""project_id"":8,""path"":""/second"","
         & """baseline_assessment"":1}],"
         & """indicators"":[""TST-03""],""target"":""" & Target_Value & """,""work_budget"":"
         & Ada.Strings.Fixed.Trim (Positive'Image (Budget), Ada.Strings.Both)
         & ",""priority_rule"":""campaign"",""autonomy_policy_digest"":""policy-1""}");

      procedure Cleanup is
      begin
         Remove_Test_File;
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      end Cleanup;

      procedure Check_Invalid_Definition
        (Text : String;
         Expected : Quality_Manager.Results.Result_Kind;
         Diagnostic : String) is
      begin
         Write_Text (Text);
         Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
         Assert (Result.Kind = Expected, Diagnostic);
      end Check_Invalid_Definition;
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign store opened");
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "uninitialized campaign context fails closed");
      Quality_Manager.Campaigns.Start (Context, "missing", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "uninitialized campaign state lookup fails closed");
      Quality_Manager.Campaigns.Initialize (Context, Store'Unchecked_Access);
      declare
         Wrong_Kind : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Project_Record,
            Entity_Key => To_Unbounded_String ("campaign:wrong-kind"),
            State => To_Unbounded_String ("DISCOVERED"), Payload => To_Unbounded_String ("{}"),
            Terminal => False, Generation => 1);
         Bad_Revision : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Campaign_Record,
            Entity_Key => To_Unbounded_String ("campaign:bad-revision"),
            State => To_Unbounded_String ("DISCOVERED"),
            Payload => To_Unbounded_String ("{""revision"":0}"),
            Terminal => False, Generation => 1);
         Bad_State : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Campaign_Record,
            Entity_Key => To_Unbounded_String ("campaign:bad-state"),
            State => To_Unbounded_String ("UNKNOWN_STATE"),
            Payload => To_Unbounded_String ("{""revision"":1}"),
            Terminal => False, Generation => 1);
      begin
         Quality_Manager.Storage.Put (Store, Wrong_Kind, Result);
         Quality_Manager.Campaigns.Start (Context, "wrong-kind", Result);
         Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
                 "campaign identity cannot alias another record kind");
         Quality_Manager.Storage.Put (Store, Bad_Revision, Result);
         Quality_Manager.Campaigns.Start (Context, "bad-revision", Result);
         Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
                 "invalid durable campaign revision is rejected");
         Quality_Manager.Storage.Put (Store, Bad_State, Result);
         Quality_Manager.Campaigns.Start (Context, "bad-state", Result);
         Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
                 "unknown durable campaign state is a compatibility error");
      end;
      Quality_Manager.Campaigns.Create (Context, "/tmp/no-such-campaign.json", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "missing campaign definition is rejected");
      Write_Text ("");
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "empty campaign definition is rejected");
      Write_Text ("{");
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "malformed campaign definition is rejected");
      Quality_Manager.Storage.Records.Save
        (Store,
         Quality_Manager.Storage.Schema.Project'
           (Key => Project, Enabled => True, Last_Assessment_Run => 1,
            Last_Source_Fingerprint => To_Unbounded_String ("source-1")), Result);
      Quality_Manager.Storage.Records.Save
        (Store,
         Quality_Manager.Storage.Schema.Project'
           (Key => (To_Unbounded_String ("database-a"), 8, To_Unbounded_String ("/second")),
            Enabled => True, Last_Assessment_Run => 1,
            Last_Source_Fingerprint => To_Unbounded_String ("source-1")), Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign population inventory persisted");
      Check_Invalid_Definition
        ("{""schema_version"":1}", Quality_Manager.Results.Incompatible_Contract,
         "incomplete campaign contract is rejected");
      Check_Invalid_Definition
        ("{""schema_version"":1,""campaign_id"":""bad-project"",""definition_revision"":1," &
         """projects"":[{}],""indicators"":[""TST-03""],""target"":""pass""," &
         """work_budget"":1,""priority_rule"":""campaign""," &
         """autonomy_policy_digest"":""policy""}",
         Quality_Manager.Results.Incompatible_Contract, "invalid campaign project is rejected");
      Check_Invalid_Definition
        ("{""schema_version"":1,""campaign_id"":""unknown-project"",""definition_revision"":1," &
         """projects"":[{""quality_database_id"":""database-a"",""project_id"":9," &
         """path"":""/unknown"",""baseline_assessment"":1}]," &
         """indicators"":[""TST-03""],""target"":""pass"",""work_budget"":1," &
         """priority_rule"":""campaign"",""autonomy_policy_digest"":""policy""}",
         Quality_Manager.Results.Not_Found, "unsynchronized campaign project is rejected");
      Check_Invalid_Definition
        ("{""schema_version"":1,""campaign_id"":""duplicate-project"",""definition_revision"":1," &
         """projects"":[{""quality_database_id"":""database-a"",""project_id"":7," &
         """path"":""/project"",""baseline_assessment"":1},{" &
         """quality_database_id"":""database-a"",""project_id"":7," &
         """path"":""/project"",""baseline_assessment"":1}]," &
         """indicators"":[""TST-03""],""target"":""pass"",""work_budget"":1," &
         """priority_rule"":""campaign"",""autonomy_policy_digest"":""policy""}",
         Quality_Manager.Results.Invalid_Request, "duplicate campaign project is rejected");
      Check_Invalid_Definition
        ("{""schema_version"":1,""campaign_id"":""bad-indicator"",""definition_revision"":1," &
         """projects"":[{""quality_database_id"":""database-a"",""project_id"":7," &
         """path"":""/project"",""baseline_assessment"":1}]," &
         """indicators"":[1],""target"":""pass"",""work_budget"":1," &
         """priority_rule"":""campaign"",""autonomy_policy_digest"":""policy""}",
         Quality_Manager.Results.Incompatible_Contract, "non-string campaign indicator is rejected");
      Check_Invalid_Definition
        ("{""schema_version"":1,""campaign_id"":""duplicate-indicator"",""definition_revision"":1," &
         """projects"":[{""quality_database_id"":""database-a"",""project_id"":7," &
         """path"":""/project"",""baseline_assessment"":1}]," &
         """indicators"":[""TST-03"",""TST-03""],""target"":""pass"",""work_budget"":1," &
         """priority_rule"":""campaign"",""autonomy_policy_digest"":""policy""}",
         Quality_Manager.Results.Invalid_Request, "duplicate campaign indicator is rejected");
      Write_Text (Definition ("coverage-90", 1, 2));
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "versioned campaign definition persisted");
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "same campaign definition is idempotent");
      Write_Text (Definition ("coverage-90", 1, 3));
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "conflicting content cannot reuse a campaign definition revision");
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Campaign_Target_Record, Values, 20, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Natural (Values.Length) = 2,
              "campaign population and baselines are frozen per project target");
      Quality_Manager.Campaigns.Start (Context, "coverage-90", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign starts from its frozen definition");
      Quality_Manager.Campaigns.Start (Context, "coverage-90", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "campaign start state precondition is enforced");
      Quality_Manager.Storage.Records.Save (Store, Work, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "shared remediation work persisted");
      Quality_Manager.Campaigns.Find_Shared_Work
        (Context, "global:coverage", Shared, Found, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Found
         and then To_String (Shared) = "work:shared-campaign",
         "campaign attaches to compatible active remediation instead of duplicating execution");
      Quality_Manager.Campaigns.Pause (Context, "coverage-90", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign pauses without rewriting baselines");
      Quality_Manager.Campaigns.Resume (Context, "coverage-90", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "paused campaign resumes");
      Quality_Manager.Campaigns.Update_Target
        (Context, "coverage-90", 7, "TST-03", 2, "unknown-outcome", Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "unknown campaign target outcome is rejected");
      Quality_Manager.Campaigns.Update_Target
        (Context, "coverage-90", 99, "TST-03", 2, "pass", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "unknown campaign target is explicit");
      Quality_Manager.Campaigns.Update_Target
        (Context, "coverage-90", 7, "TST-03", 1, "pass", Result);
      Assert (Result.Kind = Quality_Manager.Results.Stale_Evidence,
              "frozen baseline evidence cannot satisfy a campaign target as current evidence");
      Quality_Manager.Campaigns.Update_Target
        (Context, "coverage-90", 7, "TST-03", 2, "pass", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "first campaign target evaluated");
      Quality_Manager.Campaigns.Update_Target
        (Context, "coverage-90", 8, "TST-03", 2, "pass", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "second campaign target evaluated");
      Quality_Manager.Campaigns.Reconcile (Context, "coverage-90", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign target reconciliation succeeds");
      Quality_Manager.Storage.Read (Store, "campaign:coverage-90", Loaded, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Verified),
         "campaign completes only after every current target is satisfied");
      Quality_Manager.Campaigns.Pause (Context, "coverage-90", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "terminal campaign cannot be paused");
      Progress_Text := To_Unbounded_String
        (Quality_Manager.Campaigns.Progress (Context, "coverage-90", Result));
      Quality_Manager.Schemas.Validate_Versioned_JSON (To_String (Progress_Text), 1, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Ada.Strings.Fixed.Index (To_String (Progress_Text), """satisfied_targets"":2") > 0,
         "campaign progress is available as versioned structured output");

      Write_Text (Definition ("coverage-90", 2, 2));
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "new campaign definition revision is accepted");
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Campaign_Target_Record, Values, 20, Result);
      Assert (Natural (Values.Length) = 4, "historical campaign baselines are retained across revisions");

      Write_Text (Definition ("budgeted", 1, 1));
      Quality_Manager.Campaigns.Record_Execution (Context, "missing-campaign", Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "campaign execution accounting requires an existing campaign");
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Quality_Manager.Campaigns.Start (Context, "budgeted", Result);
      Quality_Manager.Campaigns.Record_Execution (Context, "budgeted", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign consumes work within its budget");
      Quality_Manager.Campaigns.Record_Execution (Context, "budgeted", Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "campaign budget exhaustion blocks additional execution");
      Quality_Manager.Campaigns.Cancel (Context, "budgeted", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "blocked campaign can be cancelled");

      Write_Text (Definition ("applicability", 1, 2, "pass-or-not-applicable"));
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Quality_Manager.Campaigns.Start (Context, "applicability", Result);
      Quality_Manager.Campaigns.Update_Target
        (Context, "applicability", 7, "TST-03", 2, "not-applicable", False, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "unjustified not-applicable evidence is retained but not satisfied");
      Quality_Manager.Campaigns.Update_Target
        (Context, "applicability", 7, "TST-03", 3, "not-applicable", True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "justified allowed not-applicable evidence satisfies its target");

      declare
         Original_Directory : constant String := Ada.Directories.Current_Directory;
         Wrapper_Root       : constant String := "/tmp/quality-manager-wrapper-cwd";
         Wrapper_Config     : constant String := Wrapper_Root & "/config/quality-manager.toml";
         Wrapper_Database   : constant String := "/tmp/quality-manager-wrapper.database";
         Wrapper_Store      : Quality_Manager.Storage.Store;
         Wrapper_Result     : Quality_Manager.Results.Operation_Result;
         File               : Ada.Text_IO.File_Type;

         procedure Remove (Name : String) is
         begin
            if Ada.Directories.Exists (Name) then
               Ada.Directories.Delete_File (Name);
            end if;
         end Remove;

         procedure Cleanup_Wrappers is
         begin
            if Ada.Directories.Current_Directory /= Original_Directory then
               Ada.Directories.Set_Directory (Original_Directory);
            end if;
            Remove (Wrapper_Config);
            Remove (Wrapper_Database);
            Remove (Wrapper_Database & ".wal");
            Remove (Wrapper_Database & ".journal");
            Remove (Wrapper_Database & ".lock");
            if Ada.Directories.Exists (Wrapper_Root & "/config") then
               Ada.Directories.Delete_Directory (Wrapper_Root & "/config");
            end if;
            if Ada.Directories.Exists (Wrapper_Root) then
               Ada.Directories.Delete_Directory (Wrapper_Root);
            end if;
         end Cleanup_Wrappers;
      begin
         Cleanup_Wrappers;
         Ada.Directories.Create_Directory (Wrapper_Root);
         Ada.Directories.Create_Directory (Wrapper_Root & "/config");
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Wrapper_Config);
         Ada.Text_IO.Put
           (File, "[coordinator]" & ASCII.LF & "database = """ & Wrapper_Database & """" & ASCII.LF
            & "[quality]" & ASCII.LF & "database = ""quality.db""" & ASCII.LF
            & "[integrations]" & ASCII.LF & "ada_quality = """
            & Original_Directory & "/bin/qm_adapter_fixture""" & ASCII.LF);
         Ada.Text_IO.Close (File);
         Quality_Manager.Storage.Open (Wrapper_Store, Wrapper_Database, True, Wrapper_Result);
         Quality_Manager.Storage.Records.Save
           (Wrapper_Store,
            Quality_Manager.Storage.Schema.Project'
              (Key => Project, Enabled => True, Last_Assessment_Run => 1,
               Last_Source_Fingerprint => To_Unbounded_String ("source-1")), Wrapper_Result);
         Quality_Manager.Storage.Records.Save
           (Wrapper_Store,
            Quality_Manager.Storage.Schema.Project'
              (Key => (To_Unbounded_String ("database-a"), 8, To_Unbounded_String ("/second")),
               Enabled => True, Last_Assessment_Run => 1,
               Last_Source_Fingerprint => To_Unbounded_String ("source-1")), Wrapper_Result);
         Quality_Manager.Storage.Close (Wrapper_Store, Wrapper_Result);
         Write_Text (Definition ("wrapper-campaign", 1, 2));
         Ada.Directories.Set_Directory (Wrapper_Root);
         Quality_Manager.Campaigns.Create (Base_Path);
         Quality_Manager.Campaigns.Start ("wrapper-campaign");
         Quality_Manager.Campaigns.Pause ("wrapper-campaign");
         Quality_Manager.Campaigns.Resume ("wrapper-campaign");
         Quality_Manager.Campaigns.Reconcile ("wrapper-campaign");
         begin
            Quality_Manager.Releases.Export_Evidence ("missing-release", "/tmp/missing-evidence.json");
            Assert (False, "missing public release export must fail");
         exception
            when Quality_Manager.Releases.Release_Error => null;
         end;
         begin
            Quality_Manager.Releases.Create ("7", "release");
            Assert (False, "release creation with an unavailable project path must fail");
         exception
            when Quality_Manager.Releases.Release_Error => null;
         end;
         Cleanup_Wrappers;
      exception
         when others =>
            Quality_Manager.Storage.Close (Wrapper_Store, Wrapper_Result);
            Cleanup_Wrappers;
            raise;
      end;
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Campaign_Workflow;

   procedure Test_Authorization_Policies (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Maximum : constant Quality_Manager.Policies.Policy_Set := Quality_Manager.Policies.Initial_Maximum;
      Restricted : Quality_Manager.Policies.Policy_Set := Maximum;
      Effective  : Quality_Manager.Policies.Policy_Set;
      Risk       : Quality_Manager.Policies.Risk_Decision;
      Result     : Quality_Manager.Results.Operation_Result;
      Project    : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
      Approval   : constant Quality_Manager.Storage.Schema.Approval :=
        (Approval_Id => To_Unbounded_String ("approval-1"), Project => Project,
         Plan_Id => To_Unbounded_String ("plan-1"), Plan_Revision => 2,
         Content_Digest => To_Unbounded_String ("content-1"),
         Authorized_Action => To_Unbounded_String ("publish"),
         Policy_Digest => To_Unbounded_String ("policy-1"), Approver => To_Unbounded_String ("human"),
         Created_At => 1, Expires_At => 100);
   begin
      Restricted.Permissions (Quality_Manager.Policies.Execute_Isolated_Changes) :=
        Quality_Manager.Policies.Denied;
      Restricted.Digest := To_Unbounded_String ("project-policy");
      Effective := Quality_Manager.Policies.Intersect (Maximum, Restricted);
      Assert
        (Effective.Permissions (Quality_Manager.Policies.Execute_Isolated_Changes)
           = Quality_Manager.Policies.Denied,
         "lower policy layers cannot expand coordinator authorization");
      Assert
        (not Quality_Manager.Policies.Permits_Automatically
           (Maximum, Quality_Manager.Policies.Approve_Improve_Plan),
         "Improve plan approval requires explicit authorization");
      Risk := Quality_Manager.Policies.Classify
        ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
          Public_API_Change => False, Build_Or_Release_Change => False,
          Required_Checks_Available => False, Prior_Failed_Attempts => 0, Scope_Known => True));
      Assert (Risk.Requires_Review and then Risk.Level = Quality_Manager.Model.High_Risk,
              "unavailable checks fail closed into human review");
      Risk := Quality_Manager.Policies.Classify
        ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
          Public_API_Change => False, Build_Or_Release_Change => False,
          Required_Checks_Available => True, Prior_Failed_Attempts => 0, Scope_Known => False));
      Assert (Risk.Requires_Review, "unknown scope requires review");
      Risk := Quality_Manager.Policies.Classify
        ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => True,
          Public_API_Change => False, Build_Or_Release_Change => False,
          Required_Checks_Available => True, Prior_Failed_Attempts => 0, Scope_Known => True));
      Assert (Risk.Level = Quality_Manager.Model.Critical_Risk, "security changes are critical risk");
      Risk := Quality_Manager.Policies.Classify
        ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
          Public_API_Change => True, Build_Or_Release_Change => False,
          Required_Checks_Available => True, Prior_Failed_Attempts => 0, Scope_Known => True));
      Assert (Risk.Requires_Review, "public API changes require review");
      Risk := Quality_Manager.Policies.Classify
        ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
          Public_API_Change => False, Build_Or_Release_Change => False,
          Required_Checks_Available => True, Prior_Failed_Attempts => 1, Scope_Known => True));
      Assert (Risk.Requires_Review, "prior failures require review");
      Risk := Quality_Manager.Policies.Classify
        ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
          Public_API_Change => False, Build_Or_Release_Change => False,
          Required_Checks_Available => True, Prior_Failed_Attempts => 0, Scope_Known => True));
      Assert (not Risk.Requires_Review, "known low-risk work may proceed automatically");
      Quality_Manager.Policies.Validate_Approval
        (Approval, Project, "plan-1", 2, "content-1", "publish", "policy-1", 50, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "exact unexpired approval is accepted");
      Quality_Manager.Policies.Validate_Approval
        (Approval, Project, "plan-1", 3, "content-1", "publish", "policy-1", 50, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "approval cannot authorize another plan revision");
      Quality_Manager.Policies.Validate_Approval
        (Approval, Project, "plan-1", 2, "content-1", "publish", "policy-1", 101, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "expired approval cannot authorize work");
   end Test_Authorization_Policies;

   procedure Test_Release_Qualification (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Path        : constant String := "/tmp/quality-manager-release.database";
      Export_Path : constant String := "/tmp/quality-manager-release-evidence.json";
      Store       : aliased Quality_Manager.Storage.Store;
      Context     : Quality_Manager.Releases.Context;
      Result      : Quality_Manager.Results.Operation_Result;
      Release_Id  : Unbounded_String;
      Decision    : Quality_Manager.Releases.Qualification_Decision;
      Invalidated : Boolean;
      Project     : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
      Assessment  : constant Quality_Manager.Verification.Assessment_Evidence :=
        (Assessment_Id => 5, Project_Id => 7, Project_Path => To_Unbounded_String ("/project"),
         Source_Fingerprint => To_Unbounded_String ("source-1"),
         Policy_Fingerprint => To_Unbounded_String ("policy-1"),
         Toolchain_Fingerprint => To_Unbounded_String ("toolchain-1"),
         Completed => True, Complete => True, Indicator_Count => 33, Violations => 0,
         Coverage_Basis_Points => 9_000, Proof_Applicable => True, Proof_Passed => True);
      Checks : Quality_Manager.Releases.Check_Results :=
        (Candidate_Commit => To_Unbounded_String ("commit-1"),
         Source_Fingerprint => To_Unbounded_String ("source-1"),
         Release_Config_Digest => To_Unbounded_String ("release-config-1"),
         Clean_Build => True, Reproducible_Build => True, AUnit_Passed => True,
         Proof_Applicable => True, GNATprove_Passed => True,
         Coverage_Basis_Points => 8_999, Release_Checks_Passed => True);
      References : constant Quality_Manager.Releases.Evidence_References :=
        (Improve_Audit => To_Unbounded_String ("improve-audit-1"),
         Native_Audit => To_Unbounded_String ("native-audit-1"),
         Regression_Evidence => To_Unbounded_String ("comparison-1"),
         Authorization_Audit => To_Unbounded_String ("approval-1"));
      Recovered_Checks : Quality_Manager.Releases.Check_Results;
      Actual_Checks    : Quality_Manager.Releases.Check_Results;
      Journal_Record   : Quality_Manager.Storage.Stored_Entity;
      Release_Fixture  : constant String :=
        (if Ada.Directories.Exists (Ada.Directories.Current_Directory & "/fixtures/release_project")
         then Ada.Directories.Current_Directory & "/fixtures/release_project"
         else Ada.Directories.Current_Directory & "/tests/fixtures/release_project");
      Tool_Fixture     : constant String :=
        (if Ada.Directories.Exists (Ada.Directories.Current_Directory & "/bin/qm_adapter_fixture")
         then Ada.Directories.Current_Directory & "/bin/qm_adapter_fixture"
         else Ada.Directories.Current_Directory & "/tests/bin/qm_adapter_fixture");

      procedure Check_Corrupt_Evidence (Commit, Payload : String) is
         Corrupt_Id : Unbounded_String;
         Candidate  : Quality_Manager.Storage.Schema.Release;
         Evidence   : Quality_Manager.Storage.Stored_Entity;
      begin
         Quality_Manager.Releases.Create
           (Context, Project, Commit, "source-corrupt", "policy-1", "toolchain-1",
            "release-config-1", Corrupt_Id, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "corrupt evidence fixture created");
         Candidate :=
           (Release_Id => Corrupt_Id, Project => Project,
            Candidate_Commit => To_Unbounded_String (Commit),
            Source_Digest => To_Unbounded_String ("source-corrupt"),
            Policy_Digest => To_Unbounded_String ("policy-1"),
            Toolchain => To_Unbounded_String ("toolchain-1"),
            Release_Config => To_Unbounded_String ("release-config-1"),
            Generation => 1, Final_Assessment => 1, Coverage_Basis_Points => 9_000,
            State => Quality_Manager.Model.Verified);
         Quality_Manager.Storage.Records.Save (Store, Candidate, Result);
         Evidence :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
            Entity_Key => To_Unbounded_String
              ("release-evidence:" & To_String (Corrupt_Id) & ":1"),
            State => To_Unbounded_String ("QUALIFIED"),
            Payload => To_Unbounded_String (Payload), Terminal => True, Generation => 1);
         Quality_Manager.Storage.Put (Store, Evidence, Result);
         Quality_Manager.Releases.Export_Evidence
           (Context, To_String (Corrupt_Id), Export_Path, Result);
         Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
                 "corrupt release evidence is rejected before export");
      end Check_Corrupt_Evidence;

      procedure Check_Corrupt_Chunk_Digest is
         Corrupt_Id : Unbounded_String;
         Candidate  : Quality_Manager.Storage.Schema.Release;
         Evidence   : Quality_Manager.Storage.Stored_Entity;
      begin
         Quality_Manager.Releases.Create
           (Context, Project, "commit-corrupt-chunk", "source-corrupt", "policy-1", "toolchain-1",
            "release-config-1", Corrupt_Id, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "chunk digest fixture created");
         Candidate :=
           (Release_Id => Corrupt_Id, Project => Project,
            Candidate_Commit => To_Unbounded_String ("commit-corrupt-chunk"),
            Source_Digest => To_Unbounded_String ("source-corrupt"),
            Policy_Digest => To_Unbounded_String ("policy-1"),
            Toolchain => To_Unbounded_String ("toolchain-1"),
            Release_Config => To_Unbounded_String ("release-config-1"),
            Generation => 1, Final_Assessment => 1, Coverage_Basis_Points => 9_000,
            State => Quality_Manager.Model.Verified);
         Quality_Manager.Storage.Records.Save (Store, Candidate, Result);
         Evidence :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
            Entity_Key => To_Unbounded_String
              ("release-evidence-chunk:" & To_String (Corrupt_Id) & ":1:1"),
            State => To_Unbounded_String ("CHUNK"),
            Payload => To_Unbounded_String ("{""schema_version"":1}"),
            Terminal => True, Generation => 1);
         Quality_Manager.Storage.Put (Store, Evidence, Result);
         Evidence.Entity_Key := To_Unbounded_String
           ("release-evidence:" & To_String (Corrupt_Id) & ":1");
         Evidence.State := To_Unbounded_String ("QUALIFIED");
         Evidence.Payload := To_Unbounded_String ("digest=wrong" & ASCII.LF & "chunks=1");
         Quality_Manager.Storage.Put (Store, Evidence, Result);
         Quality_Manager.Releases.Export_Evidence
           (Context, To_String (Corrupt_Id), Export_Path, Result);
         Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
                 "chunked release evidence is rejected when its bundle digest differs");
      end Check_Corrupt_Chunk_Digest;

      procedure Cleanup is
      begin
         if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
         if Ada.Directories.Exists (Export_Path) then Ada.Directories.Delete_File (Export_Path); end if;
      end Cleanup;
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "release store opened");
      Quality_Manager.Releases.Create
        (Context, Project, "commit", "source", "policy", "toolchain", "config",
         Release_Id, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "uninitialized release context fails closed");
      Quality_Manager.Releases.Initialize (Context, Store'Unchecked_Access);
      declare
         Wrong_Kind : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Project_Record,
            Entity_Key => To_Unbounded_String ("release:wrong-kind"),
            State => To_Unbounded_String ("DISCOVERED"), Payload => To_Unbounded_String ("{}"),
            Terminal => False, Generation => 1);
         Incomplete : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
            Entity_Key => To_Unbounded_String ("release:incomplete"),
            State => To_Unbounded_String ("DISCOVERED"), Payload => To_Unbounded_String ("{}"),
            Terminal => False, Generation => 1);
         Unknown_State : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
            Entity_Key => To_Unbounded_String ("release:unknown-state"),
            State => To_Unbounded_String ("UNKNOWN_STATE"),
            Payload => To_Unbounded_String
              ("{""quality_project_id"":7,""generation"":1}"),
            Terminal => False, Generation => 1);
      begin
         Quality_Manager.Storage.Put (Store, Wrong_Kind, Result);
         Quality_Manager.Releases.Export_Evidence (Context, "wrong-kind", Export_Path, Result);
         Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
                 "release identity cannot alias another record kind");
         Quality_Manager.Storage.Put (Store, Incomplete, Result);
         Quality_Manager.Releases.Export_Evidence (Context, "incomplete", Export_Path, Result);
         Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
                 "incomplete durable release identity is rejected");
         Quality_Manager.Storage.Put (Store, Unknown_State, Result);
         Quality_Manager.Releases.Export_Evidence (Context, "unknown-state", Export_Path, Result);
         Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
                 "unknown durable release state is a compatibility error");
      end;
      Quality_Manager.Releases.Create
        (Context, Project, "", "source", "policy", "toolchain", "config",
         Release_Id, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "incomplete release candidate identity is rejected");
      Quality_Manager.Releases.Create
        (Context, Project, "commit-1", "source-1", "policy-1", "toolchain-1",
         "release-config-1", Release_Id, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Length (Release_Id) = 64,
              "immutable release candidate identity created");
      Quality_Manager.Releases.Evaluate
        (Context, To_String (Release_Id), Assessment, Checks, References, Decision, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Negative_Result and then not Decision.Qualified,
         "coverage below 90 percent blocks qualification");
      Quality_Manager.Releases.Export_Evidence
        (Context, To_String (Release_Id), Export_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
              "unqualified candidate cannot export evidence");
      Checks.Coverage_Basis_Points := 9_000;
      Quality_Manager.Releases.Evaluate
        (Context, To_String (Release_Id), Assessment, Checks, References, Decision, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Decision.Qualified
         and then Length (Decision.Bundle_Digest) = 64,
         "all exact release gates produce a qualified evidence bundle");
      Quality_Manager.Releases.Export_Evidence
        (Context, To_String (Release_Id), Export_Path, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Ada.Directories.Exists (Export_Path),
         "qualified evidence exports only after digest verification");
      Quality_Manager.Releases.Export_Evidence
        (Context, To_String (Release_Id), "/tmp/no-such-release-output/evidence.json", Result);
      Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
              "release evidence export reports an unwritable destination");
      Check_Corrupt_Evidence ("commit-corrupt-envelope", "not-an-envelope");
      Check_Corrupt_Evidence
        ("commit-corrupt-digest", "digest=wrong" & ASCII.LF & "{""schema_version"":1}");
      Check_Corrupt_Chunk_Digest;
      Quality_Manager.Releases.Invalidate_If_Changed
        (Context, To_String (Release_Id), "commit-2", "source-2", Invalidated, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Invalidated,
              "source modification invalidates a prior qualification");
      Quality_Manager.Releases.New_Generation
        (Context, To_String (Release_Id), "commit-1", "source-1", "policy-1", "toolchain-1",
         "release-config-1", Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "candidate generation requires a new exact source");
      Quality_Manager.Releases.New_Generation
        (Context, To_String (Release_Id), "commit-2", "source-2", "policy-1", "toolchain-1",
         "release-config-1", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "source-changing remediation creates a new candidate generation");
      Quality_Manager.Storage.Prepare_Operation
        (Store, 300, "release-checks", "fixture", "release-checks:300", Result);
      Quality_Manager.Storage.Advance_Operation
        (Store, 300, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         "release-checks:300", "fixture started", Result);
      Quality_Manager.Releases.Run_Local_Checks
        (Context, 0, "/project", "commit-2", "source-2", "release-config-1", 9_000,
         False, Recovered_Checks, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "release checks require a durable operation identity");
      Journal_Record :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
         Entity_Key => To_Unbounded_String ("release-checks:300"),
         State => To_Unbounded_String ("OBSERVED"),
         Payload => To_Unbounded_String
           ("{""candidate_commit"":""commit-2"",""source_fingerprint"":""source-2""," &
            """release_config_digest"":""release-config-1"",""clean_build"":true," &
            """reproducible_build"":true,""aunit_passed"":true,""proof_applicable"":false," &
            """gnatprove_passed"":true,""coverage_basis_points"":9000," &
            """release_checks_passed"":true}"),
         Terminal => True, Generation => 1);
      Quality_Manager.Storage.Put (Store, Journal_Record, Result);
      Quality_Manager.Releases.Run_Local_Checks
        (Context, 300, "/project", "commit-2", "source-2", "release-config-1", 9_000,
         False, Recovered_Checks, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Recovered_Checks.Release_Checks_Passed,
         "interrupted idempotent release checks adopt their durable observed result");
      Quality_Manager.Storage.Read (Store, "journal:300", Journal_Record, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then To_String (Journal_Record.State) = Quality_Manager.Journal.Journal_State'Image
           (Quality_Manager.Journal.Committed),
         "adopted release checks complete their recovery journal");
      Quality_Manager.Releases.Run_Local_Checks_With_Tools
        (Context, 301, Release_Fixture,
         "fixture-commit",
         "source-2", "release-config-1", 9_000, False,
         Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Actual_Checks.Clean_Build
         and then Actual_Checks.Reproducible_Build
         and then Actual_Checks.AUnit_Passed
         and then Actual_Checks.Release_Checks_Passed,
         "local release checks run clean build, reproducibility, and test gates: "
         & Quality_Manager.Results.Message (Result)
         & " commit=" & To_String (Actual_Checks.Candidate_Commit)
         & " clean=" & Boolean'Image (Actual_Checks.Clean_Build)
         & " reproducible=" & Boolean'Image (Actual_Checks.Reproducible_Build)
         & " tests=" & Boolean'Image (Actual_Checks.AUnit_Passed));
      Quality_Manager.Releases.Run_Local_Checks_With_Tools
        (Context, 302, Release_Fixture,
         "fixture-commit",
         "source-2", "release-config-1", 9_000, True,
         Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Actual_Checks.GNATprove_Passed,
         "applicable proof gate is executed through the configured release toolchain");
      Quality_Manager.Releases.Run_Local_Checks_With_Tools
        (Context, 303, Release_Fixture, "commit-2", "source-2", "release-config-1", 9_000,
         False, "/tmp/no-such-git-tool", "/tmp/no-such-alire-tool", Actual_Checks, Result);
      Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
              "release check infrastructure start failures are distinguished from negative gates");
      Quality_Manager.Releases.Run_Local_Checks_With_Tools
        (Context, 304, Release_Fixture, "commit-2", "source-2", "release-config-1", 9_000,
         False, "/bin/false", "/bin/false", Actual_Checks, Result);
      Assert (Result.Kind = Quality_Manager.Results.Negative_Result,
              "completed failing release commands remain negative gate outcomes");
      declare
         Release_Project : constant Quality_Manager.Identities.Project_Key :=
           (To_Unbounded_String ("database-a"), 7, To_Unbounded_String (Release_Fixture));
         Candidate_Commit : constant String := "fixture-commit";
         Release_Quality : Quality_Manager.Integrations.Quality.Adapter;
         Qualified_Id    : Unbounded_String;
         First_Digest    : Unbounded_String;
      begin
         Quality_Manager.Integrations.Quality.Initialize
           (Release_Quality, Tool_Fixture, "release-quality.db", Release_Fixture);
         Quality_Manager.Releases.Create
           (Context, Release_Project, Candidate_Commit, "candidate-source", "policy", "toolchain",
            "release-config-qualified", Qualified_Id, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success,
                 "configured qualification fixture creates an exact candidate");
         Quality_Manager.Releases.Qualify_With_Tools
           (Context, Release_Quality, To_String (Qualified_Id), Tool_Fixture, Tool_Fixture,
            Decision, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success and then Decision.Qualified
            and then Length (Decision.Bundle_Digest) = 64,
            "configured qualification obtains fresh evidence and runs every local gate: "
            & Quality_Manager.Results.Message (Result));
         First_Digest := Decision.Bundle_Digest;
         Quality_Manager.Releases.Qualify_With_Tools
           (Context, Release_Quality, To_String (Qualified_Id), Tool_Fixture, Tool_Fixture,
            Decision, Result);
         Assert
           (Result.Kind = Quality_Manager.Results.Success and then Decision.Qualified
            and then Decision.Bundle_Digest = First_Digest,
            "repeated qualification adopts journaled assessment and check evidence idempotently");
      end;
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Release_Qualification;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Caller.Create ("configuration validation", Test_Config_Validation'Access));
      Result.Add_Test (Caller.Create ("configuration UTF-8", Test_Config_Encoding'Access));
      Result.Add_Test (Caller.Create ("path normalization", Test_Path_Normalization'Access));
      Result.Add_Test (Caller.Create ("strict CLI", Test_CLI'Access));
      Result.Add_Test (Caller.Create ("operational control", Test_Operational_Control'Access));
      Result.Add_Test (Caller.Create ("CLI executable", Test_CLI_Executable'Access));
      Result.Add_Test (Caller.Create ("versioned JSON", Test_JSON_Contract'Access));
      Result.Add_Test (Caller.Create ("doctor output", Test_Doctor_Output'Access));
      Result.Add_Test (Caller.Create ("qualified identities", Test_Identities'Access));
      Result.Add_Test (Caller.Create ("deterministic identities", Test_Deterministic_Identities'Access));
      Result.Add_Test (Caller.Create ("transitions and journal", Test_Transitions_And_Journal'Access));
      Result.Add_Test (Caller.Create ("persistent storage", Test_Persistent_Storage'Access));
      Result.Add_Test (Caller.Create ("storage boundaries", Test_Storage_Boundaries'Access));
      Result.Add_Test (Caller.Create ("corrupt storage", Test_Corrupt_Storage'Access));
      Result.Add_Test (Caller.Create ("bounded process adapter", Test_Process_Adapter'Access));
      Result.Add_Test (Caller.Create ("JSON CLI contracts", Test_JSON_CLI_Contracts'Access));
      Result.Add_Test (Caller.Create ("durable native dispatch", Test_Native_Dispatch'Access));
      Result.Add_Test (Caller.Create ("independent verification", Test_Verification_Engine'Access));
      Result.Add_Test (Caller.Create ("verification workflow", Test_Verification_Workflow'Access));
      Result.Add_Test (Caller.Create ("durable scheduler", Test_Durable_Scheduler'Access));
      Result.Add_Test (Caller.Create ("maintenance cycle", Test_Maintenance_Cycle'Access));
      Result.Add_Test (Caller.Create ("campaign workflow", Test_Campaign_Workflow'Access));
      Result.Add_Test (Caller.Create ("authorization policies", Test_Authorization_Policies'Access));
      Result.Add_Test (Caller.Create ("release qualification", Test_Release_Qualification'Access));
      return Result;
   end Suite;
end Quality_Manager_Test_Suite;
