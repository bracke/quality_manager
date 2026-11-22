with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Integrations.Runner;
with Quality_Manager.Identities;
with Quality_Manager.Model;
with Quality_Manager.Results;
with Quality_Manager.Storage;

package Quality_Manager.Verification is
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

   type Regression_Evidence is record
      Project_Id      : Natural := 0;
      Baseline_Id     : Natural := 0;
      Current_Id      : Natural := 0;
      Comparable      : Boolean := False;
      Policy_Changed  : Boolean := False;
      Compatibility_Failure : Boolean := False;
      Regression_Count : Natural := 0;
   end record;

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

   type Verification_Decision is record
      Native_Gate     : Boolean := False;
      Quality_Gate    : Boolean := False;
      Regression_Gate : Boolean := False;
      Freshness_Gate  : Boolean := False;
      Verified        : Boolean := False;
      Outcome         : Quality_Manager.Model.Outcome_Kind := Quality_Manager.Model.No_Outcome;
      Diagnostic      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

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

   procedure Establish_Assessment
     (Store    : in out Quality_Manager.Storage.Store;
      Quality  : Quality_Manager.Integrations.Quality.Adapter;
      Request  : Assessment_Request;
      Evidence : out Assessment_Evidence;
      Result   : out Quality_Manager.Results.Operation_Result);

   procedure Decode_Assessment
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Assessment_Evidence;
      Result   : out Quality_Manager.Results.Operation_Result);

   procedure Decode_Regression
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Regression_Evidence;
      Result   : out Quality_Manager.Results.Operation_Result);

   procedure Decode_Improve
     (Response         : Quality_Manager.Integrations.JSON_CLI.Response;
      Expected_Task_Id : String;
      Evidence         : out Improve_Evidence;
      Result           : out Quality_Manager.Results.Operation_Result);

   procedure Decide
     (Native     : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Assessment : Assessment_Evidence;
      Regression : Regression_Evidence;
      Improve    : Improve_Evidence;
      Context    : Verification_Context;
      Decision   : out Verification_Decision);

   function Retry_For
     (Outcome          : Quality_Manager.Model.Outcome_Kind;
      Attempts_Used    : Natural;
      Maximum_Attempts : Positive) return Retry_Action;

   procedure Verify_Remediation
     (Store       : in out Quality_Manager.Storage.Store;
      Quality     : Quality_Manager.Integrations.Quality.Adapter;
      Planner     : Quality_Manager.Integrations.Improve.Adapter;
      Native      : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Request     : Remediation_Request;
      Decision    : out Verification_Decision;
      Result      : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Verification;
