with Ada.Strings.Unbounded;
with Interfaces;
with Quality_Manager.Identities;
with Quality_Manager.Journal;
with Quality_Manager.Model;

package Quality_Manager.Storage.Schema is
   subtype Text is Ada.Strings.Unbounded.Unbounded_String;
   subtype Sequence_Number is Interfaces.Unsigned_64;

   type Metadata is record
      Schema_Version        : Positive := Quality_Manager.Storage.Current_Schema_Version;
      Installation_Identity : Text;
   end record;

   type Project is record
      Key                      : Quality_Manager.Identities.Project_Key;
      Enabled                  : Boolean := True;
      Last_Assessment_Run      : Natural := 0;
      Last_Source_Fingerprint  : Text;
   end record;

   type Cycle is record
      Cycle_Id      : Text;
      Workflow      : Quality_Manager.Model.Workflow_Kind;
      Trigger       : Text;
      Project       : Quality_Manager.Identities.Project_Key;
      Policy_Digest : Text;
      State         : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
   end record;

   type Work_Item is record
      Work_Id             : Text;
      Global_Remediation  : Text;
      Project             : Quality_Manager.Identities.Project_Key;
      Origin              : Quality_Manager.Model.Workflow_Kind;
      Finding_Identities  : Text;
      Priority            : Natural := 0;
      Improve_Plan_Id     : Text;
      Improve_Revision    : Natural := 0;
      Improve_Task_Id     : Text;
      State               : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
      Outcome             : Quality_Manager.Model.Outcome_Kind := Quality_Manager.Model.No_Outcome;
   end record;

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

   type Attempt is record
      Attempt             : Quality_Manager.Identities.Attempt_Id := 0;
      Dispatch_Id         : Text;
      Execution_Identity  : Text;
      Started_At          : Sequence_Number := 0;
      Finished_At         : Sequence_Number := 0;
      Timeout_Seconds     : Positive := 3_600;
      Outcome             : Quality_Manager.Model.Outcome_Kind := Quality_Manager.Model.No_Outcome;
   end record;

   type Lease is record
      Resource_Key : Text;
      Owner         : Text;
      Generation    : Sequence_Number := 0;
      Expires_At    : Sequence_Number := 0;
   end record;

   type Journal_Entry is record
      Operation       : Quality_Manager.Identities.Operation_Id := 0;
      Operation_Kind  : Text;
      Intent          : Text;
      State           : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
      External_Id     : Text;
      Diagnostic      : Text;
   end record;

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

   type Campaign is record
      Campaign_Id       : Text;
      Definition_Revision : Positive := 1;
      Definition_Digest : Text;
      Scope             : Text;
      Baseline          : Text;
      State             : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
      Budget            : Natural := 0;
   end record;

   type Campaign_Target is record
      Composite_Key  : Text;
      Campaign_Id    : Text;
      Project        : Quality_Manager.Identities.Project_Key;
      Indicator      : Text;
      Baseline       : Text;
      Target         : Text;
      Latest_Result  : Text;
   end record;

   type Release is record
      Release_Id       : Text;
      Project          : Quality_Manager.Identities.Project_Key;
      Candidate_Commit : Text;
      Source_Digest    : Text;
      Policy_Digest    : Text;
      Toolchain        : Text;
      Generation       : Natural := 1;
      State            : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
   end record;

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

   type Event is record
      Event_Id            : Text;
      Entity              : Text;
      Previous_State      : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
      New_State           : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
      Occurred_At         : Sequence_Number := 0;
      Cause               : Text;
      Evidence_References : Text;
   end record;
end Quality_Manager.Storage.Schema;
