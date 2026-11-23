separate (Quality_Manager_Test_Suite)
procedure Test_JSON_CLI_Contracts (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Args : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
   Env  : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
   Response : Quality_Manager.Integrations.JSON_CLI.Response;

   procedure Run
     (Exit_Code : String; JSON : String;
      Contract : Quality_Manager.Integrations.JSON_CLI.Exit_Contract;
      Version : Positive := 1;
      Limit : Positive := 4_096) is
   begin
      Args.Clear;
      Args.Append (To_Unbounded_String (Exit_Code));
      Args.Append (To_Unbounded_String (JSON));
      Quality_Manager.Integrations.JSON_CLI.Execute
        ("./bin/qm_adapter_fixture", Args, "", Env, Contract, Version, 10, Limit, Response);
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
   Run
     ("0", "{""schema_version"":1,""padding"":""0123456789""}",
      Quality_Manager.Integrations.JSON_CLI.Ada_Quality_Contract, Limit => 8);
   Assert (Response.Status.Kind = Quality_Manager.Results.Execution_Error, "bounded JSON output is enforced");

   declare
      Adapter : Quality_Manager.Integrations.Improve.Adapter;
   begin
      Quality_Manager.Integrations.Improve.Initialize
        (Adapter, "./bin/qm_adapter_fixture", "config.toml", "quality.db", "improve.db");
      Quality_Manager.Integrations.Improve.Approve_Exact_Revision
        (Adapter, "PLAN-001", 1, "content-digest", Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "autonomous approval uses Improve's atomic exact-revision contract");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Response.Document),
            "plan approve PLAN-001 --revision 1 --content-sha256 content-digest") > 0,
         "autonomous approval uses Improve's atomic exact-revision contract");
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
Assert (Identity_Result.Kind = Quality_Manager.Results.Success,
         "Ada Quality durable database identity is validated and retained");
      Assert (To_String (Database_Identity) = "123e4567-e89b-12d3-a456-426614174000",
         "Ada Quality durable database identity is validated and retained");
      Quality_Manager.Integrations.Quality.Initialize
        (Quality_Adapter, "./bin/qm_adapter_fixture", "missing-identity.db");
      Quality_Manager.Integrations.Quality.Resolve_Database_Identity
        (Quality_Adapter, Database_Identity, Identity_Result);
Assert (Identity_Result.Kind = Quality_Manager.Results.Incompatible_Contract,
         "missing Ada Quality database identity fails closed");
      Assert (Length (Database_Identity) = 0,
         "missing Ada Quality database identity fails closed");
      Quality_Manager.Integrations.Quality.Initialize
        (Quality_Adapter, "./bin/qm_adapter_fixture", "invalid-identity.db");
      Quality_Manager.Integrations.Quality.Resolve_Database_Identity
        (Quality_Adapter, Database_Identity, Identity_Result);
