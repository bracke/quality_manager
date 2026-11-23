with Ada.Strings.Unbounded;
with Interfaces;
with Quality_Manager.Identities;
with Quality_Manager.Journal;
with Quality_Manager.Model;

--  Defines typed logical persistence records.
package Quality_Manager.Storage.Schema is
   --  Public contract for this Quality Manager unit.
   subtype Text is Ada.Strings.Unbounded.Unbounded_String;
   --  Text domain value.
   subtype Sequence_Number is Interfaces.Unsigned_64;
   --  Sequence Number domain value.

   type Metadata is record
      Schema_Version        : Positive := Quality_Manager.Storage.Current_Schema_Version;
      Installation_Identity : Text;
   end record;
   --  Metadata record.
   --  @field Schema_Version Schema Version.
   --  @field Installation_Identity Installation Identity.

   type Project is record
      Key                      : Quality_Manager.Identities.Project_Key;
      Enabled                  : Boolean := True;
      Last_Assessment_Run      : Natural := 0;
      Last_Source_Fingerprint  : Text;
   end record;
   --  Project record.
   --  @field Key Key.
   --  @field Enabled Enabled.
   --  @field Last_Assessment_Run Last Assessment Run.
   --  @field Last_Source_Fingerprint Last Source Fingerprint.

   type Cycle is record
      Cycle_Id      : Text;
      Workflow      : Quality_Manager.Model.Workflow_Kind;
      Trigger       : Text;
      Project       : Quality_Manager.Identities.Project_Key;
      Policy_Digest : Text;
      State         : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
   end record;
   --  Cycle record.
   --  @field Cycle_Id Cycle Id.
   --  @field Workflow Workflow.
   --  @field Trigger Trigger.
   --  @field Project Project.
   --  @field Policy_Digest Policy Digest.
   --  @field State State.

   type Work_Item is record
      Work_Id             : Text;
      Global_Remediation  : Text;
      Project             : Quality_Manager.Identities.Project_Key;
      Origin              : Quality_Manager.Model.Workflow_Kind;
      Finding_Identities  : Text;
      Priority            : Natural := 0;
      Baseline_Assessment_Run : Natural := 0;
      Improve_Plan_Id     : Text;
      Improve_Revision    : Natural := 0;
      Improve_Task_Id     : Text;
      Improve_Content_SHA256 : Text;
      Planned_Source_Fingerprint : Text;
      Effective_Policy_Digest : Text;
      State               : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
      Outcome             : Quality_Manager.Model.Outcome_Kind := Quality_Manager.Model.No_Outcome;
   end record;
   --  Work Item record.
   --  @field Work_Id Work Id.
   --  @field Global_Remediation Global Remediation.
   --  @field Project Project.
   --  @field Origin Origin.
   --  @field Finding_Identities Finding Identities.
   --  @field Priority Priority.
   --  @field Baseline_Assessment_Run Baseline Assessment Run.
   --  @field Improve_Plan_Id Improve Plan Id.
   --  @field Improve_Revision Improve Revision.
   --  @field Improve_Task_Id Improve Task Id.
   --  @field Improve_Content_SHA256 Improve Content SHA256.
   --  @field Planned_Source_Fingerprint Planned Source Fingerprint.
   --  @field Effective_Policy_Digest Effective Policy Digest.
   --  @field State State.
   --  @field Outcome Outcome.

   type Dispatch is record
      Dispatch_Id        : Text;
      Work_Id            : Text;
      Logical_Remediation : Text;
      Improve_Task       : Quality_Manager.Identities.Improve_Task_Key;
      Native_Task_Id     : Text;
      Authorization_Id   : Text;
      State              : Quality_Manager.Model.Work_State := Quality_Manager.Model.Published;
      Active             : Boolean := True;
   end record;
   --  Dispatch record.
   --  @field Dispatch_Id Dispatch Id.
   --  @field Work_Id Work Id.
   --  @field Logical_Remediation Logical Remediation.
   --  @field Improve_Task Improve Task.
   --  @field Native_Task_Id Native Task Id.
   --  @field Authorization_Id Authorization Id.
   --  @field State State.
   --  @field Active Active.

   type Attempt is record
      Attempt             : Quality_Manager.Identities.Attempt_Id := 0;
      Dispatch_Id         : Text;
      Execution_Identity  : Text;
      Started_At          : Sequence_Number := 0;
      Finished_At         : Sequence_Number := 0;
      Timeout_Seconds     : Positive := 3_600;
      Outcome             : Quality_Manager.Model.Outcome_Kind := Quality_Manager.Model.No_Outcome;
   end record;
   --  Attempt record.
   --  @field Attempt Attempt.
   --  @field Dispatch_Id Dispatch Id.
   --  @field Execution_Identity Execution Identity.
   --  @field Started_At Started At.
   --  @field Finished_At Finished At.
   --  @field Timeout_Seconds Timeout Seconds.
   --  @field Outcome Outcome.

   type Lease is record
      Resource_Key : Text;
      Owner         : Text;
      Generation    : Sequence_Number := 0;
      Expires_At    : Sequence_Number := 0;
   end record;
   --  Lease record.
   --  @field Resource_Key Resource Key.
   --  @field Owner Owner.
   --  @field Generation Generation.
   --  @field Expires_At Expires At.

   type Journal_Entry is record
      Operation       : Quality_Manager.Identities.Operation_Id := 0;
      Operation_Kind  : Text;
      Intent          : Text;
      State           : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
      External_Id     : Text;
      Diagnostic      : Text;
   end record;
   --  Journal Entry record.
   --  @field Operation Operation.
   --  @field Operation_Kind Operation Kind.
   --  @field Intent Intent.
   --  @field State State.
   --  @field External_Id External Id.
   --  @field Diagnostic Diagnostic.

   type Approval is record
      Approval_Id       : Text;
      Project           : Quality_Manager.Identities.Project_Key;
      Plan_Id           : Text;
      Plan_Revision     : Positive := 1;
      Content_Digest    : Text;
      Authorized_Action : Text;
      Policy_Digest     : Text;
      Approver          : Text;
      Created_At        : Sequence_Number := 0;
      Expires_At        : Sequence_Number := 0;
   end record;
   --  Approval record.
   --  @field Approval_Id Approval Id.
   --  @field Project Project.
   --  @field Plan_Id Plan Id.
   --  @field Plan_Revision Plan Revision.
   --  @field Content_Digest Content Digest.
   --  @field Authorized_Action Authorized Action.
   --  @field Policy_Digest Policy Digest.
   --  @field Approver Approver.
   --  @field Created_At Created At.
   --  @field Expires_At Expires At.

   type Campaign is record
      Campaign_Id       : Text;
      Definition_Revision : Positive := 1;
      Definition_Digest : Text;
      Scope             : Text;
      Baseline          : Text;
      State             : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
      Budget            : Natural := 0;
      Used              : Natural := 0;
   end record;
   --  Campaign record.
   --  @field Campaign_Id Campaign Id.
   --  @field Definition_Revision Definition Revision.
   --  @field Definition_Digest Definition Digest.
   --  @field Scope Scope.
   --  @field Baseline Baseline.
   --  @field State State.
   --  @field Budget Budget.
   --  @field Used Used.

   type Campaign_Target is record
      Composite_Key  : Text;
      Campaign_Id    : Text;
      Definition_Revision : Positive := 1;
      Project        : Quality_Manager.Identities.Project_Key;
      Indicator      : Text;
      Baseline       : Text;
      Target         : Text;
      Latest_Result  : Text;
   end record;
   --  Campaign Target record.
   --  @field Composite_Key Composite Key.
   --  @field Campaign_Id Campaign Id.
   --  @field Definition_Revision Definition Revision.
   --  @field Project Project.
   --  @field Indicator Indicator.
   --  @field Baseline Baseline.
   --  @field Target Target.
   --  @field Latest_Result Latest Result.

   type Release is record
      Release_Id       : Text;
      Project          : Quality_Manager.Identities.Project_Key;
      Candidate_Commit : Text;
      Source_Digest    : Text;
      Policy_Digest    : Text;
      Toolchain        : Text;
      Release_Config   : Text;
      Generation       : Natural := 1;
      Final_Assessment : Natural := 0;
      Coverage_Basis_Points : Natural := 0;
      State            : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
   end record;
   --  Release record.
   --  @field Release_Id Release Id.
   --  @field Project Project.
   --  @field Candidate_Commit Candidate Commit.
   --  @field Source_Digest Source Digest.
   --  @field Policy_Digest Policy Digest.
   --  @field Toolchain Toolchain.
   --  @field Release_Config Release Config.
   --  @field Generation Generation.
   --  @field Final_Assessment Final Assessment.
   --  @field Coverage_Basis_Points Coverage Basis Points.
   --  @field State State.

   type Verification is record
      Composite_Key       : Text;
      Work_Id             : Text;
      Assessment          : Quality_Manager.Identities.Assessment_Key;
      Contract_Digest     : Text;
      Native_Result       : Text;
      Improve_Result      : Text;
      Regression_Result   : Text;
      Candidate_Revision  : Text;
      Source_Fingerprint  : Text;
      Policy_Fingerprint  : Text;
      Toolchain_Fingerprint : Text;
   end record;
   --  Verification record.
   --  @field Composite_Key Composite Key.
   --  @field Work_Id Work Id.
   --  @field Assessment Assessment.
   --  @field Contract_Digest Contract Digest.
   --  @field Native_Result Native Result.
   --  @field Improve_Result Improve Result.
   --  @field Regression_Result Regression Result.
   --  @field Candidate_Revision Candidate Revision.
   --  @field Source_Fingerprint Source Fingerprint.
   --  @field Policy_Fingerprint Policy Fingerprint.
   --  @field Toolchain_Fingerprint Toolchain Fingerprint.

   type Event is record
      Event_Id            : Text;
      Entity              : Text;
      Previous_State      : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
      New_State           : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
      Occurred_At         : Sequence_Number := 0;
      Cause               : Text;
      Evidence_References : Text;
   end record;
   --  Event record.
   --  @field Event_Id Event Id.
   --  @field Entity Entity.
   --  @field Previous_State Previous State.
   --  @field New_State New State.
   --  @field Occurred_At Occurred At.
   --  @field Cause Cause.
   --  @field Evidence_References Evidence References.
end Quality_Manager.Storage.Schema;
