with Ada.Strings.Unbounded;
with Interfaces;
with Quality_Manager.Identities;
with Quality_Manager.Model;
with Quality_Manager.Results;
with Quality_Manager.Storage.Schema;

package Quality_Manager.Policies is
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

   type Permission is (Allowed, Human_Authorization, Denied);
   type Permission_Map is array (Action_Kind) of Permission;

   type Policy_Set is record
      Permissions : Permission_Map := [others => Denied];
      Digest      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Initial_Maximum return Policy_Set;
   function Intersect (Left, Right : Policy_Set) return Policy_Set;
   function Permits_Automatically (Policy : Policy_Set; Action : Action_Kind) return Boolean;

   type Risk_Inputs is record
      Declared_Risk          : Quality_Manager.Model.Risk_Level := Quality_Manager.Model.Moderate_Risk;
      Security_Sensitive     : Boolean := False;
      Public_API_Change      : Boolean := False;
      Build_Or_Release_Change : Boolean := False;
      Required_Checks_Available : Boolean := True;
      Prior_Failed_Attempts  : Natural := 0;
      Scope_Known            : Boolean := True;
   end record;

   type Risk_Decision is record
      Level           : Quality_Manager.Model.Risk_Level := Quality_Manager.Model.Moderate_Risk;
      Requires_Review : Boolean := True;
      Reason          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Classify (Inputs : Risk_Inputs) return Risk_Decision;

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
end Quality_Manager.Policies;
