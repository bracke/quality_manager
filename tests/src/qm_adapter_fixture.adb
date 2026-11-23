with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Hostkit.Process;
with Quality_Manager.Identities;
with Quality_Manager.Results;
with Quality_Manager.Storage;

procedure QM_Adapter_Fixture is
   use type Quality_Manager.Results.Result_Kind;

   Status : Integer := 0;
   Numeric_Mode : Boolean := False;
   Integrated_Marker : constant String := "/tmp/qm-adapter-project-integrated";
   Retry_Marker : constant String := "/tmp/qm-adapter-retry-three";

   function Option_Value (Text, Name : String) return String is
      Marker : constant String := "--" & Name & " ";
      First  : Natural := Ada.Strings.Fixed.Index (Text, Marker);
      Last   : Natural;
   begin
      if First = 0 then
         return "";
      end if;
      First := First + Marker'Length;
      Last := First;
      while Last <= Text'Last and then Text (Last) /= ' ' loop
         Last := Last + 1;
      end loop;
      return Text (First .. Last - 1);
   end Option_Value;
   procedure Run_Crash_Fixture is
      Store  : Quality_Manager.Storage.Store;
      Result : Quality_Manager.Results.Operation_Result;
   begin
      if Ada.Command_Line.Argument_Count /= 2
        or else Ada.Command_Line.Argument (1) /= "coordinator-crash"
      then
         return;
      end if;
      Quality_Manager.Storage.Open
        (Store, Ada.Command_Line.Argument (2), True, Result);
      if Result.Kind /= Quality_Manager.Results.Success then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (70));
         return;
      end if;
      Quality_Manager.Storage.Prepare_Operation
        (Store, Quality_Manager.Identities.Operation_Id (9_999),
         "crash-test", "persist before abrupt termination", "fixture:crash", Result);
      if Result.Kind /= Quality_Manager.Results.Success then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (71));
         return;
      end if;
      Hostkit.Process.End_Now (77);
   end Run_Crash_Fixture;

   procedure Read_Numeric_Mode is
   begin
      if Ada.Command_Line.Argument_Count = 0 then
         return;
      end if;
      begin
         Status := Integer'Value (Ada.Command_Line.Argument (1));
         Numeric_Mode := True;
      exception
         when Constraint_Error =>
            Numeric_Mode := False;
      end;
   end Read_Numeric_Mode;

   procedure Run_Numeric_Output is
   begin
      if Ada.Command_Line.Argument_Count < 2 then
         return;
      elsif Ada.Command_Line.Argument (2) = "invalid-utf8" then
         Ada.Text_IO.Put (Character'Val (16#C3#) & Character'Val (16#28#));
      else
         Ada.Text_IO.Put (Ada.Command_Line.Argument (2));
      end if;
   end Run_Numeric_Output;

   procedure Run_Structured is
      Invocation : Unbounded_String;
      Command     : Unbounded_String;
      Kind        : Unbounded_String;
      Database_Path : Unbounded_String;
      Has_State  : Boolean := False;
      Is_Database_Statistics : Boolean := False;
      Index      : Positive := 1;
      procedure Handle_Projects
        (Text : String; Done : out Boolean) is
         function Selected_Project_Id return String is
           (if Text = "project 8" then "8" else "7");

         function Selected_Project_Path return String is
           (if Ada.Strings.Fixed.Index (To_String (Database_Path), "release-remediation") > 0
            then Ada.Directories.Current_Directory
            elsif Text = "project 8" then "/second" else "/project");

         function Planned_Project_Id return String is
           (if Ada.Strings.Fixed.Index (Text, "--project 9") > 0 then "9" else "7");

         function Planned_Project_Path return String is
           (if Ada.Strings.Fixed.Index (To_String (Database_Path), "release-remediation") > 0
            then Ada.Directories.Current_Directory
            elsif Ada.Strings.Fixed.Index (Text, "--project 9") > 0 then "/second" else "/project");

         function Planned_Source return String is
           (if Ada.Directories.Exists (Integrated_Marker)
            then "integrated-source"
            else "candidate-source");

         function Comparison_Baseline return String is
           (if Ada.Directories.Exists (Integrated_Marker) then "2"
            elsif Ada.Strings.Fixed.Index (Text, "assessment diff 3 2") = 1 then "3"
            else "1");

         function Comparison_Current return String is
           (if Ada.Directories.Exists (Integrated_Marker) then "4" else "2");

         function Comparison_Changes return String is
           (if Ada.Strings.Fixed.Index (Text, "assessment diff 3 2") = 1
            then "[{""indicator"":""TST-03"",""change"":""new-violation""," &
              """before"":""pass"",""after"":""violation""}]"
            else "[]");

         procedure Put_Project_List is
         begin
            if Ada.Strings.Fixed.Index (To_String (Database_Path), "inventory-invalid") > 0 then
               Ada.Text_IO.Put ("{");
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "inventory-schema") > 0 then
               Ada.Text_IO.Put ("{""schema_version"":2,""kind"":""project-list"",""projects"":[]}");
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "inventory-project") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""project-list"",""projects"":[" &
                  "{""id"":7,""enabled"":true,""removed"":false}]}");
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "release-remediation") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""project-list"",""projects"":[" &
                  "{""id"":7,""path"":""" & Ada.Directories.Current_Directory &
                  """,""enabled"":true,""removed"":false}]}");
            else
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""project-list"",""projects"":[" &
                  "{""id"":7,""path"":""/project"",""enabled"":true,""removed"":false}," &
                  "{""id"":8,""path"":""/disabled"",""enabled"":false,""removed"":false}," &
                  "{""id"":9,""path"":""/second"",""enabled"":true,""removed"":false}]}");
            end if;
         end Put_Project_List;
      begin
         Done := False;
         if Text in "project 7" | "project 8" then
            Ada.Text_IO.Put
              ("{""schema_version"":1,""report_type"":""project"",""source"":{" &
               """application"":""ada_quality"",""database_schema_version"":6," &
               """snapshot"":""fixture""},""selection"":{""project_id"":" &
               Selected_Project_Id & "},""data"":{""project"":{" &
               """project_id"":" & Selected_Project_Id & "," &
               """path"":""" & Selected_Project_Path &
               """,""current_run_id"":2},""assessment"":{""run_id"":2}," &
               """indicators"":[{""id"":""TST-03"",""compliance"":""pass""," &
               """applicable"":true,""evidence"":""fixture evidence""}]}}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "project list") = 1 then
            Put_Project_List;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "project ") = 1 then
            Kind := To_Unbounded_String ("project-list");
         elsif Ada.Strings.Fixed.Index (Text, "check ") = 1
           and then Ada.Strings.Fixed.Index (Text, "--dry-run") > 0
         then
            if Ada.Strings.Fixed.Index (To_String (Database_Path), "plan-invalid") > 0 then
               Ada.Text_IO.Put ("{");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            end if;
            Ada.Text_IO.Put
              ("{""schema_version"":1,""kind"":""check-plan"",""projects"":[{" &
               """project_id"":" & Planned_Project_Id &
               ",""path"":""" & Planned_Project_Path &
               """," &
               """source_fingerprint"":""" & Planned_Source & """," &
               """policy_fingerprint"":""policy""," &
               """toolchain_fingerprint"":""toolchain""," &
               """reuse_eligible"":false,""action"":""assess""}]}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "assessment diff ") = 1 then
            Ada.Text_IO.Put
              ("{""schema_version"":1,""kind"":""assessment-comparison""," &
               """project_id"":7,""status"":""comparison-available""," &
               """baseline_id"":" & Comparison_Baseline &
               ",""current_id"":" & Comparison_Current &
               ",""policy_changed"":false,""changes"":" & Comparison_Changes & "}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;

         end if;
      end Handle_Projects;

      procedure Handle_Plan
        (Text : String; Done : out Boolean) is
      begin
         Done := False;
         if Ada.Strings.Fixed.Index (Text, "plan --project 7 --run 2") = 1
           or else Text = "plan show PLAN-001 --revision 1"
         then
            if Ada.Strings.Fixed.Index (To_String (Database_Path), "planning-invalid-json") > 0 then
               Ada.Text_IO.Put ("{");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "planning-empty-tasks") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""plan"",""data"":{" &
                  """plan_id"":""PLAN-001"",""revision"":1,""project_id"":7,""run_id"":2," &
                  """working_source_fingerprint"":""candidate-source""," &
                  """fingerprint"":""plan-fingerprint"",""content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """dry_run"":false,""stored"":true,""tasks"":[]}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "planning-bad-task") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""plan"",""data"":{" &
                  """plan_id"":""PLAN-001"",""revision"":1,""project_id"":7,""run_id"":2," &
                  """working_source_fingerprint"":""candidate-source""," &
                  """fingerprint"":""plan-fingerprint"",""content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """dry_run"":false,""stored"":true,""tasks"":[1]}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "planning-empty-findings") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""plan"",""data"":{" &
                  """plan_id"":""PLAN-001"",""revision"":1,""project_id"":7,""run_id"":2," &
                  """working_source_fingerprint"":""candidate-source""," &
                  """fingerprint"":""plan-fingerprint"",""content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """dry_run"":false,""stored"":true,""tasks"":[{""id"":""IMP-001"",""findings"":[]}]}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "planning-duplicate-finding") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""plan"",""data"":{" &
                  """plan_id"":""PLAN-001"",""revision"":1,""project_id"":7,""run_id"":2," &
                  """working_source_fingerprint"":""candidate-source""," &
                  """fingerprint"":""plan-fingerprint"",""content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """dry_run"":false,""stored"":true,""tasks"":[{" &
                  """id"":""IMP-001"",""findings"":[""finding-a"",""finding-a""]}]}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            end if;
            Ada.Text_IO.Put
              ("{""schema_version"":2,""command"":""plan"",""data"":{" &
               """plan_id"":""PLAN-001"",""revision"":1,""project_id"":7," &
               """project"":""fixture"",""run_id"":2," &
               """assessment_fingerprint"":""assessment-2""," &
               """working_source_fingerprint"":""candidate-source""," &
               """fingerprint"":""plan-fingerprint""," &
               """content_sha256"":""plan-content-sha256-v2:" &
               "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
               """planner"":""deterministic""," &
               """agent_provider"":"""",""agent_model_sha256"":""""," &
               """dry_run"":false,""stored"":true,""tasks"":[{" &
               """id"":""IMP-001"",""title"":""Fix fixture violation""," &
               """category"":""correctness"",""priority"":""high""," &
               """candidate_kind"":""remediation"",""goal"":""pass""," &
               """problem"":""fixture violation"",""evidence"":""assessment 2""," &
               """scope"":""src"",""out_of_scope"":""api""," &
               """requirements"":""preserve behavior"",""acceptance"":""pass""," &
               """verification"":""reassess"",""confidence"":100," &
               """requires_review"":true,""files"":[]," &
               """findings"":[""finding-b"",""finding-a""],""depends_on"":[]}]}}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;

         end if;
      end Handle_Plan;

      procedure Handle_Approval
        (Text : String; Done : out Boolean) is
      begin
         Done := False;
         if Ada.Strings.Fixed.Index (Text, "plan approve ") = 1 then
            Ada.Text_IO.Put
              ("{""schema_version"":" &
               (if Ada.Strings.Fixed.Index (To_String (Database_Path), "approval-natural-type") > 0
                then """2"""
                elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "approval-natural-range") > 0
                then "-1"
                else "2") &
               ",""command"":" &
               (if Ada.Strings.Fixed.Index (To_String (Database_Path), "approval-string-type") > 0
                then "1" else """plan approve""") &
               ",""data"":{" &
               """plan_id"":""PLAN-001"",""revision"":1," &
               """content_sha256"":""plan-content-sha256-v2:" &
               "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
               """approved"":" &
               (if Ada.Strings.Fixed.Index (To_String (Database_Path), "approval-boolean-type") > 0
                then """true"""
                elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "approval-mismatch") > 0
                then "false" else "true") &
               ",""invocation"":""" & To_String (Invocation) & """}}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;

         end if;
      end Handle_Approval;

      procedure Handle_Publication
        (Text : String; Done : out Boolean) is
      begin
         Done := False;
         if Ada.Strings.Fixed.Index (Text, "apply PLAN-001 ") = 1
           and then Ada.Strings.Fixed.Index (Text, "--task IMP-001") > 0
         then
            if Ada.Strings.Fixed.Index (To_String (Database_Path), "publication-identity") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""apply"",""data"":{" &
                  """plan_id"":""OTHER"",""revision"":1,""content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """dry_run"":true,""tasks"":[]}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "publication-empty") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""apply"",""data"":{" &
                  """plan_id"":""PLAN-001"",""revision"":1,""content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """dry_run"":true,""tasks"":[]}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "publication-bad-mapping") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""apply"",""data"":{" &
                  """plan_id"":""PLAN-001"",""revision"":1,""content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """dry_run"":true,""tasks"":[1]}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            elsif Ada.Strings.Fixed.Index (To_String (Database_Path), "publication-no-match") > 0 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""apply"",""data"":{" &
                  """plan_id"":""PLAN-001"",""revision"":1,""content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """dry_run"":true,""tasks"":[{""improve_task_id"":""OTHER""," &
                  """harness_task_id"":""TASK-OTHER""}]}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            end if;
            Ada.Text_IO.Put
              ("{""schema_version"":2,""command"":""apply"",""data"":{" &
               """plan_id"":""PLAN-001"",""revision"":1," &
               """content_sha256"":""plan-content-sha256-v2:" &
               "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
               """task_kind"":""remediation""," &
               """dry_run"":" &
               (if Ada.Strings.Fixed.Index (Text, "--dry-run") > 0 then "true" else "false") &
               ",""tasks"":[{""improve_task_id"":""IMP-001""," &
               """harness_task_id"":""TASK-001"",""origin"":""fixture-origin""," &
               """state"":""ready"",""core_state"":""ready"",""recovered"":false}]," &
               """invocation"":""" & To_String (Invocation) & """}}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;

         end if;
      end Handle_Publication;

      procedure Handle_Commands
        (Text : String; Done : out Boolean) is
      begin
         Done := False;
         if Ada.Strings.Fixed.Index (Text, "doctor ") = 1 then
            Kind := To_Unbounded_String ("doctor-report");
         elsif Text = "database stats" then
            Kind := To_Unbounded_String ("database-statistics");
            Is_Database_Statistics := True;
         elsif Text = "rev-parse HEAD" then
            Ada.Text_IO.Put
              (if Ada.Directories.Exists (Integrated_Marker)
               then "fixture-commit-remediated" else "fixture-commit");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Text = "status --porcelain --untracked-files=no" then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Text = "build --validation -- -f" then
            Ada.Directories.Create_Path (Ada.Directories.Current_Directory & "/bin");
            declare
               Artifact : Ada.Text_IO.File_Type;
            begin
               Ada.Text_IO.Create
                 (Artifact, Ada.Text_IO.Out_File,
                  Ada.Directories.Current_Directory & "/bin/release-fixture-artifact");
               Ada.Text_IO.Put
                 (Artifact,
                  (if Ada.Directories.Exists
                     (Ada.Directories.Current_Directory & "/qm_nondeterministic.fixture")
                   then Ada.Directories.Current_Directory else "deterministic-artifact"));
               Ada.Text_IO.Close (Artifact);
            end;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Text = "test" then
            if Ada.Directories.Exists
              (Ada.Directories.Current_Directory & "/qm_mutate_source.fixture")
            then
               declare
                  Mutation : Ada.Text_IO.File_Type;
               begin
                  Ada.Text_IO.Create
                    (Mutation, Ada.Text_IO.Out_File,
                     Ada.Directories.Current_Directory & "/src/quality_manager-review-mutation.adb");
                  Ada.Text_IO.Put_Line (Mutation, "procedure Quality_Manager.Review_Mutation is null;");
                  Ada.Text_IO.Close (Mutation);
               end;
            end if;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "exec -- gnatprove ") = 1 then
            if Ada.Directories.Exists
              (Ada.Directories.Current_Directory & "/qm_proof_empty.fixture")
            then
               Ada.Directories.Create_Path
                 (Ada.Directories.Current_Directory & "/obj/gnatprove");
               declare
                  Report : Ada.Text_IO.File_Type;
               begin
                  Ada.Text_IO.Create
                    (Report, Ada.Text_IO.Out_File,
                     Ada.Directories.Current_Directory & "/obj/gnatprove/gnatprove.out");
                  Ada.Text_IO.Close (Report);
               end;
            elsif not Ada.Directories.Exists
              (Ada.Directories.Current_Directory & "/qm_proof_invalid.fixture")
            then
               Ada.Directories.Create_Path
                 (Ada.Directories.Current_Directory & "/obj/gnatprove");
               declare
                  Report : Ada.Text_IO.File_Type;
               begin
                  Ada.Text_IO.Create
                    (Report, Ada.Text_IO.Out_File,
                     Ada.Directories.Current_Directory & "/obj/gnatprove/gnatprove.out");
                  Ada.Text_IO.Put_Line (Report, "Summary of SPARK analysis");
                  Ada.Text_IO.Put_Line (Report, "Analyzed 1 unit");
                  Ada.Text_IO.Put_Line (Report, "fixture and proved (1 check)");
                  Ada.Text_IO.Close (Report);
               end;
            end if;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Text = "work capabilities" then
            Ada.Text_IO.Put
              ("{""schema_version"":1,""kind"":""work-capabilities""," &
               """noninteractive"":true,""idempotent_operations"":true," &
               """operation_lookup"":true,""workspace_isolation"":true," &
               """semantic_conflict_resolution"":false,""commands"":" &
               "[""inspect"",""execute"",""status"",""cancel"",""recover"",""integrate""]}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "work cancel ") = 1 then
            Ada.Text_IO.Put
              ("{""schema_version"":1,""kind"":""work-cancellation""," &
               """operation_id"":""qm-execution-1"",""task_id"":""TASK-001""," &
               """result"":""requested""}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "work recover ") = 1 then
            Ada.Text_IO.Put
              ("{""schema_version"":1,""kind"":""work-recovery""," &
               """project_identity"":""project-identity"",""result"":""reconciled""}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;

         end if;
      end Handle_Commands;

      procedure Handle_Status_Errors
        (Text : String; Done : out Boolean) is
      begin
         Done := False;
         if Ada.Strings.Fixed.Index (Text, "work status ") = 1
           and then Ada.Strings.Fixed.Index (Text, "missing-operation") > 0
         then
            Ada.Text_IO.Put
              ("{""schema_version"":1,""kind"":""error""," &
               """error_code"":""MR-FRAMEWORK-0011"",""diagnostic"":""missing-operation""}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (2));
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "work status ") = 1
           and then Ada.Strings.Fixed.Index (Text, "invalid-error-json") > 0
         then
            Ada.Text_IO.Put ("{");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (2));
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "work status ") = 1
           and then Ada.Strings.Fixed.Index (Text, "incomplete-error") > 0
         then
            Ada.Text_IO.Put ("{""schema_version"":1,""kind"":""error""}");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (2));
            Done := True; return;
         elsif Ada.Strings.Fixed.Index (Text, "work status ") = 1
           and then Ada.Strings.Fixed.Index (Text, "error-") > 0
         then
            declare
               Code : constant String :=
                 (if Ada.Strings.Fixed.Index (Text, "error-not-ready") > 0
                  then "MR-FRAMEWORK-0009"
                  elsif Ada.Strings.Fixed.Index (Text, "error-temporary") > 0
                  then "MR-FRAMEWORK-0010"
                  elsif Ada.Strings.Fixed.Index (Text, "error-stale") > 0
                  then "MR-FRAMEWORK-0012"
                  elsif Ada.Strings.Fixed.Index (Text, "error-integrity") > 0
                  then "MR-FRAMEWORK-0013"
                  elsif Ada.Strings.Fixed.Index (Text, "error-authorization") > 0
                  then "MR-FRAMEWORK-0027"
                  else "MR-FRAMEWORK-0033");
            begin
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""error""," &
                  """error_code"":""" & Code & """,""diagnostic"":""forced error""}");
            end;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (2));
            Done := True; return;

         end if;
      end Handle_Status_Errors;

      procedure Handle_Work
        (Text : String; Done : out Boolean) is
         function Both (Left, Right : Boolean) return Boolean is
           (Left and then Right);

         function Is_Work_Command return Boolean is
           (Ada.Strings.Fixed.Index (Text, "work inspect ") = 1
            or else Ada.Strings.Fixed.Index (Text, "work execute ") = 1
            or else Ada.Strings.Fixed.Index (Text, "work status ") = 1
            or else Ada.Strings.Fixed.Index (Text, "work integrate ") = 1);

         function Retry_Attempt (Operation : String; Record_New : Boolean) return Natural is
            File  : Ada.Text_IO.File_Type;
            Count : Natural := 0;
         begin
            if Ada.Directories.Exists (Retry_Marker) then
               Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Retry_Marker);
               while not Ada.Text_IO.End_Of_File (File) loop
                  declare
                     Line : constant String := Ada.Text_IO.Get_Line (File);
                  begin
                     Count := Count + 1;
                     if Line = Operation then
                        Ada.Text_IO.Close (File);
                        return Count;
                     end if;
                  end;
               end loop;
               Ada.Text_IO.Close (File);
            end if;
            if not Record_New then
               return 0;
            elsif Ada.Directories.Exists (Retry_Marker) then
               Ada.Text_IO.Open (File, Ada.Text_IO.Append_File, Retry_Marker);
            else
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Retry_Marker);
            end if;
            Ada.Text_IO.Put_Line (File, Operation);
            Ada.Text_IO.Close (File);
            return Count + 1;
         end Retry_Attempt;

         function Operation_Value return String is
           (if Option_Value (Text, "operation-id") /= ""
            then Option_Value (Text, "operation-id")
            else "inspect-operation");
      begin
         Done := False;
         if Is_Work_Command then
            declare
               Operation : constant String := Operation_Value;
               Is_Execute : constant Boolean := Ada.Strings.Fixed.Index (Text, "work execute ") = 1;
               Is_Integrate : constant Boolean := Ada.Strings.Fixed.Index (Text, "work integrate ") = 1;
               Is_Inspect : constant Boolean := Ada.Strings.Fixed.Index (Text, "work inspect ") = 1;
               Project_Path : constant String := Option_Value (Text, "project");
               Forced_Cancelled : constant Boolean := Both (Project_Path = "/cancelled", Is_Execute);
               Forced_Failed : constant Boolean := Both (Project_Path = "/failed", Is_Execute);
               Retry_Number : constant Natural :=
                 (if Project_Path = "/retry-three" and then not Is_Inspect
                  then Retry_Attempt (Operation, Is_Execute) else 0);
               Retry_Failed : constant Boolean := Retry_Number in 1 .. 2;
               Forced_Integrated : constant Boolean := Both (Project_Path = "/integrated", Is_Execute);
               Forced_Invalid : constant Boolean := Both (Project_Path = "/invalid-state", Is_Execute);
               Forced_Blocked : constant Boolean := Both (Project_Path = "/blocked", Is_Inspect);
               Known_Operation : constant Boolean :=
                 Operation in "qm-execution-1" | "qm-execution-2" |
                              "qm-execution-3" | "qm-execution-4" |
                              "qm-execution-5" | "qm-execution-6" |
                              "qm-execution-7" | "qm-execution-8" |
                              "qm-execution-9";
               Persisted_Integrated : constant Boolean :=
                 Both (not Known_Operation, Ada.Directories.Exists (Integrated_Marker));
               Running : constant Boolean :=
                 Both
                   (Operation in "qm-execution-2" | "qm-execution-6" | "qm-execution-7",
                    Is_Execute);
               Incompatible : constant Boolean := Operation = "qm-execution-3";
               Cancelled : constant Boolean := Operation = "qm-execution-4";
               Failed : constant Boolean := Operation = "qm-execution-5";
               Pending_Integration : constant Boolean :=
                 Both (Operation = "qm-execution-8", Is_Integrate);

               function Audit_Value return String is
                 (if Is_Execute then "execute-audit" else "status-audit");

               function Identity_Value return String is
                 (if Project_Path = "/missing-identity" then ""
                  elsif Project_Path = "/integration-project-drift" then "other-project"
                  else "project-identity");

               function Task_Revision_Value return String is
                 (if Project_Path = "/missing-identity" then ""
                  elsif Project_Path = "/integration-revision-drift" then "other-revision"
                  else "task-revision");

               function Result_Operation return String is
                 (if Project_Path = "/integration-operation-drift"
                  then "qm-execution-999" else Operation);

               function Result_Task return String is
                 (if Project_Path = "/integration-task-drift" then "TASK-OTHER" else "TASK-001");

               function Ready_Value return String is
                 (if Both (Is_Inspect, not Forced_Blocked) then "true" else "false");

               function Workspace_Id_Value return String is
                 (if Is_Integrate or else Persisted_Integrated then "" else "workspace-1");

               function Source_Value return String is
               begin
                  if Is_Integrate and then not Pending_Integration then
                     return "integrated-source";
                  elsif Persisted_Integrated then
                     return "integrated-source";
                  elsif Is_Inspect then
                     return "candidate-source";
                  elsif Option_Value (Text, "expected-source-fingerprint") /= "" then
                     return Option_Value (Text, "expected-source-fingerprint");
                  elsif not Known_Operation then
                     return "candidate-source";
                  else
                     return "source-fingerprint";
                  end if;
               end Source_Value;

               function Exceptional_Execution_State return String is
               begin
                  if Forced_Cancelled then
                     return "cancelled";
                  elsif Forced_Failed or else Retry_Failed then
                     return "failed";
                  elsif Forced_Integrated or else Forced_Invalid then
                     return "completed";
                  elsif Incompatible then
                     return "incompatible";
                  elsif Cancelled then
                     return "cancelled";
                  elsif Failed or else Retry_Failed then
                     return "failed";
                  elsif Running then
                     return "executing";
                  else
                     return "";
                  end if;
               end Exceptional_Execution_State;

               function Execution_State return String is
                  Exceptional : constant String := Exceptional_Execution_State;
               begin
                  if Is_Inspect then
                     return "ready";
                  elsif Exceptional /= "" then
                     return Exceptional;
                  elsif (Is_Integrate and then not Pending_Integration)
                    or else Persisted_Integrated
                  then
                     return "completed";
                  else
                     return "awaiting_integration";
                  end if;
               end Execution_State;

               function Native_State return String is
               begin
                  if Is_Inspect then
                     return "ready";
                  elsif Forced_Cancelled then
                     return "cancelled";
                  elsif Forced_Failed or else Retry_Failed then
                     return "failed";
                  elsif Running then
                     return "running";
                  elsif Failed or else Retry_Failed then
                     return "failed";
                  elsif Cancelled then
                     return "cancelled";
                  else
                     return "verification";
                  end if;
               end Native_State;

               function Core_State return String is
               begin
                  if Is_Inspect then
                     return "ready";
                  elsif Running then
                     return "running";
                  elsif Failed or else Retry_Failed then
                     return "failed";
                  elsif Cancelled then
                     return "cancelled";
                  else
                     return "verification";
                  end if;
               end Core_State;

               function Workspace_State return String is
               begin
                  if Forced_Integrated then
                     return "integrated";
                  elsif Forced_Invalid then
                     return "active";
                  elsif (Is_Integrate and then not Pending_Integration)
                    or else Persisted_Integrated
                  then
                     return "integrated";
                  else
                     return "active";
                  end if;
               end Workspace_State;
            begin
               if Both (Both (Is_Integrate, not Pending_Integration), not Known_Operation) then
                  declare
                     Marker : Ada.Text_IO.File_Type;
                  begin
                     Ada.Text_IO.Create (Marker, Ada.Text_IO.Out_File, Integrated_Marker);
                     Ada.Text_IO.Put_Line (Marker, Operation);
                     Ada.Text_IO.Close (Marker);
                  end;
               end if;
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""work-operation""," &
                  """operation_id"":""" & Result_Operation & """,""project_identity"":""" &
                  Identity_Value & """," &
                  """source_fingerprint"":""" & Source_Value &
                  """,""task_id"":""" & Result_Task & """," &
                  """task_revision"":""" & Task_Revision_Value &
                  """,""effective_task_revision"":""effective-revision""," &
                  """execution_policy"":""policy-fingerprint"",""execution_generation"":""1""," &
                  """execution_state"":""" & Execution_State &
                  """,""native_task_state"":""" & Native_State &
                  """,""core_state"":""" & Core_State &
                  """,""ready"":" & Ready_Value &
                  ",""readiness_reasons"":[]," &
                  """workspace_id"":""" & Workspace_Id_Value &
                  """,""workspace_state"":""" & Workspace_State &
                  """," &
                  """result"":""success"",""diagnostics"":[],""audit_reference"":""" &
                  Audit_Value & """," &
                  """invocation"":""" & To_String (Invocation) & """}");
            end;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;

         end if;
      end Handle_Work;

      procedure Handle_Assessment
        (Text : String; Done : out Boolean) is
         function Is_Assessment_Command return Boolean is
           (Ada.Strings.Fixed.Index (Text, "check ") = 1
            or else Text in "assessment show 2 --json" | "assessment show 3 --json");

         function Assessment_Id return String is
           (if Text = "assessment show 3 --json" then "3"
            elsif Ada.Directories.Exists (Integrated_Marker) then "4"
            else "2");

         function Project_Id return String is
           (if Ada.Strings.Fixed.Index (Text, "--project 9") > 0 then "9" else "7");

         function Project_Path return String is
           (if To_String (Database_Path) = "release-quality.db"
             or else Ada.Strings.Fixed.Index
               (To_String (Database_Path), "release-remediation") > 0
            then Ada.Directories.Current_Directory
            elsif Ada.Strings.Fixed.Index (Text, "--project 9") > 0 then "/second"
            else "/project");

         function Source_Fingerprint return String is
           (if Ada.Directories.Exists (Integrated_Marker)
            then "integrated-source"
            else "candidate-source");

         function Compliance (Position : Positive) return String is
            First : constant Boolean := Position = 1;
         begin
            if Text = "assessment show 3 --json" and then First then
               return "unknown";
            elsif Ada.Strings.Fixed.Index (Text, "--project 9") > 0 and then First then
               return "unknown";
            elsif Ada.Strings.Fixed.Index (Text, "--project 7") > 0
              and then (To_String (Database_Path) = "quality.db"
                or else Ada.Strings.Fixed.Index
                  (To_String (Database_Path), "release-remediation") > 0)
              and then First
              and then not Ada.Directories.Exists (Integrated_Marker)
            then
               return "violation";
            else
               return "pass";
            end if;
         end Compliance;

         function Indicator (Position : Positive) return String is
            Number : constant String := Ada.Strings.Fixed.Trim
              (Natural'Image (Position), Ada.Strings.Both);
         begin
            return "TST-" & (if Position < 10 then "0" else "") & Number;
         end Indicator;

         function Measurement (Position : Positive) return String is
           (if Position = 3 then "{""basis_points"":9000}" else "{}");
      begin
         Done := False;
         if Is_Assessment_Command then
            if Ada.Strings.Fixed.Index (To_String (Database_Path), "assessment-invalid") > 0 then
               Ada.Text_IO.Put ("{");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            end if;
            if Ada.Strings.Fixed.Index (Text, "--project 99") > 0 then
               Ada.Text_IO.Put ("not-json");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               Done := True; return;
            end if;
            Ada.Text_IO.Put
              ("{""schema_version"":1,""assessment_id"":" &
               Assessment_Id & ",""project_id"":" & Project_Id & "," &
               """project_path"":""" & Project_Path &
               """,""source_fingerprint"":""" & Source_Fingerprint & """," &
               """policy_fingerprint"":""policy"",""toolchain_fingerprint"":""toolchain""," &
               """status"":""ASSESSMENT_COMPLETED"",""results"":[");
            for Result_Index in 1 .. 33 loop
               if Result_Index > 1 then Ada.Text_IO.Put (","); end if;
               declare
                  Indicator_Id : constant String := Indicator (Result_Index);
               begin
               Ada.Text_IO.Put
                    ("{""indicator"":""" & Indicator_Id & """,""execution"":""succeeded""," &
                     """compliance"":""" & Compliance (Result_Index) &
                     """,""applicable"":true,""summary"":""ok""," &
                     """evidence"":""fixture"",""measurement"":" &
                     Measurement (Result_Index) &
                     ",""findings"":[]}");
               end;
            end loop;
            Ada.Text_IO.Put ("],""executions"":[]}");
            Ada.Command_Line.Set_Exit_Status
              (if Ada.Strings.Fixed.Index (Text, "--project 9") > 0
               then Ada.Command_Line.Exit_Status (3)
               else Ada.Command_Line.Success);
            Done := True; return;

         end if;
      end Handle_Assessment;

      procedure Handle_Verification
        (Text : String; Done : out Boolean) is
      begin
         Done := False;
         if Has_State
           and then Ada.Strings.Fixed.Index (Text, "verify --task IMP-") = 1
         then
            declare
               Failing : constant Boolean := Ada.Strings.Fixed.Index (Text, "IMP-FAIL") > 0;
            begin
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""verify"",""data"":{" &
                 """plan_id"":""PLAN-001"",""baseline_run"":" &
                 (if Ada.Directories.Exists (Integrated_Marker) then "2" else "1") &
                 ",""verification_run"":" &
                 (if Ada.Directories.Exists (Integrated_Marker) then "4" else "2") & "," &
                  """outcome"":""" & (if Failing then "still-failing" else "verified") &
                  """,""plan_outcome"":""" & (if Failing then "still-failing" else "verified") &
                  """,""project_outcome"":""verified"",""comparable"":true,""new_critical"":0," &
                  """explanation"":""fixture"",""tasks"":[{""task_id"":""" &
                  (if Failing then "IMP-FAIL" else "IMP-001") & """,""outcome"":""" &
                  (if Failing then "still-failing" else "verified") &
                  """,""matched"":" & (if Failing then "0" else "1") &
                  ",""total"":1,""explanation"":""fixture""}]}}");
            end;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            Done := True; return;
         end if;
      end Handle_Verification;

      procedure Dispatch (Text : String) is
         type Handler_Access is access procedure
           (Text : String; Done : out Boolean);
         Handlers : constant array (Positive range <>) of Handler_Access :=
           [Handle_Projects'Access,
            Handle_Plan'Access,
            Handle_Approval'Access,
            Handle_Publication'Access,
            Handle_Commands'Access,
            Handle_Status_Errors'Access,
            Handle_Work'Access,
            Handle_Assessment'Access,
            Handle_Verification'Access];
         Done : Boolean;

         function Schema_Version return String is
           (if Has_State or else Is_Database_Statistics then "2" else "1");

         function Database_Identity return String is
         begin
            if Is_Database_Statistics
              and then Ada.Strings.Fixed.Index (To_String (Database_Path), "quality.db") > 0
            then
               return ",""database_identity"":""123e4567-e89b-12d3-a456-426614174000""";
            elsif Is_Database_Statistics
              and then To_String (Database_Path) = "invalid-identity.db"
            then
               return ",""database_identity"":""not-a-uuid""";
            else
               return "";
            end if;
         end Database_Identity;
      begin
         for Handler of Handlers loop
            Handler (Text, Done);
            if Done then
               return;
            end if;
         end loop;
         Ada.Text_IO.Put
           ("{""schema_version"":" & Schema_Version
            & ",""command"":""" & To_String (Command) & """"
            & ",""report_type"":""" & To_String (Command) & """"
            & ",""kind"":""" & To_String (Kind) & """"
            & Database_Identity
            & ",""invocation"":""" & To_String (Invocation) & """}");
      end Dispatch;
   begin
      while Index <= Ada.Command_Line.Argument_Count loop
         declare
            Argument : constant String := Ada.Command_Line.Argument (Index);
         begin
            if Argument = "--state" then Has_State := True; end if;
            if Argument = "--database" then
               Database_Path := To_Unbounded_String (Ada.Command_Line.Argument (Index + 1));
               Index := Index + 2;
            elsif Argument = "--policy" then
               Index := Index + 2;
            elsif Argument in "--format" | "--config" | "--state" then
               Index := Index + 2;
            else
               if Length (Command) = 0 then
                  Command := To_Unbounded_String (Argument);
               end if;
               if Length (Invocation) > 0 then Append (Invocation, " "); end if;
               Append (Invocation, Argument);
               Index := Index + 1;
            end if;
         end;
      end loop;
      Dispatch (To_String (Invocation));
   end Run_Structured;

begin
   Run_Crash_Fixture;
   Read_Numeric_Mode;
   if Numeric_Mode then
      Run_Numeric_Output;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
   else
      Run_Structured;
   end if;
end QM_Adapter_Fixture;
