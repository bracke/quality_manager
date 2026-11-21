with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;

with Quality_Manager.CLI;
with Quality_Manager.Config;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Integrations.Summary;
with Quality_Manager.Journal;
with Quality_Manager.Model;
with Quality_Manager.Reporting;
with Quality_Manager.Results;
with Quality_Manager.Schemas;
with Quality_Manager.Storage.Schema;
with Quality_Manager.Storage.Migrations;
with Quality_Manager.Storage.Records;
with Quality_Manager.Transitions;

package body Quality_Manager_Test_Suite is
   use type Quality_Manager.CLI.Command_Kind;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Journal.Recovery_Action;
   use type Quality_Manager.Storage.Record_Kind;

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
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "unimplemented mutation command rejected");

      Args.Clear;
      Args.Append ("doctor");
      Quality_Manager.CLI.Parse (Args, Options, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "doctor accepted");
      Assert (Options.Command = Quality_Manager.CLI.Doctor_Command, "doctor selected");
   end Test_CLI;

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
      Output   : constant String := Quality_Manager.Reporting.Doctor
        (Settings, Quality_Manager.CLI.JSON_Output);
      Result   : Quality_Manager.Results.Operation_Result;
   begin
      Quality_Manager.Schemas.Validate_Versioned_JSON (Output, 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "doctor JSON is versioned JSON");
      Assert (Ada.Strings.Fixed.Index (Output, """write_coordination"": ""disabled""") > 0,
              "doctor reports write fencing");
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
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), "project list --json") > 0,
            "Ada Quality project inventory requires project-list-v1");
         Quality_Manager.Integrations.Quality.Plan_Check
           (Quality_Adapter, "7", "ci", False, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), "--dry-run --json") > 0,
            "Ada Quality planning requires check-plan-v1");
         Quality_Manager.Integrations.Quality.Read_Assessment (Quality_Adapter, 4, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), "assessment show 4 --json") > 0,
            "Ada Quality assessment command is exact and versioned");
         Quality_Manager.Integrations.Quality.Compare (Quality_Adapter, 3, 4, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), "assessment diff 3 4 --json") > 0,
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

         Quality_Manager.Integrations.Improve.Initialize
           (Improve_Adapter, "./bin/qm_adapter_fixture", "improve.toml", "quality.db", "improve.db");
         Quality_Manager.Integrations.Improve.Read_Plan (Improve_Adapter, "PLAN-001", 2, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index
              (To_String (Response.Document), "plan show PLAN-001 --revision 2") > 0,
            "Improve exact-revision command uses schema version 2");
         Quality_Manager.Integrations.Improve.Verify_Project
           (Improve_Adapter, "7", 2, 4, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success
            and then Ada.Strings.Fixed.Index
              (To_String (Response.Document), "verify --project 7 --revision 2 --run 4") > 0,
            "Improve project verification binds plan revision and assessment");
      end;
   end Test_JSON_CLI_Contracts;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Caller.Create ("configuration validation", Test_Config_Validation'Access));
      Result.Add_Test (Caller.Create ("configuration UTF-8", Test_Config_Encoding'Access));
      Result.Add_Test (Caller.Create ("path normalization", Test_Path_Normalization'Access));
      Result.Add_Test (Caller.Create ("strict CLI", Test_CLI'Access));
      Result.Add_Test (Caller.Create ("versioned JSON", Test_JSON_Contract'Access));
      Result.Add_Test (Caller.Create ("doctor output", Test_Doctor_Output'Access));
      Result.Add_Test (Caller.Create ("qualified identities", Test_Identities'Access));
      Result.Add_Test (Caller.Create ("deterministic identities", Test_Deterministic_Identities'Access));
      Result.Add_Test (Caller.Create ("transitions and journal", Test_Transitions_And_Journal'Access));
      Result.Add_Test (Caller.Create ("persistent storage", Test_Persistent_Storage'Access));
      Result.Add_Test (Caller.Create ("corrupt storage", Test_Corrupt_Storage'Access));
      Result.Add_Test (Caller.Create ("bounded process adapter", Test_Process_Adapter'Access));
      Result.Add_Test (Caller.Create ("JSON CLI contracts", Test_JSON_CLI_Contracts'Access));
      return Result;
   end Suite;
end Quality_Manager_Test_Suite;
