package Quality_Manager.Model
  with Pure
is
   type Work_State is
     (Discovered,
      Planning,
      Awaiting_Approval,
      Publishable,
      Publishing,
      Published,
      Queued,
      Executing,
      Awaiting_Integration,
      Awaiting_Assessment,
      Verifying,
      Verified,
      Blocked,
      Failed,
      Cancelled,
      Superseded,
      Inconclusive,
      Needs_Intervention);

   type Workflow_Kind is
     (Maintenance, Campaign, Release_Qualification);

   type Outcome_Kind is
     (No_Outcome,
      Satisfied,
      Unresolved,
      Regression,
      Evidence_Unavailable,
      Policy_Incompatible,
      Execution_Failed,
      Authorization_Required);

   type Risk_Level is
     (Low_Risk, Moderate_Risk, High_Risk, Critical_Risk);
end Quality_Manager.Model;
