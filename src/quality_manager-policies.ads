with Ada.Strings.Unbounded;
with Interfaces;
with Quality_Manager.Identities;
with Quality_Manager.Model;
with Quality_Manager.Results;
with Quality_Manager.Storage.Schema;

--  Evaluates effective authorization and deterministic risk policy.
package Quality_Manager.Policies is
   --  Public contract for this Quality Manager unit.
   type Action_Kind is
     (Read_Quality_Reports,
      Run_Quality_Check,
      Use_Planning_Model,
      Approve_Improve_Plan,
      Publish_Approved_Remediation,
      Execute_Isolated_Changes,
      Integrate_Conflict_Free_Changes,
      Resolve_Semantic_Conflict,
      Modify_Quality_Policy,
      Create_Quality_Waiver,
      Modify_Public_API,
      Modify_Security_Policy,
      Push_Protected_Branch,
      Publish_Release);
   --  Action Kind values.
   --  @enum Read_Quality_Reports Read Quality Reports.
   --  @enum Run_Quality_Check Run Quality Check.
   --  @enum Use_Planning_Model Use Planning Model.
   --  @enum Approve_Improve_Plan Approve Improve Plan.
   --  @enum Publish_Approved_Remediation Publish Approved Remediation.
   --  @enum Execute_Isolated_Changes Execute Isolated Changes.
   --  @enum Integrate_Conflict_Free_Changes Integrate Conflict Free Changes.
   --  @enum Resolve_Semantic_Conflict Resolve Semantic Conflict.
   --  @enum Modify_Quality_Policy Modify Quality Policy.
   --  @enum Create_Quality_Waiver Create Quality Waiver.
   --  @enum Modify_Public_API Modify Public API.
   --  @enum Modify_Security_Policy Modify Security Policy.
   --  @enum Push_Protected_Branch Push Protected Branch.
   --  @enum Publish_Release Publish Release.

   type Permission is (Allowed, Human_Authorization, Denied);
   --  Permission values.
   --  @enum Allowed Allowed.
   --  @enum Human_Authorization Human Authorization.
   --  @enum Denied Denied.
   type Permission_Map is array (Action_Kind) of Permission;
   --  Permission Map domain value.

   type Policy_Set is record
      Permissions : Permission_Map := [others => Denied];
      Digest      : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Policy Set record.
   --  @field Permissions Permissions.
   --  @field Digest Digest.

   function Initial_Maximum return Policy_Set;
   --  Return Initial Maximum.
   --  @return Initial Maximum result.
   function Intersect (Left, Right : Policy_Set) return Policy_Set;
   --  Return Intersect.
   --  @param Left Left.
   --  @param Right Right.
   --  @return Intersect result.
   function Permits_Automatically (Policy : Policy_Set; Action : Action_Kind) return Boolean;
   --  Return Permits Automatically.
   --  @param Policy Policy.
   --  @param Action Action.
   --  @return Permits Automatically result.

   type Risk_Inputs is record
      Declared_Risk          : Quality_Manager.Model.Risk_Level := Quality_Manager.Model.Moderate_Risk;
      Security_Sensitive     : Boolean := False;
      Public_API_Change      : Boolean := False;
      Build_Or_Release_Change : Boolean := False;
      Required_Checks_Available : Boolean := True;
      Prior_Failed_Attempts  : Natural := 0;
      Scope_Known            : Boolean := True;
   end record;
   --  Risk Inputs record.
   --  @field Declared_Risk Declared Risk.
   --  @field Security_Sensitive Security Sensitive.
   --  @field Public_API_Change Public API Change.
   --  @field Build_Or_Release_Change Build Or Release Change.
   --  @field Required_Checks_Available Required Checks Available.
   --  @field Prior_Failed_Attempts Prior Failed Attempts.
   --  @field Scope_Known Scope Known.

   type Risk_Decision is record
      Level           : Quality_Manager.Model.Risk_Level := Quality_Manager.Model.Moderate_Risk;
      Requires_Review : Boolean := True;
      Reason          : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Risk Decision record.
   --  @field Level Level.
   --  @field Requires_Review Requires Review.
   --  @field Reason Reason.

   function Classify (Inputs : Risk_Inputs) return Risk_Decision;
   --  Return Classify.
   --  @param Inputs Inputs.
   --  @return Classify result.

   procedure Validate_Approval
     (Approval        : Quality_Manager.Storage.Schema.Approval;
      Project         : Quality_Manager.Identities.Project_Key;
      Plan_Id         : String;
      Plan_Revision   : Positive;
      Content_Digest  : String;
      Action          : String;
      Policy_Digest   : String;
      Now             : Interfaces.Unsigned_64;
      Result          : out Quality_Manager.Results.Operation_Result);
   --  Perform Validate Approval.
   --  @param Approval Approval.
   --  @param Project Project.
   --  @param Plan_Id Plan Id.
   --  @param Plan_Revision Plan Revision.
   --  @param Content_Digest Content Digest.
   --  @param Action Action.
   --  @param Policy_Digest Policy Digest.
   --  @param Now Now.
   --  @param Result Result.
end Quality_Manager.Policies;
