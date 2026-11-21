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
with Quality_Manager.Reporting;
with Quality_Manager.Results;
with Quality_Manager.Schemas;

package body Quality_Manager_Test_Suite is
   use type Quality_Manager.CLI.Command_Kind;
   use type Quality_Manager.Results.Result_Kind;

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
      return Result;
   end Suite;
end Quality_Manager_Test_Suite;
