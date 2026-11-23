separate (Quality_Manager_Test_Suite)
procedure Test_Verification_Engine (Item : in out Fixture) is
   pragma Unreferenced (Item);

   function Assessment_JSON
     (Source : String;
      Complete : Boolean := True;
      Variant : Natural := 0) return String is
      Text : Unbounded_String := To_Unbounded_String
        ("{""schema_version"":1,""assessment_id"":2,""project_id"":7," &
         """project_path"":""/project"",""source_fingerprint"":""" & Source & """," &
         """policy_fingerprint"":""policy"",""toolchain_fingerprint"":""toolchain""," &
         """status"":""ASSESSMENT_COMPLETED"",""results"":[");

      function Selected (Choice, Position : Natural) return Boolean is
        (Variant = Choice and then Position = 1);

      function Has_Coverage (Position : Natural) return Boolean is
        (Position = 3 and then Variant /= 3);

      function Indicator_For (Position : Natural) return String is
         Number : constant String := Ada.Strings.Fixed.Trim
           (Natural'Image (Position), Ada.Strings.Both);
      begin
         if Selected (2, Position) then
            return "bad";
         elsif Selected (4, Position) then
            return "PRF-01";
         else
            return "TST-" & (if Position < 10 then "0" else "") & Number;
         end if;
      end Indicator_For;

      function Compliance_For (Position : Natural) return String is
      begin
         if Selected (1, Position) then
            return "violation";
         elsif Selected (5, Position) or else Selected (6, Position) then
            return "pass";
         elsif not Complete and then Position = 1 then
            return "unknown";
         else
            return "pass";
         end if;
      end Compliance_For;
   begin
      for Index in 1 .. 33 loop
         if Index > 1 then
            Append (Text, ",");
         end if;
         declare
            Indicator  : constant String := Indicator_For (Index);
            Compliance : constant String := Compliance_For (Index);
         begin
            Append
              (Text,
               "{""indicator"":""" & Indicator & """,""execution"":""" &
               (if Selected (5, Index) then "failed" else "succeeded") &
               """,""compliance"":""" & Compliance &
               """,""applicable"":" &
               (if Selected (6, Index) then "false" else "true") &
               ",""summary"":""ok""," &
               """evidence"":""fixture"",""measurement"":" &
               (if Has_Coverage (Index) then "{""basis_points"":9000}" else "{}") &
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
Assert (Result.Kind = Quality_Manager.Results.Success,
      "complete 33-indicator assessment evidence is decoded");
   Assert (Assessment.Complete,
      "complete 33-indicator assessment evidence is decoded");
   Quality_Manager.Verification.Decode_Regression
     (Response
        ("{""schema_version"":1,""kind"":""assessment-comparison"",""project_id"":7," &
         """status"":""comparison-available"",""baseline_id"":1,""current_id"":2," &
         """policy_changed"":false,""changes"":[]}"),
      Regression, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "explicit selected-baseline comparison is decoded");
   Assert (Regression.Regression_Count = 0,
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
Assert (Result.Kind = Quality_Manager.Results.Success,
      "exact Improve task verification is decoded");
   Assert (Improve.Task_Found,
      "exact Improve task verification is decoded");

   Native.State := Quality_Manager.Integrations.Runner.Completed_State;
   Native.Workspace_State := To_Unbounded_String ("integrated");
   Quality_Manager.Verification.Decide
     (Native, Assessment, Regression, Improve, Context, Decision);
Assert (Decision.Verified,
      "N and Q and R and F is the only verified outcome");
   Assert (Decision.Outcome = Quality_Manager.Model.Satisfied,
      "N and Q and R and F is the only verified outcome");

   Context.Candidate_Source := To_Unbounded_String ("different-source");
   Quality_Manager.Verification.Decide
     (Native, Assessment, Regression, Improve, Context, Decision);
Assert (not Decision.Verified,
      "source mismatch invalidates otherwise successful evidence");
   Assert (Decision.Outcome = Quality_Manager.Model.Evidence_Unavailable,
      "source mismatch invalidates otherwise successful evidence");
   Context.Candidate_Source := To_Unbounded_String ("candidate-source");
   Quality_Manager.Verification.Decode_Assessment
     (Response (Assessment_JSON ("candidate-source", False)), Assessment, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "an assessment missing one indicator remains incomplete evidence");
   Assert (not Assessment.Complete,
      "an assessment missing one indicator remains incomplete evidence");
   declare
      Incomplete_Response : constant Quality_Manager.Integrations.JSON_CLI.Response :=
        (Status => Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Stale_Evidence,
            "assessment completed with incomplete evidence",
            "fixture.incomplete"),
         Exit_Status => 3,
         Document => To_Unbounded_String
           (Assessment_JSON ("candidate-source", False)),
         Diagnostics => Null_Unbounded_String);
   begin
      Quality_Manager.Verification.Decode_Assessment
        (Incomplete_Response, Assessment, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "exit code 3 adopts the durable incomplete assessment");
      Assert (Assessment.Assessment_Id = 2,
         "exit code 3 adopts the durable incomplete assessment");
      Assert (Assessment.Completed,
         "exit code 3 adopts the durable incomplete assessment");
      Assert (not Assessment.Complete,
         "exit code 3 adopts the durable incomplete assessment");
   end;
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

   Native.State := Quality_Manager.Integrations.Runner.Failed_State;
   Quality_Manager.Verification.Decide
     (Native, Assessment, Regression, Improve, Context, Decision);
   Assert (Decision.Outcome = Quality_Manager.Model.Execution_Failed,
           "native failure remains independent from quality evidence");

   for Outcome in Quality_Manager.Model.Outcome_Kind loop
      declare
         Action : constant Quality_Manager.Verification.Retry_Action :=
           Quality_Manager.Verification.Retry_For (Outcome, 0, 2);
         Expected : constant Quality_Manager.Verification.Retry_Action :=
           (case Outcome is
               when Quality_Manager.Model.No_Outcome =>
                  Quality_Manager.Verification.Retry_Idempotent_Operation,
               when Quality_Manager.Model.Unresolved =>
                  Quality_Manager.Verification.Replan_Remediation,
               when Quality_Manager.Model.Regression =>
                  Quality_Manager.Verification.Reject_Candidate,
               when Quality_Manager.Model.Evidence_Unavailable =>
                  Quality_Manager.Verification.Repair_Evidence,
               when Quality_Manager.Model.Policy_Incompatible =>
                  Quality_Manager.Verification.Establish_Compatible_Baseline,
               when Quality_Manager.Model.Execution_Failed =>
                  Quality_Manager.Verification.Start_New_Execution_Attempt,
               when Quality_Manager.Model.Authorization_Required =>
                  Quality_Manager.Verification.Escalate,
               when Quality_Manager.Model.Satisfied =>
                  Quality_Manager.Verification.No_Retry);
      begin
         Assert (Action = Expected, "every verification outcome has a cause-specific retry");
      end;
   end loop;

   Quality_Manager.Verification.Decode_Assessment
     (Response (Assessment_JSON ("candidate-source", Variant => 1)), Assessment, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
           "assessment violations remain evidence rather than process failures");
   Assert (Assessment.Violations = 1,
           "assessment violations remain evidence rather than process failures");
   for Variant in 2 .. 3 loop
      Quality_Manager.Verification.Decode_Assessment
        (Response (Assessment_JSON ("candidate-source", Variant => Variant)), Assessment, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
              "malformed indicator evidence remains explicitly incomplete");
      Assert (not Assessment.Complete,
              "malformed indicator evidence remains explicitly incomplete");
   end loop;
   Quality_Manager.Verification.Decode_Assessment
     (Response (Assessment_JSON ("candidate-source", Variant => 4)), Assessment, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "proof applicability and outcome are retained from the exact indicator");
   Assert (Assessment.Proof_Applicable,
      "proof applicability and outcome are retained from the exact indicator");
   Assert (Assessment.Proof_Passed,
      "proof applicability and outcome are retained from the exact indicator");
   for Variant in 5 .. 6 loop
      Quality_Manager.Verification.Decode_Assessment
        (Response (Assessment_JSON ("candidate-source", Variant => Variant)), Assessment, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
              "execution and applicability inconsistencies invalidate completeness");
      Assert (not Assessment.Complete,
              "execution and applicability inconsistencies invalidate completeness");
   end loop;

   declare
      Upstream_Failure : constant Quality_Manager.Integrations.JSON_CLI.Response :=
        (Status => Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Execution_Error, "upstream failed", "fixture.failed"),
         Exit_Status => 4, Document => Null_Unbounded_String,
         Diagnostics => Null_Unbounded_String);
   begin
      Quality_Manager.Verification.Decode_Assessment
        (Upstream_Failure, Assessment, Result);
      Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
              "assessment decoder preserves upstream execution failures");
      Quality_Manager.Verification.Decode_Regression
        (Upstream_Failure, Regression, Result);
      Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
              "regression decoder preserves upstream execution failures");
      Quality_Manager.Verification.Decode_Improve
        (Upstream_Failure, "IMP-001", Improve, Result);
      Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
              "Improve decoder preserves upstream execution failures");
   end;

   Quality_Manager.Verification.Decode_Assessment
     (Response ("{""schema_version"":1}"), Assessment, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
           "structurally incomplete assessment evidence fails closed");
   Quality_Manager.Verification.Decode_Regression
     (Response ("{""schema_version"":1}"), Regression, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
           "structurally incomplete regression evidence fails closed");
   Quality_Manager.Verification.Decode_Regression
     (Response
        ("{""schema_version"":1,""kind"":""assessment-comparison"",""project_id"":7," &
         """status"":""comparison-available"",""baseline_id"":1,""current_id"":2," &
         """policy_changed"":false,""changes"":[{""indicator"":""TST-03""," &
         """change"":""unknown-change"",""before"":""pass"",""after"":""violation""}]}"),
      Regression, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
           "unknown regression change kind is rejected");
   Quality_Manager.Verification.Decode_Improve
     (Response ("{""schema_version"":2,""command"":""verify"",""data"":{}}"),
      "IMP-001", Improve, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
           "structurally incomplete Improve evidence fails closed");
   Quality_Manager.Verification.Decode_Improve
     (Response
        ("{""schema_version"":2,""command"":""verify"",""data"":{" &
         """plan_id"":""PLAN-001"",""baseline_run"":1,""verification_run"":2," &
         """outcome"":""verified"",""plan_outcome"":""verified""," &
         """project_outcome"":""verified"",""comparable"":true,""new_critical"":0," &
         """explanation"":""resolved"",""tasks"":[{}]}}"),
      "IMP-001", Improve, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
           "malformed Improve task evidence is rejected");
   Quality_Manager.Verification.Decode_Improve
     (Response
        ("{""schema_version"":2,""command"":""verify"",""data"":{" &
         """plan_id"":""PLAN-001"",""baseline_run"":1,""verification_run"":2," &
         """outcome"":""verified"",""plan_outcome"":""verified""," &
         """project_outcome"":""verified"",""comparable"":true,""new_critical"":0," &
         """explanation"":""resolved"",""tasks"":[" &
         "{""task_id"":""IMP-001"",""outcome"":""verified"",""matched"":1," &
         """total"":1,""explanation"":""resolved""}," &
         "{""task_id"":""IMP-001"",""outcome"":""verified"",""matched"":1," &
         """total"":1,""explanation"":""duplicate""}]}}"),
      "IMP-001", Improve, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
           "duplicate Improve task evidence is rejected");

   Quality_Manager.Verification.Decode_Assessment
     (Response ("{"), Assessment, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
           "malformed assessment evidence fails closed");
   Quality_Manager.Verification.Decode_Regression
     (Response ("{"), Regression, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
           "malformed regression evidence fails closed");
   Quality_Manager.Verification.Decode_Improve
     (Response ("{"), "IMP-001", Improve, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
           "malformed Improve evidence fails closed");
end Test_Verification_Engine;

