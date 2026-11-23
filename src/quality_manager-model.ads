--  Defines coordinator workflow, outcome, and risk states.
package Quality_Manager.Model
  with Pure
is
   --  Normalized coordinator states, outcomes, and risk levels.
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
   --  Coordinator lifecycle for a durable remediation objective.
   --  @enum Discovered Work has been identified.
   --  @enum Planning An Improve plan is being established.
   --  @enum Awaiting_Approval The exact plan revision needs authorization.
   --  @enum Publishable The approved work may be published.
   --  @enum Publishing Improve publication is in progress.
   --  @enum Published A native task mapping exists.
   --  @enum Queued The native task is ready for dispatch.
   --  @enum Executing The native task is running.
   --  @enum Awaiting_Integration Candidate changes await native integration.
   --  @enum Awaiting_Assessment Integrated changes need current measurement.
   --  @enum Verifying Independent verification is in progress.
   --  @enum Verified Every required verification gate passed.
   --  @enum Blocked A known prerequisite prevents progress.
   --  @enum Failed The workflow ended with recorded failure evidence.
   --  @enum Cancelled The workflow was cancelled.
   --  @enum Superseded Newer work replaced this objective.
   --  @enum Inconclusive Available evidence cannot establish an outcome.
   --  @enum Needs_Intervention Automatic recovery cannot proceed safely.

   type Workflow_Kind is
     (Maintenance, Campaign, Release_Qualification);
   --  Top-level workflow owning an objective.
   --  @enum Maintenance Continuous portfolio maintenance.
   --  @enum Campaign A bounded portfolio improvement campaign.
   --  @enum Release_Qualification Qualification of an exact release candidate.

   type Outcome_Kind is
     (No_Outcome,
      Satisfied,
      Unresolved,
      Regression,
      Evidence_Unavailable,
      Policy_Incompatible,
      Execution_Failed,
      Authorization_Required);
   --  Normalized workflow outcome independent of upstream process status.
   --  @enum No_Outcome No outcome has been established.
   --  @enum Satisfied The objective is independently verified.
   --  @enum Unresolved The targeted deficiency remains.
   --  @enum Regression Candidate work introduced a prohibited regression.
   --  @enum Evidence_Unavailable Required evidence is absent or incomplete.
   --  @enum Policy_Incompatible Evidence is incompatible with the effective policy.
   --  @enum Execution_Failed Native execution did not complete successfully.
   --  @enum Authorization_Required The next action requires authorization.

   type Risk_Level is
     (Low_Risk, Moderate_Risk, High_Risk, Critical_Risk);
   --  Deterministic autonomy risk classification.
   --  @enum Low_Risk Routine bounded work.
   --  @enum Moderate_Risk Work requiring additional policy checks.
   --  @enum High_Risk Work requiring explicit review by default.
   --  @enum Critical_Risk Security, release, or other critical work.
end Quality_Manager.Model;