Assert (Identity_Result.Kind = Quality_Manager.Results.Incompatible_Contract,
         "noncanonical Ada Quality database identity fails closed");
      Assert (Length (Database_Identity) = 0,
         "noncanonical Ada Quality database identity fails closed");
      Quality_Manager.Integrations.Quality.Initialize
        (Quality_Adapter, "./bin/qm_adapter_fixture", "quality.db");
      Quality_Manager.Integrations.Quality.List_Projects (Quality_Adapter, Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Ada Quality project inventory requires project-list-v1");
      Assert (Ada.Strings.Fixed.Index (To_String (Response.Document), """projects""") > 0,
         "Ada Quality project inventory requires project-list-v1");
      Quality_Manager.Integrations.Quality.Plan_Check
        (Quality_Adapter, "7", "ci", False, Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Ada Quality planning requires check-plan-v1");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Response.Document), """source_fingerprint"":""candidate-source""") > 0,
         "Ada Quality planning requires check-plan-v1");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Response.Document), """policy_fingerprint"":""policy""") > 0,
         "Ada Quality planning requires check-plan-v1");
      Quality_Manager.Integrations.Quality.Read_Assessment (Quality_Adapter, 4, Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Ada Quality assessment command is exact and versioned");
      Assert (Ada.Strings.Fixed.Index (To_String (Response.Document), "assessment show 4 --json") > 0,
         "Ada Quality assessment command is exact and versioned");
      Quality_Manager.Integrations.Quality.Compare (Quality_Adapter, 1, 2, Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Ada Quality comparison preserves both selected assessments");
      Assert (Ada.Strings.Fixed.Index (To_String (Response.Document), """baseline_id"":1") > 0,
         "Ada Quality comparison preserves both selected assessments");
      Assert (Ada.Strings.Fixed.Index (To_String (Response.Document), """current_id"":2") > 0,
         "Ada Quality comparison preserves both selected assessments");
      Quality_Manager.Integrations.Quality.Check_Environment (Quality_Adapter, "7", Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Ada Quality doctor requires doctor-report-v1");
      Assert (Ada.Strings.Fixed.Index (To_String (Response.Document), "doctor --project 7 --json") > 0,
         "Ada Quality doctor requires doctor-report-v1");

      Quality_Manager.Integrations.Summary.Initialize
        (Summary_Adapter, "./bin/qm_adapter_fixture", "quality.db");
      Quality_Manager.Integrations.Summary.Read_Problems (Summary_Adapter, Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Summary problems command is versioned JSON");
      Assert (Ada.Strings.Fixed.Index (To_String (Response.Document), "problems") > 0,
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
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Improve exact-revision command uses schema version 2");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Response.Document), "plan show PLAN-001 --revision 2") > 0,
         "Improve exact-revision command uses schema version 2");
      Quality_Manager.Integrations.Improve.Generate_Plan (Improve_Adapter, "7", 4, Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Improve planning binds the exact assessment run");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Response.Document), "plan --project 7 --run 4") > 0,
         "Improve planning binds the exact assessment run");
      Quality_Manager.Integrations.Improve.Inspect_Approval
        (Improve_Adapter, "PLAN-001", 2, Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Success, "Improve approval inspection is exposed");
      Quality_Manager.Integrations.Improve.Approve_Exact_Revision
        (Improve_Adapter, "PLAN-001", 2, "content-digest", Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "autonomous approval invokes the atomic exact revision contract");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Response.Document),
            "plan approve PLAN-001 --revision 2 --content-sha256 content-digest") > 0,
         "autonomous approval invokes the atomic exact revision contract");
      Quality_Manager.Integrations.Improve.Preflight_Publication
        (Improve_Adapter, "PLAN-001", 2, "IMP-001", Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Improve preflight binds the exact plan revision");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Response.Document), "apply PLAN-001 --revision 2 --task IMP-001 --dry-run") > 0,
         "Improve preflight binds the exact plan revision");
      Quality_Manager.Integrations.Improve.Publish_Task
        (Improve_Adapter, "PLAN-001", 2, "IMP-001", Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Improve publication binds the exact plan revision");
      Assert (Ada.Strings.Fixed.Index
           (To_String (Response.Document), "apply PLAN-001 --revision 2 --task IMP-001") > 0,
         "Improve publication binds the exact plan revision");
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
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "Improve project verification binds plan revision and assessment");
      Assert (Ada.Strings.Fixed.Index
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
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
            "native execution binds the durable operation and is noninteractive");
         Assert (Ada.Strings.Fixed.Index
              (To_String (Response.Document), "--operation-id qm-execution-1") > 0,
            "native execution binds the durable operation and is noninteractive");
         Assert (Ada.Strings.Fixed.Index
              (To_String (Response.Document), "--noninteractive") > 0,
            "native execution binds the durable operation and is noninteractive");
         Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Checked);
Assert (Checked.Kind = Quality_Manager.Results.Success,
            "native state is explicitly normalized");
         Assert (Snapshot.State =
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
      Quality_Manager.Integrations.Runner.Status
        (Runner_Adapter, "/project", "error-not-ready", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Not_Ready,
              "native readiness errors are normalized");
      Quality_Manager.Integrations.Runner.Status
        (Runner_Adapter, "/project", "error-temporary", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Temporarily_Unavailable,
              "native transient errors are normalized");
      Quality_Manager.Integrations.Runner.Status
        (Runner_Adapter, "/project", "error-stale", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Stale_Evidence,
              "native stale-evidence errors are normalized");
      Quality_Manager.Integrations.Runner.Status
        (Runner_Adapter, "/project", "error-integrity", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Integrity_Error,
              "native integrity errors are normalized");
      Quality_Manager.Integrations.Runner.Status
        (Runner_Adapter, "/project", "error-authorization", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Authorization_Required,
              "native authorization errors are normalized");
      Quality_Manager.Integrations.Runner.Status
        (Runner_Adapter, "/project", "error-negative", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Negative_Result,
              "native negative outcomes are normalized");
      Quality_Manager.Integrations.Runner.Status
        (Runner_Adapter, "/project", "invalid-error-json", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Invalid_Request,
              "malformed native error details do not override the process classification");
      Quality_Manager.Integrations.Runner.Status
        (Runner_Adapter, "/project", "incomplete-error", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Invalid_Request,
              "incomplete native error details do not override the process classification");
      Quality_Manager.Integrations.Runner.Cancel
        (Runner_Adapter, "/project", "qm-execution-1", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Success, "native cancellation is exposed");
      Quality_Manager.Integrations.Runner.Recover (Runner_Adapter, "/project", Response);
      Assert (Response.Status.Kind = Quality_Manager.Results.Success, "native recovery is exposed");
      Quality_Manager.Integrations.Runner.Integrate
        (Runner_Adapter, "/project", "qm-execution-1", Response);
Assert (Response.Status.Kind = Quality_Manager.Results.Success,
         "integration is restricted to the conflict-free native gate");
      Assert (Ada.Strings.Fixed.Index
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

