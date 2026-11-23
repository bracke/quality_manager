with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Integrations.Runner;
with Quality_Manager.Identities;
with Quality_Manager.Model;
with Quality_Manager.Results;
with Quality_Manager.Storage;

--  Combines native, quality, regression, and freshness evidence.
package Quality_Manager.Verification is
   --  Public contract for this Quality Manager unit.
   type Assessment_Evidence is record
      Assessment_Id        : Natural := 0;
      Project_Id           : Natural := 0;
      Project_Path         : Ada.Strings.Unbounded.Unbounded_String;
      Source_Fingerprint   : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Fingerprint   : Ada.Strings.Unbounded.Unbounded_String;
      Toolchain_Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
      Completed            : Boolean := False;
      Complete             : Boolean := False;
      Indicator_Count      : Natural := 0;
      Violations           : Natural := 0;
      Coverage_Basis_Points : Natural := 0;
      Proof_Applicable      : Boolean := False;
      Proof_Passed          : Boolean := False;
   end record;
   --  Assessment Evidence record.
   --  @field Assessment_Id Assessment Id.
   --  @field Project_Id Project Id.
   --  @field Project_Path Project Path.
   --  @field Source_Fingerprint Source Fingerprint.
   --  @field Policy_Fingerprint Policy Fingerprint.
   --  @field Toolchain_Fingerprint Toolchain Fingerprint.
   --  @field Completed Completed.
   --  @field Complete Complete.
   --  @field Indicator_Count Indicator Count.
   --  @field Violations Violations.
   --  @field Coverage_Basis_Points Coverage Basis Points.
   --  @field Proof_Applicable Proof Applicable.
   --  @field Proof_Passed Proof Passed.

   type Regression_Evidence is record
      Project_Id      : Natural := 0;
      Baseline_Id     : Natural := 0;
      Current_Id      : Natural := 0;
      Comparable      : Boolean := False;
      Policy_Changed  : Boolean := False;
      Compatibility_Failure : Boolean := False;
      Regression_Count : Natural := 0;
   end record;
   --  Regression Evidence record.
   --  @field Project_Id Project Id.
   --  @field Baseline_Id Baseline Id.
   --  @field Current_Id Current Id.
   --  @field Comparable Comparable.
   --  @field Policy_Changed Policy Changed.
   --  @field Compatibility_Failure Compatibility Failure.
   --  @field Regression_Count Regression Count.

   type Improve_Evidence is record
      Plan_Id          : Ada.Strings.Unbounded.Unbounded_String;
      Baseline_Run     : Natural := 0;
      Verification_Run : Natural := 0;
      Outcome           : Ada.Strings.Unbounded.Unbounded_String;
      Project_Outcome   : Ada.Strings.Unbounded.Unbounded_String;
      Comparable        : Boolean := False;
      New_Critical      : Natural := 0;
      Task_Id           : Ada.Strings.Unbounded.Unbounded_String;
      Task_Outcome      : Ada.Strings.Unbounded.Unbounded_String;
      Task_Found        : Boolean := False;
   end record;
   --  Improve Evidence record.
   --  @field Plan_Id Plan Id.
   --  @field Baseline_Run Baseline Run.
   --  @field Verification_Run Verification Run.
   --  @field Outcome Outcome.
   --  @field Project_Outcome Project Outcome.
   --  @field Comparable Comparable.
   --  @field New_Critical New Critical.
   --  @field Task_Id Task Id.
   --  @field Task_Outcome Task Outcome.
   --  @field Task_Found Task Found.

   type Verification_Context is record
      Project_Id             : Positive;
      Project_Path           : Ada.Strings.Unbounded.Unbounded_String;
      Candidate_Source       : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Fingerprint     : Ada.Strings.Unbounded.Unbounded_String;
      Toolchain_Fingerprint  : Ada.Strings.Unbounded.Unbounded_String;
      Baseline_Assessment    : Positive;
      Current_Assessment     : Positive;
      Improve_Plan_Id        : Ada.Strings.Unbounded.Unbounded_String;
      Improve_Task_Id        : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Verification Context record.
   --  @field Project_Id Project Id.
   --  @field Project_Path Project Path.
   --  @field Candidate_Source Candidate Source.
   --  @field Policy_Fingerprint Policy Fingerprint.
   --  @field Toolchain_Fingerprint Toolchain Fingerprint.
   --  @field Baseline_Assessment Baseline Assessment.
   --  @field Current_Assessment Current Assessment.
   --  @field Improve_Plan_Id Improve Plan Id.
   --  @field Improve_Task_Id Improve Task Id.

   type Verification_Decision is record
      Native_Gate     : Boolean := False;
      Quality_Gate    : Boolean := False;
      Regression_Gate : Boolean := False;
      Freshness_Gate  : Boolean := False;
      Verified        : Boolean := False;
      Outcome         : Quality_Manager.Model.Outcome_Kind := Quality_Manager.Model.No_Outcome;
      Diagnostic      : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Verification Decision record.
   --  @field Native_Gate Native Gate.
   --  @field Quality_Gate Quality Gate.
   --  @field Regression_Gate Regression Gate.
   --  @field Freshness_Gate Freshness Gate.
   --  @field Verified Verified.
   --  @field Outcome Outcome.
   --  @field Diagnostic Diagnostic.

   type Retry_Action is
     (No_Retry,
      Retry_Idempotent_Operation,
      Start_New_Execution_Attempt,
      Replan_Remediation,
      Reject_Candidate,
      Repair_Evidence,
      Establish_Compatible_Baseline,
      Block_Work,
      Escalate);
   --  Retry Action values.
   --  @enum No_Retry No Retry.
   --  @enum Retry_Idempotent_Operation Retry Idempotent Operation.
   --  @enum Start_New_Execution_Attempt Start New Execution Attempt.
   --  @enum Replan_Remediation Replan Remediation.
   --  @enum Reject_Candidate Reject Candidate.
   --  @enum Repair_Evidence Repair Evidence.
   --  @enum Establish_Compatible_Baseline Establish Compatible Baseline.
   --  @enum Block_Work Block Work.
   --  @enum Escalate Escalate.

   type Remediation_Request is record
      Work_Id                  : Ada.Strings.Unbounded.Unbounded_String;
      Project                  : Quality_Manager.Identities.Project_Key;
      Project_Selector         : Ada.Strings.Unbounded.Unbounded_String;
      Profile                  : Ada.Strings.Unbounded.Unbounded_String;
      Candidate_Revision       : Ada.Strings.Unbounded.Unbounded_String;
      Candidate_Source         : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Fingerprint       : Ada.Strings.Unbounded.Unbounded_String;
      Toolchain_Fingerprint    : Ada.Strings.Unbounded.Unbounded_String;
      Baseline_Assessment      : Positive;
      Improve_Plan_Id          : Ada.Strings.Unbounded.Unbounded_String;
      Improve_Plan_Revision    : Positive;
      Improve_Task_Id          : Ada.Strings.Unbounded.Unbounded_String;
      Contract_Digest          : Ada.Strings.Unbounded.Unbounded_String;
      Assessment_Operation     : Quality_Manager.Identities.Operation_Id;
      Improve_Operation        : Quality_Manager.Identities.Operation_Id;
      Attempts_Used            : Natural := 1;
      Maximum_Attempts         : Positive := 2;
   end record;
   --  Remediation Request record.
   --  @field Work_Id Work Id.
   --  @field Project Project.
   --  @field Project_Selector Project Selector.
   --  @field Profile Profile.
   --  @field Candidate_Revision Candidate Revision.
   --  @field Candidate_Source Candidate Source.
   --  @field Policy_Fingerprint Policy Fingerprint.
   --  @field Toolchain_Fingerprint Toolchain Fingerprint.
   --  @field Baseline_Assessment Baseline Assessment.
   --  @field Improve_Plan_Id Improve Plan Id.
   --  @field Improve_Plan_Revision Improve Plan Revision.
   --  @field Improve_Task_Id Improve Task Id.
   --  @field Contract_Digest Contract Digest.
   --  @field Assessment_Operation Assessment Operation.
   --  @field Improve_Operation Improve Operation.
   --  @field Attempts_Used Attempts Used.
   --  @field Maximum_Attempts Maximum Attempts.

   type Assessment_Request is record
      Operation             : Quality_Manager.Identities.Operation_Id;
      Work_Id               : Ada.Strings.Unbounded.Unbounded_String;
      Project               : Quality_Manager.Identities.Project_Key;
      Project_Selector      : Ada.Strings.Unbounded.Unbounded_String;
      Profile               : Ada.Strings.Unbounded.Unbounded_String;
      Candidate_Source      : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Fingerprint    : Ada.Strings.Unbounded.Unbounded_String;
      Toolchain_Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Assessment Request record.
   --  @field Operation Operation.
   --  @field Work_Id Work Id.
   --  @field Project Project.
   --  @field Project_Selector Project Selector.
   --  @field Profile Profile.
   --  @field Candidate_Source Candidate Source.
   --  @field Policy_Fingerprint Policy Fingerprint.
   --  @field Toolchain_Fingerprint Toolchain Fingerprint.

   procedure Establish_Assessment
     (Store    : in out Quality_Manager.Storage.Store;
      Quality  : Quality_Manager.Integrations.Quality.Adapter;
      Request  : Assessment_Request;
      Evidence : out Assessment_Evidence;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Establish Assessment.
   --  @param Store Store.
   --  @param Quality Quality.
   --  @param Request Request.
   --  @param Evidence Evidence.
   --  @param Result Result.

   procedure Decode_Assessment
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Assessment_Evidence;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Decode Assessment.
   --  @param Response Response.
   --  @param Evidence Evidence.
   --  @param Result Result.

   procedure Decode_Regression
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Regression_Evidence;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Decode Regression.
   --  @param Response Response.
   --  @param Evidence Evidence.
   --  @param Result Result.

   procedure Decode_Improve
     (Response         : Quality_Manager.Integrations.JSON_CLI.Response;
      Expected_Task_Id : String;
      Evidence         : out Improve_Evidence;
      Result           : out Quality_Manager.Results.Operation_Result);
   --  Perform Decode Improve.
   --  @param Response Response.
   --  @param Expected_Task_Id Expected Task Id.
   --  @param Evidence Evidence.
   --  @param Result Result.

   procedure Decide
     (Native     : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Assessment : Assessment_Evidence;
      Regression : Regression_Evidence;
      Improve    : Improve_Evidence;
      Context    : Verification_Context;
      Decision   : out Verification_Decision);
   --  Perform Decide.
   --  @param Native Native.
   --  @param Assessment Assessment.
   --  @param Regression Regression.
   --  @param Improve Improve.
   --  @param Context Context.
   --  @param Decision Decision.

   function Retry_For
     (Outcome          : Quality_Manager.Model.Outcome_Kind;
      Attempts_Used    : Natural;
      Maximum_Attempts : Positive) return Retry_Action;
   --  Return Retry For.
   --  @param Outcome Outcome.
   --  @param Attempts_Used Attempts Used.
   --  @param Maximum_Attempts Maximum Attempts.
   --  @return Retry For result.

   procedure Verify_Remediation
     (Store       : in out Quality_Manager.Storage.Store;
      Quality     : Quality_Manager.Integrations.Quality.Adapter;
      Planner     : Quality_Manager.Integrations.Improve.Adapter;
      Native      : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Request     : Remediation_Request;
      Decision    : out Verification_Decision;
      Result      : out Quality_Manager.Results.Operation_Result);
   --  Perform Verify Remediation.
   --  @param Store Store.
   --  @param Quality Quality.
   --  @param Planner Planner.
   --  @param Native Native.
   --  @param Request Request.
   --  @param Decision Decision.
   --  @param Result Result.
end Quality_Manager.Verification;
