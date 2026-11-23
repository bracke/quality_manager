separate (Quality_Manager_Test_Suite)
procedure Test_Campaign_Workflow (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path    : constant String := "/tmp/quality-manager-campaign.database";
   Store   : aliased Quality_Manager.Storage.Store;
   Context : Quality_Manager.Campaigns.Context;
   Summary : Quality_Manager.Integrations.Summary.Adapter;
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
      Baseline_Assessment_Run => 0,
      Improve_Plan_Id => Null_Unbounded_String, Improve_Revision => 0,
      Improve_Task_Id => Null_Unbounded_String, Improve_Content_SHA256 => Null_Unbounded_String,
      Planned_Source_Fingerprint => Null_Unbounded_String,
      Effective_Policy_Digest => Null_Unbounded_String,
      State => Quality_Manager.Model.Planning,
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
   Quality_Manager.Storage.Records.Save
     (Store,
      Quality_Manager.Storage.Schema.Campaign'
        (Campaign_Id => To_Unbounded_String ("empty-targets"),
         Definition_Revision => 1, Definition_Digest => To_Unbounded_String ("digest"),
         Scope => To_Unbounded_String ("scope"), Baseline => To_Unbounded_String ("baseline"),
         State => Quality_Manager.Model.Queued, Budget => 1, Used => 0), Result);
   Quality_Manager.Campaigns.Reconcile (Context, "empty-targets", Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Integrity_Error,
      "campaign reconciliation rejects a durable campaign without current targets");
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
   Quality_Manager.Campaigns.Reconcile (Context, "budgeted", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "exhausted unsatisfied campaign reconciles as blocked");
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
   Quality_Manager.Campaigns.Reconcile (Context, "applicability", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "partially evaluated campaign remains queued");
   Quality_Manager.Campaigns.Update_Target
     (Context, "applicability", 7, "TST-03", 3, "not-applicable", True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success,
           "justified allowed not-applicable evidence satisfies its target");

   Write_Text (Definition ("summary-reconcile", 1, 2));
   Quality_Manager.Campaigns.Create (Context, Base_Path, Result);
   Quality_Manager.Campaigns.Start (Context, "summary-reconcile", Result);
   Quality_Manager.Integrations.Summary.Initialize
     (Summary, "./bin/qm_adapter_fixture", "quality.db");
   Quality_Manager.Campaigns.Reconcile (Context, Summary, "summary-reconcile", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success,
           "campaign reconciliation adopts current versioned Summary evidence");
   Quality_Manager.Storage.Read (Store, "campaign:summary-reconcile", Loaded, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then To_String (Loaded.State) = Quality_Manager.Model.Work_State'Image
        (Quality_Manager.Model.Verified),
      "current passing Summary evidence completes every frozen campaign target");

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
         & Original_Directory & "/bin/qm_adapter_fixture""" & ASCII.LF
         & "ada_quality_summary = """
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
      when others =>  --  AQ: audited exception boundary
         Quality_Manager.Storage.Close (Wrapper_Store, Wrapper_Result);
         Cleanup_Wrappers;
         raise;
   end;
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Campaign_Workflow;

