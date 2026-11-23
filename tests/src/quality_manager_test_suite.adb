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
with Hostkit.FS;

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
with Quality_Manager.Recovery;
with Quality_Manager.Releases;
with Quality_Manager.Release_Artifacts;
with Quality_Manager.Reproducibility;
with Quality_Manager.Results;
with Quality_Manager.Scheduler;
with Quality_Manager.Priorities;
with Quality_Manager.Policies;
with Quality_Manager.Schemas;
with Quality_Manager.Storage.Schema;
with Quality_Manager.Storage.Decoding;
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

   procedure Test_Config_Validation (Item : in out Fixture) is separate;

   procedure Test_Config_Encoding (Item : in out Fixture) is separate;

   procedure Test_Path_Normalization (Item : in out Fixture) is separate;

   procedure Test_CLI (Item : in out Fixture) is separate;

   procedure Test_Operational_Control (Item : in out Fixture) is separate;

   procedure Test_CLI_Executable (Item : in out Fixture) is separate;

   procedure Test_JSON_Contract (Item : in out Fixture) is separate;

   procedure Test_Doctor_Output (Item : in out Fixture) is separate;

   procedure Test_Identities (Item : in out Fixture) is separate;

   procedure Test_Deterministic_Identities (Item : in out Fixture) is separate;

   procedure Test_Transitions_And_Journal (Item : in out Fixture) is separate;

   procedure Test_Persistent_Storage (Item : in out Fixture) is separate;

   procedure Test_Storage_Boundaries (Item : in out Fixture) is separate;

   procedure Test_Corrupt_Storage (Item : in out Fixture) is separate;

   procedure Test_Process_Adapter (Item : in out Fixture) is separate;

   procedure Test_JSON_CLI_Contracts (Item : in out Fixture) is separate;

   procedure Test_Authorized_Publication (Item : in out Fixture) is separate;

   procedure Test_Native_Dispatch (Item : in out Fixture) is separate;

   procedure Test_Verification_Engine (Item : in out Fixture) is separate;

   procedure Test_Verification_Workflow (Item : in out Fixture) is separate;

   procedure Test_Durable_Scheduler (Item : in out Fixture) is separate;

   procedure Test_Maintenance_Cycle (Item : in out Fixture) is separate;

   procedure Test_Campaign_Workflow (Item : in out Fixture) is separate;

   procedure Test_Authorization_Policies (Item : in out Fixture) is separate;

   procedure Test_Release_Qualification (Item : in out Fixture) is separate;

   procedure Test_Release_Artifacts (Item : in out Fixture) is separate;

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
      Result.Add_Test (Caller.Create ("authorized publication", Test_Authorized_Publication'Access));
      Result.Add_Test (Caller.Create ("durable native dispatch", Test_Native_Dispatch'Access));
      Result.Add_Test (Caller.Create ("independent verification", Test_Verification_Engine'Access));
      Result.Add_Test (Caller.Create ("verification workflow", Test_Verification_Workflow'Access));
      Result.Add_Test (Caller.Create ("durable scheduler", Test_Durable_Scheduler'Access));
      Result.Add_Test (Caller.Create ("maintenance cycle", Test_Maintenance_Cycle'Access));
      Result.Add_Test (Caller.Create ("campaign workflow", Test_Campaign_Workflow'Access));
      Result.Add_Test (Caller.Create ("authorization policies", Test_Authorization_Policies'Access));
      Result.Add_Test (Caller.Create ("release qualification", Test_Release_Qualification'Access));
      Result.Add_Test (Caller.Create ("signed release artifacts", Test_Release_Artifacts'Access));
      return Result;
   end Suite;
end Quality_Manager_Test_Suite;
