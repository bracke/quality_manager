separate (Quality_Manager_Test_Suite)
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
        ((if Ada.Directories.Exists (Ada.Directories.Current_Directory & "/bin/quality-manager")
          then Ada.Directories.Current_Directory & "/bin/quality-manager"
          else Ada.Directories.Current_Directory & "/../bin/quality-manager"));
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
      "ada_quality_summary = """ & Fixture_Path & """" & ASCII.LF &
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
     (Run (Args ("--config", Config_Path, "reconcile-assessment", "not-an-operation", "2"), 1));
   Output := To_Unbounded_String
     (Run (Args ("--config", Config_Path, "approve", "/tmp/no-such-decision.json"), 1));
   Output := To_Unbounded_String
     (Run (Args ("--config", "/tmp/no-such-quality-manager-config.toml", "status"), 1));
   Output := To_Unbounded_String
     (Run (Args ("--config", "/tmp/no-such-quality-manager-config.toml", "doctor"), 1));
   Output := To_Unbounded_String
     (Run (Args ("--config", "/tmp/no-such-quality-manager-config.toml", "maintenance"), 1));
   Output := To_Unbounded_String
     (Run (Args ("--config", "/tmp/no-such-quality-manager-config.toml", "daemon", "--once"), 1));
   Output := To_Unbounded_String
     (Run (Args ("--config", "/tmp/no-such-quality-manager-config.toml", "campaign-start", "missing"), 1));
   Output := To_Unbounded_String
     (Run (Args ("--config", "/tmp/no-such-quality-manager-config.toml", "approve", Approval_Path), 1));
   Write_File
     (Config_Path,
      "[coordinator]" & ASCII.LF & "database = """ & Database_Path & """" & ASCII.LF &
      "[integrations]" & ASCII.LF & "model_runner = ""/bin/false""" & ASCII.LF);
   Output := To_Unbounded_String (Run (Args ("--config", Config_Path, "doctor"), 1));
   Write_File
     (Config_Path,
      "[coordinator]" & ASCII.LF &
      "database = ""/tmp/no-such-quality-manager-status.db""" & ASCII.LF);
   Output := To_Unbounded_String (Run (Args ("--config", Config_Path, "status"), 1));
   Output := To_Unbounded_String (Run (Args ("unknown-command"), 1));
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_CLI_Executable;

