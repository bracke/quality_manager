separate (Quality_Manager_Test_Suite)
procedure Test_Authorization_Policies (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Maximum : constant Quality_Manager.Policies.Policy_Set := Quality_Manager.Policies.Initial_Maximum;
   Restricted : Quality_Manager.Policies.Policy_Set := Maximum;
   Effective  : Quality_Manager.Policies.Policy_Set;
   Risk       : Quality_Manager.Policies.Risk_Decision;
   Result     : Quality_Manager.Results.Operation_Result;
   Project    : constant Quality_Manager.Identities.Project_Key :=
     (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
   Approval   : constant Quality_Manager.Storage.Schema.Approval :=
     (Approval_Id => To_Unbounded_String ("approval-1"), Project => Project,
      Plan_Id => To_Unbounded_String ("plan-1"), Plan_Revision => 2,
      Content_Digest => To_Unbounded_String ("content-1"),
      Authorized_Action => To_Unbounded_String ("publish"),
      Policy_Digest => To_Unbounded_String ("policy-1"), Approver => To_Unbounded_String ("human"),
      Created_At => 1, Expires_At => 100);
begin
   Restricted.Permissions (Quality_Manager.Policies.Execute_Isolated_Changes) :=
     Quality_Manager.Policies.Denied;
   Restricted.Digest := To_Unbounded_String ("project-policy");
   Effective := Quality_Manager.Policies.Intersect (Maximum, Restricted);
   Assert
     (Effective.Permissions (Quality_Manager.Policies.Execute_Isolated_Changes)
        = Quality_Manager.Policies.Denied,
      "lower policy layers cannot expand coordinator authorization");
   Assert
     (not Quality_Manager.Policies.Permits_Automatically
        (Maximum, Quality_Manager.Policies.Approve_Improve_Plan),
      "Improve plan approval requires explicit authorization");
   Risk := Quality_Manager.Policies.Classify
     ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
       Public_API_Change => False, Build_Or_Release_Change => False,
       Required_Checks_Available => False, Prior_Failed_Attempts => 0, Scope_Known => True));
   Assert (Risk.Requires_Review and then Risk.Level = Quality_Manager.Model.High_Risk,
           "unavailable checks fail closed into human review");
   Risk := Quality_Manager.Policies.Classify
     ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
       Public_API_Change => False, Build_Or_Release_Change => False,
       Required_Checks_Available => True, Prior_Failed_Attempts => 0, Scope_Known => False));
   Assert (Risk.Requires_Review, "unknown scope requires review");
   Risk := Quality_Manager.Policies.Classify
     ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => True,
       Public_API_Change => False, Build_Or_Release_Change => False,
       Required_Checks_Available => True, Prior_Failed_Attempts => 0, Scope_Known => True));
   Assert (Risk.Level = Quality_Manager.Model.Critical_Risk, "security changes are critical risk");
   Risk := Quality_Manager.Policies.Classify
     ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
       Public_API_Change => True, Build_Or_Release_Change => False,
       Required_Checks_Available => True, Prior_Failed_Attempts => 0, Scope_Known => True));
   Assert (Risk.Requires_Review, "public API changes require review");
   Risk := Quality_Manager.Policies.Classify
     ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
       Public_API_Change => False, Build_Or_Release_Change => False,
       Required_Checks_Available => True, Prior_Failed_Attempts => 1, Scope_Known => True));
   Assert (Risk.Requires_Review, "prior failures require review");
   Risk := Quality_Manager.Policies.Classify
     ((Declared_Risk => Quality_Manager.Model.Low_Risk, Security_Sensitive => False,
       Public_API_Change => False, Build_Or_Release_Change => False,
       Required_Checks_Available => True, Prior_Failed_Attempts => 0, Scope_Known => True));
   Assert (not Risk.Requires_Review, "known low-risk work may proceed automatically");
   Quality_Manager.Policies.Validate_Approval
     (Approval, Project, "plan-1", 2, "content-1", "publish", "policy-1", 50, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "exact unexpired approval is accepted");
   Quality_Manager.Policies.Validate_Approval
     (Approval, Project, "plan-1", 3, "content-1", "publish", "policy-1", 50, Result);
   Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
           "approval cannot authorize another plan revision");
   Quality_Manager.Policies.Validate_Approval
     (Approval, Project, "plan-1", 2, "content-1", "publish", "policy-1", 101, Result);
   Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
           "expired approval cannot authorize work");
end Test_Authorization_Policies;

