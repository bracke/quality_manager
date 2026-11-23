separate (Quality_Manager_Test_Suite)
procedure Test_Config_Validation (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Settings : Quality_Manager.Config.Settings;
   Result   : Quality_Manager.Results.Operation_Result;
begin
   Quality_Manager.Config.Load ("/tmp/qm-no-such-config.toml", True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing required config is rejected");

   Write_Text ("");
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "an empty configuration uses defaults");

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

   Write_Text ("[integrations]" & ASCII.LF & "ada_quality_summary = """"" & ASCII.LF);
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty Summary executable is rejected");

   Write_Text ("[integrations]" & ASCII.LF & "improve = """"" & ASCII.LF);
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty Improve executable is rejected");

   Write_Text ("[coordinator]" & ASCII.LF & "database = """"" & ASCII.LF);
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty coordinator path is rejected");

   Write_Text ("[integrations]" & ASCII.LF & "improve_state = """"" & ASCII.LF);
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty Improve state path is rejected");

   Write_Text ("[scheduler]" & ASCII.LF & "assessment_workers = 0" & ASCII.LF);
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "invalid assessment worker count is rejected");

   Write_Text ("[scheduler]" & ASCII.LF & "maximum_task_seconds = 0" & ASCII.LF);
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "invalid task duration is rejected");

   Write_Text ("[scheduler]" & ASCII.LF & "remediation_attempts = 0" & ASCII.LF);
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "invalid remediation budget is rejected");

   Write_Text ("[autonomy]" & ASCII.LF & "dry_run = ""maybe""" & ASCII.LF);
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "non-boolean dry-run policy is rejected");

   Write_Text
     ("[coordinator]" & ASCII.LF & "database = ""/tmp/coordinator.db""" & ASCII.LF
      & "[quality]" & ASCII.LF & "database = ""/tmp/quality.db""" & ASCII.LF
      & "policy = ""/tmp/quality-policy.toml""" & ASCII.LF
      & "[integrations]" & ASCII.LF & "ada_quality = ""ada-quality-fixture""" & ASCII.LF
      & "ada_quality_summary = ""ada-quality-summary-fixture""" & ASCII.LF
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
      and then To_String (Settings.Ada_Quality_Summary_Executable) = "ada-quality-summary-fixture"
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

