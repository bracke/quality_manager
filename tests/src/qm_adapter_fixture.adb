with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

procedure QM_Adapter_Fixture is
   Status : Integer := 0;
   Numeric_Mode : Boolean := False;
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      begin
         Status := Integer'Value (Ada.Command_Line.Argument (1));
         Numeric_Mode := True;
      exception
         when Constraint_Error => Numeric_Mode := False;
      end;
   end if;
   if not Numeric_Mode then
      declare
         Invocation : Unbounded_String;
         Command     : Unbounded_String;
         Kind        : Unbounded_String;
         Database_Path : Unbounded_String;
         Has_State  : Boolean := False;
         Is_Database_Statistics : Boolean := False;
         Index      : Positive := 1;
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
         declare
            Text : constant String := To_String (Invocation);
         begin
            if Ada.Strings.Fixed.Index (Text, "project list") = 1 then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""project-list"",""projects"":[" &
                  "{""id"":7,""path"":""/project"",""enabled"":true,""removed"":false}," &
                  "{""id"":8,""path"":""/disabled"",""enabled"":false,""removed"":false}," &
                  "{""id"":9,""path"":""/second"",""enabled"":true,""removed"":false}]}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "project ") = 1 then
               Kind := To_Unbounded_String ("project-list");
            elsif Ada.Strings.Fixed.Index (Text, "check ") = 1
              and then Ada.Strings.Fixed.Index (Text, "--dry-run") > 0
            then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""check-plan"",""projects"":[{" &
                  """project_id"":" &
                  (if Ada.Strings.Fixed.Index (Text, "--project 9") > 0 then "9" else "7") &
                  ",""path"":""" &
                  (if Ada.Strings.Fixed.Index (Text, "--project 9") > 0 then "/second" else "/project") &
                  """," &
                  """source_fingerprint"":""candidate-source""," &
                  """policy_fingerprint"":""policy""," &
                  """toolchain_fingerprint"":""toolchain""," &
                  """reuse_eligible"":false,""action"":""assess""}]}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "assessment diff ") = 1 then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""assessment-comparison""," &
                  """project_id"":7,""status"":""comparison-available""," &
                  """baseline_id"":" &
                  (if Ada.Strings.Fixed.Index (Text, "assessment diff 3 2") = 1 then "3" else "1") &
                  ",""current_id"":2,""policy_changed"":false,""changes"":" &
                  (if Ada.Strings.Fixed.Index (Text, "assessment diff 3 2") = 1
                   then "[{""indicator"":""TST-03"",""change"":""new-violation""," &
                     """before"":""pass"",""after"":""violation""}]"
                   else "[]") & "}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "plan --project 7 --run 2") = 1
              or else Text = "plan show PLAN-001 --revision 1"
            then
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
               return;
            elsif Ada.Strings.Fixed.Index (Text, "plan approve ") = 1 then
               Ada.Text_IO.Put
                 ("{""schema_version"":2,""command"":""plan approve"",""data"":{" &
                  """plan_id"":""PLAN-001"",""revision"":1," &
                  """content_sha256"":""plan-content-sha256-v2:" &
                  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""," &
                  """approved"":true,""invocation"":""" & To_String (Invocation) & """}}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "doctor ") = 1 then
               Kind := To_Unbounded_String ("doctor-report");
            elsif Text = "database stats" then
               Kind := To_Unbounded_String ("database-statistics");
               Is_Database_Statistics := True;
            elsif Text = "rev-parse HEAD" then
               Ada.Text_IO.Put ("fixture-commit");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Text = "work capabilities" then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""work-capabilities""," &
                  """noninteractive"":true,""idempotent_operations"":true," &
                  """operation_lookup"":true,""workspace_isolation"":true," &
                  """semantic_conflict_resolution"":false,""commands"":" &
                  "[""inspect"",""execute"",""status"",""cancel"",""recover"",""integrate""]}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "work cancel ") = 1 then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""work-cancellation""," &
                  """operation_id"":""qm-execution-1"",""task_id"":""TASK-001""," &
                  """result"":""requested""}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "work recover ") = 1 then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""work-recovery""," &
                  """project_identity"":""project-identity"",""result"":""reconciled""}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "work status ") = 1
              and then Ada.Strings.Fixed.Index (Text, "missing-operation") > 0
            then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""error""," &
                  """error_code"":""MR-FRAMEWORK-0011"",""diagnostic"":""missing-operation""}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (2));
               return;
            elsif Ada.Strings.Fixed.Index (Text, "work inspect ") = 1
              or else Ada.Strings.Fixed.Index (Text, "work execute ") = 1
              or else Ada.Strings.Fixed.Index (Text, "work status ") = 1
              or else Ada.Strings.Fixed.Index (Text, "work integrate ") = 1
            then
               declare
                  Operation : constant String :=
                    (if Ada.Strings.Fixed.Index (Text, "qm-execution-2") > 0 then "qm-execution-2"
                     elsif Ada.Strings.Fixed.Index (Text, "qm-execution-3") > 0 then "qm-execution-3"
                     elsif Ada.Strings.Fixed.Index (Text, "qm-execution-4") > 0 then "qm-execution-4"
                     elsif Ada.Strings.Fixed.Index (Text, "qm-execution-5") > 0 then "qm-execution-5"
                     elsif Ada.Strings.Fixed.Index (Text, "qm-execution-6") > 0 then "qm-execution-6"
                     elsif Ada.Strings.Fixed.Index (Text, "qm-execution-7") > 0 then "qm-execution-7"
                     elsif Ada.Strings.Fixed.Index (Text, "qm-execution-8") > 0 then "qm-execution-8"
                     elsif Ada.Strings.Fixed.Index (Text, "qm-execution-9") > 0 then "qm-execution-9"
                     else "qm-execution-1");
                  Is_Execute : constant Boolean := Ada.Strings.Fixed.Index (Text, "work execute ") = 1;
                  Is_Integrate : constant Boolean := Ada.Strings.Fixed.Index (Text, "work integrate ") = 1;
                  Running : constant Boolean :=
                    Operation in "qm-execution-2" | "qm-execution-6" | "qm-execution-7"
                    and then Is_Execute;
                  Incompatible : constant Boolean := Operation = "qm-execution-3";
                  Cancelled : constant Boolean := Operation = "qm-execution-4";
                  Failed : constant Boolean := Operation = "qm-execution-5";
                  Pending_Integration : constant Boolean :=
                    Operation = "qm-execution-8" and then Is_Integrate;
                  Audit : constant String := (if Is_Execute then "execute-audit" else "status-audit");
               begin
                  Ada.Text_IO.Put
                    ("{""schema_version"":1,""kind"":""work-operation""," &
                     """operation_id"":""" & Operation & """,""project_identity"":""project-identity""," &
                     """source_fingerprint"":""" &
                     (if Is_Integrate and then not Pending_Integration
                      then "integrated-source" else "source-fingerprint") &
                     """,""task_id"":""TASK-001""," &
                     """task_revision"":""task-revision"",""effective_task_revision"":""effective-revision""," &
                     """execution_policy"":""policy-fingerprint"",""execution_generation"":""1""," &
                     """execution_state"":""" &
                     (if Incompatible then "incompatible"
                      elsif Cancelled then "cancelled"
                      elsif Failed then "failed"
                      elsif Running then "executing"
                      elsif Is_Integrate and then not Pending_Integration
                      then "completed" else "awaiting_integration") &
                     """,""native_task_state"":""" &
                     (if Running then "running" elsif Failed then "failed"
                      elsif Cancelled then "cancelled" else "verification") &
                     """,""core_state"":""" &
                     (if Running then "running" elsif Failed then "failed"
                      elsif Cancelled then "cancelled" else "verification") &
                     """,""ready"":false,""readiness_reasons"":[]," &
                     """workspace_id"":""" & (if Is_Integrate then "" else "workspace-1") &
                     """,""workspace_state"":""" &
                     (if Is_Integrate and then not Pending_Integration then "integrated" else "active") &
                     """," &
                     """result"":""success"",""diagnostics"":[],""audit_reference"":""" & Audit & """," &
                     """invocation"":""" & To_String (Invocation) & """}");
               end;
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "check ") = 1
              or else Text = "assessment show 2 --json"
            then
               if Ada.Strings.Fixed.Index (Text, "--project 99") > 0 then
                  Ada.Text_IO.Put ("not-json");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
                  return;
               end if;
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""assessment_id"":2,""project_id"":" &
                  (if Ada.Strings.Fixed.Index (Text, "--project 9") > 0 then "9" else "7") & "," &
                  """project_path"":""" &
                  (if To_String (Database_Path) = "release-quality.db"
                   then Ada.Directories.Current_Directory
                   elsif Ada.Strings.Fixed.Index (Text, "--project 9") > 0 then "/second"
                   else "/project") &
                  """,""source_fingerprint"":""candidate-source""," &
                  """policy_fingerprint"":""policy"",""toolchain_fingerprint"":""toolchain""," &
                  """status"":""ASSESSMENT_COMPLETED"",""results"":[");
               for Result_Index in 1 .. 33 loop
                  if Result_Index > 1 then Ada.Text_IO.Put (","); end if;
                  declare
                     Number : constant String := Ada.Strings.Fixed.Trim
                       (Natural'Image (Result_Index), Ada.Strings.Both);
                     Indicator : constant String :=
                       "TST-" & (if Result_Index < 10 then "0" else "") & Number;
                  begin
                  Ada.Text_IO.Put
                       ("{""indicator"":""" & Indicator & """,""execution"":""succeeded""," &
                        """compliance"":""" &
                        (if Ada.Strings.Fixed.Index (Text, "--project 9") > 0 and then Result_Index = 1
                         then "unknown"
                         elsif Ada.Strings.Fixed.Index (Text, "--project 7") > 0
                           and then To_String (Database_Path) = "quality.db"
                           and then Result_Index = 1
                         then "violation"
                         else "pass") &
                        """,""applicable"":true,""summary"":""ok""," &
                        """evidence"":""fixture"",""measurement"":" &
                        (if Result_Index = 3 then "{""basis_points"":9000}" else "{}") &
                        ",""findings"":[]}");
                  end;
               end loop;
               Ada.Text_IO.Put ("],""executions"":[]}");
               Ada.Command_Line.Set_Exit_Status
                 (if Ada.Strings.Fixed.Index (Text, "--project 9") > 0
                  then Ada.Command_Line.Exit_Status (3)
                  else Ada.Command_Line.Success);
               return;
            elsif Has_State
              and then Ada.Strings.Fixed.Index (Text, "verify --task IMP-") = 1
            then
               declare
                  Failing : constant Boolean := Ada.Strings.Fixed.Index (Text, "IMP-FAIL") > 0;
               begin
                  Ada.Text_IO.Put
                    ("{""schema_version"":2,""command"":""verify"",""data"":{" &
                     """plan_id"":""PLAN-001"",""baseline_run"":1,""verification_run"":2," &
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
               return;
            end if;
         end;
         Ada.Text_IO.Put
           ("{""schema_version"":" & (if Has_State or else Is_Database_Statistics then "2" else "1")
            & ",""command"":""" & To_String (Command) & """"
            & ",""report_type"":""" & To_String (Command) & """"
            & ",""kind"":""" & To_String (Kind) & """"
            & (if Is_Database_Statistics
               and then Ada.Strings.Fixed.Index (To_String (Database_Path), "quality.db") > 0
               then ",""database_identity"":""123e4567-e89b-12d3-a456-426614174000"""
               elsif Is_Database_Statistics and then To_String (Database_Path) = "invalid-identity.db"
               then ",""database_identity"":""not-a-uuid"""
               else "")
            & ",""invocation"":""" & To_String (Invocation) & """}");
      end;
   elsif Ada.Command_Line.Argument_Count >= 2 and then Ada.Command_Line.Argument (2) = "invalid-utf8" then
      Ada.Text_IO.Put (Character'Val (16#C3#) & Character'Val (16#28#));
   elsif Ada.Command_Line.Argument_Count >= 2 then
      Ada.Text_IO.Put (Ada.Command_Line.Argument (2));
   end if;
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
end QM_Adapter_Fixture;
