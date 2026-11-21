with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
package body Quality_Manager.Policies is
   use type Interfaces.Unsigned_64;
   use type Quality_Manager.Model.Risk_Level;

   function Initial_Maximum return Policy_Set is
      Result : Policy_Set;
   begin
      Result.Digest := To_Unbounded_String ("quality-manager-initial-maximum-v1");
      Result.Permissions (Read_Quality_Reports) := Allowed;
      Result.Permissions (Run_Quality_Check) := Allowed;
      Result.Permissions (Use_Planning_Model) := Human_Authorization;
      Result.Permissions (Approve_Improve_Plan) := Human_Authorization;
      Result.Permissions (Publish_Approved_Remediation) := Allowed;
      Result.Permissions (Execute_Isolated_Changes) := Allowed;
      Result.Permissions (Integrate_Conflict_Free_Changes) := Human_Authorization;
      Result.Permissions (Resolve_Semantic_Conflict) := Human_Authorization;
      Result.Permissions (Modify_Quality_Policy) := Human_Authorization;
      Result.Permissions (Create_Quality_Waiver) := Human_Authorization;
      Result.Permissions (Modify_Public_API) := Human_Authorization;
      Result.Permissions (Modify_Security_Policy) := Human_Authorization;
      Result.Permissions (Push_Protected_Branch) := Human_Authorization;
      Result.Permissions (Publish_Release) := Human_Authorization;
      return Result;
   end Initial_Maximum;

   function Intersect (Left, Right : Policy_Set) return Policy_Set is
      Result : Policy_Set;
   begin
      for Action in Action_Kind loop
         Result.Permissions (Action) :=
           Permission'Val
             (Integer'Max
                (Permission'Pos (Left.Permissions (Action)),
                 Permission'Pos (Right.Permissions (Action))));
      end loop;
      Result.Digest := To_Unbounded_String
        (Quality_Manager.Identities.Canonical_Digest
           ([Quality_Manager.Identities.Text_Value (To_String (Left.Digest)),
             Quality_Manager.Identities.Text_Value (To_String (Right.Digest))]));
      return Result;
   end Intersect;

   function Permits_Automatically (Policy : Policy_Set; Action : Action_Kind) return Boolean is
     (Policy.Permissions (Action) = Allowed);

   function Classify (Inputs : Risk_Inputs) return Risk_Decision is
   begin
      if not Inputs.Scope_Known then
         return
           (Level => Quality_Manager.Model.High_Risk, Requires_Review => True,
            Reason => To_Unbounded_String ("task scope is unknown"));
      elsif not Inputs.Required_Checks_Available then
         return
           (Level => Quality_Manager.Model.High_Risk, Requires_Review => True,
            Reason => To_Unbounded_String ("required checks are unavailable"));
      elsif Inputs.Security_Sensitive then
         return
           (Level => Quality_Manager.Model.Critical_Risk, Requires_Review => True,
            Reason => To_Unbounded_String ("security-sensitive change"));
      elsif Inputs.Public_API_Change or else Inputs.Build_Or_Release_Change then
         return
           (Level => Quality_Manager.Model.High_Risk, Requires_Review => True,
            Reason => To_Unbounded_String ("public API or release configuration change"));
      elsif Inputs.Prior_Failed_Attempts > 0 then
         return
           (Level => Quality_Manager.Model.High_Risk, Requires_Review => True,
            Reason => To_Unbounded_String ("task has prior failed attempts"));
      else
         return
           (Level => Inputs.Declared_Risk,
            Requires_Review => Inputs.Declared_Risk /= Quality_Manager.Model.Low_Risk,
            Reason => To_Unbounded_String ("deterministic declared risk"));
      end if;
   end Classify;

   procedure Validate_Approval
     (Approval        : Quality_Manager.Storage.Schema.Approval;
      Project         : Quality_Manager.Identities.Project_Key;
      Plan_Id         : String;
      Plan_Revision   : Positive;
      Content_Digest  : String;
      Action          : String;
      Policy_Digest   : String;
      Now             : Interfaces.Unsigned_64;
      Result          : out Quality_Manager.Results.Operation_Result) is
      use Quality_Manager.Results;
   begin
      if not Quality_Manager.Identities.Equal (Approval.Project, Project)
        or else To_String (Approval.Plan_Id) /= Plan_Id
        or else Approval.Plan_Revision /= Plan_Revision
        or else To_String (Approval.Content_Digest) /= Content_Digest
        or else To_String (Approval.Authorized_Action) /= Action
        or else To_String (Approval.Policy_Digest) /= Policy_Digest
      then
         Result := Make_Result
           (Authorization_Required, "approval does not bind the exact requested operation", "qm.policy.approval");
      elsif Approval.Expires_At > 0 and then Now > Approval.Expires_At then
         Result := Make_Result (Authorization_Required, "approval has expired", "qm.policy.approval-expired");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Approval;
end Quality_Manager.Policies;
