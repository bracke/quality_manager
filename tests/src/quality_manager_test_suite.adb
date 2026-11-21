with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;

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
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Journal.Recovery_Action;
   use type Quality_Manager.Storage.Record_Kind;
   use type Quality_Manager.Integrations.Runner.Execution_State;
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Model.Outcome_Kind;
   use type Quality_Manager.Model.Risk_Level;
   use type Quality_Manager.Verification.Retry_Action;
   use type Quality_Manager.Scheduler.Work_Resource;
   use type Quality_Manager.Maintenance.Assessment_Reason;
   use type Quality_Manager.Policies.Permission;

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
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
   exception
      when others =>
         Quality_Manager.Storage.Close (Store, Result);
         Cleanup;
         raise;
   end Test_Operational_Control;

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
            and then Ada.Strings.Fixed.Index (To_String (Response.Document), "--dry-run --json") > 0,
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

         Quality_Manager.Integrations.Runner.Initialize
           (Runner_Adapter, "./bin/qm_adapter_fixture");
         Quality_Manager.Integrations.Runner.Capabilities (Runner_Adapter, Response);
         Assert
           (Response.Status.Kind = Quality_Manager.Results.Success,
            "model_runner required headless capabilities are negotiated");

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
      Quality_Manager.Dispatch.Bind_Published_Task (Store, Mapping, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "published native mapping retained exactly");
      Quality_Manager.Integrations.Runner.Initialize (Runner, "./bin/qm_adapter_fixture");

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

      function Assessment_JSON (Source : String; Complete : Boolean := True) return String is
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
               Indicator : constant String := "TST-" & (if Index < 10 then "0" else "") & Number;
            begin
               Append
                 (Text,
                  "{""indicator"":""" & Indicator & """,""execution"":""succeeded""," &
                  """compliance"":""" &
                  (if not Complete and then Index = 1 then "unknown" else "pass") &
                  """,""applicable"":true,""summary"":""ok""," &
                  """evidence"":""fixture"",""measurement"":" &
                  (if Index = 3 then "{""basis_points"":9000}" else "{}") &
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
         Interrupted.Project_Selector := To_Unbounded_String ("9");
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

      Quality_Manager.Scheduler.Initialize (Scheduler);
      Quality_Manager.Scheduler.Enqueue_Work
        (Scheduler, "work:low", "project:one", Quality_Manager.Priorities.Campaign_Work,
         1, Quality_Manager.Scheduler.Agent_Resource);
      Quality_Manager.Scheduler.Enqueue_Work
        (Scheduler, "work:critical", "project:two", Quality_Manager.Priorities.Critical_Regression,
         2, Quality_Manager.Scheduler.Agent_Resource);
      Quality_Manager.Scheduler.Take_Next (Scheduler, Work_Id, Resource, Found);
      Assert (Found and then To_String (Work_Id) = "work:critical",
              "critical regressions sort before older campaign work");
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
      Quality_Manager.Scheduler.Initialize (Scheduler);
      Quality_Manager.Scheduler.Configure (Scheduler, Store'Unchecked_Access, 4, 1);
      Quality_Manager.Integrations.Quality.Initialize
        (Quality, "./bin/qm_adapter_fixture", "quality.db");
      Quality_Manager.Maintenance.Initialize
        (Context, Store'Unchecked_Access, Scheduler'Unchecked_Access, Quality);
      Quality_Manager.Maintenance.Run_Cycle (Context, "", False, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Quality_Manager.Scheduler.Pending_Count (Scheduler) = 2,
         "maintenance inventory schedules due assessment work without blocking on disabled projects: "
         & Quality_Manager.Results.Message (Result)
         & " pending=" & Natural'Image (Quality_Manager.Scheduler.Pending_Count (Scheduler)));
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Project_Record, Values, 10, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Natural (Values.Length) = 3,
              "qualified project inventory is synchronized across multiple projects");
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Cycle_Record, Values, 10, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Natural (Values.Length) = 3,
              "each selected project has independent durable cycle state");
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Work_Item_Record, Values, 10, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Natural (Values.Length) = 2
         and then To_String (Values.First_Element.State) = Quality_Manager.Model.Work_State'Image
           (Quality_Manager.Model.Queued),
         "due assessment is committed before entering the in-memory scheduler");
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

      function Definition (Id : String; Revision, Budget : Positive) return String is
        ("{""schema_version"":1,""campaign_id"":""" & Id
         & """,""definition_revision"":"
         & Ada.Strings.Fixed.Trim (Positive'Image (Revision), Ada.Strings.Both)
         & ",""projects"":["
         & "{""quality_database_id"":""database-a"",""project_id"":7,""path"":""/project"","
         & """baseline_assessment"":1},"
         & "{""quality_database_id"":""database-a"",""project_id"":8,""path"":""/second"","
         & """baseline_assessment"":1}],"
         & """indicators"":[""TST-03""],""target"":""pass"",""work_budget"":"
         & Ada.Strings.Fixed.Trim (Positive'Image (Budget), Ada.Strings.Both)
         & ",""priority_rule"":""campaign"",""autonomy_policy_digest"":""policy-1""}");

      procedure Cleanup is
      begin
         Remove_Test_File;
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      end Cleanup;
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign store opened");
      Quality_Manager.Campaigns.Initialize (Context, Store'Unchecked_Access);
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
      Write_Text (Definition ("coverage-90", 1, 2));
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "versioned campaign definition persisted");
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "same campaign definition is idempotent");
      Quality_Manager.Storage.List
        (Store, Quality_Manager.Storage.Campaign_Target_Record, Values, 20, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Natural (Values.Length) = 2,
              "campaign population and baselines are frozen per project target");
      Quality_Manager.Campaigns.Start (Context, "coverage-90", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign starts from its frozen definition");
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
      Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
      Quality_Manager.Campaigns.Start (Context, "budgeted", Result);
      Quality_Manager.Campaigns.Record_Execution (Context, "budgeted", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "campaign consumes work within its budget");
      Quality_Manager.Campaigns.Record_Execution (Context, "budgeted", Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "campaign budget exhaustion blocks additional execution");
      Quality_Manager.Campaigns.Cancel (Context, "budgeted", Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "blocked campaign can be cancelled");
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
      Quality_Manager.Policies.Validate_Approval
        (Approval, Project, "plan-1", 2, "content-1", "publish", "policy-1", 50, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "exact unexpired approval is accepted");
      Quality_Manager.Policies.Validate_Approval
        (Approval, Project, "plan-1", 3, "content-1", "publish", "policy-1", 50, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "approval cannot authorize another plan revision");
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
      Journal_Record   : Quality_Manager.Storage.Stored_Entity;

      procedure Cleanup is
      begin
         if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
         if Ada.Directories.Exists (Export_Path) then Ada.Directories.Delete_File (Export_Path); end if;
      end Cleanup;
   begin
      Cleanup;
      Quality_Manager.Storage.Open (Store, Path, True, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "release store opened");
      Quality_Manager.Releases.Initialize (Context, Store'Unchecked_Access);
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
      Quality_Manager.Releases.Invalidate_If_Changed
        (Context, To_String (Release_Id), "commit-2", "source-2", Invalidated, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Invalidated,
              "source modification invalidates a prior qualification");
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
      Result.Add_Test (Caller.Create ("versioned JSON", Test_JSON_Contract'Access));
      Result.Add_Test (Caller.Create ("doctor output", Test_Doctor_Output'Access));
      Result.Add_Test (Caller.Create ("qualified identities", Test_Identities'Access));
      Result.Add_Test (Caller.Create ("deterministic identities", Test_Deterministic_Identities'Access));
      Result.Add_Test (Caller.Create ("transitions and journal", Test_Transitions_And_Journal'Access));
      Result.Add_Test (Caller.Create ("persistent storage", Test_Persistent_Storage'Access));
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
