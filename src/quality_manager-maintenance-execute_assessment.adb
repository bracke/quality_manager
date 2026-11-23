separate (Quality_Manager.Maintenance)
procedure Execute_Assessment
  (Item    : in out Context;
   Work_Id : String;
   Result  : out Operation_Result) is
   Work       : Quality_Manager.Storage.Stored_Entity;
   Project    : Quality_Manager.Identities.Project_Key;
   Plan       : Assessment_Plan;
   Response   : Quality_Manager.Integrations.JSON_CLI.Response;
   Evidence   : Quality_Manager.Verification.Assessment_Evidence;
   Local      : Operation_Result;
   Selector   : Unbounded_String;
   Can_Continue : Boolean := True;

   procedure Stop_Work
     (From       : Quality_Manager.Model.Work_State;
      Target     : Quality_Manager.Model.Work_State;
      Diagnostic : String) is
   begin
      Transition
        (Item.Database.all, Work_Id, From, Target, "blocked", Diagnostic, "", Result);
   end Stop_Work;
   procedure Load_Queued_Work is
   begin
      Renew_Coordinator_Lease (Item, Result);
      if Result.Kind = Success then
         Quality_Manager.Storage.Read (Item.Database.all, Work_Id, Work, Result);
      end if;
      if Result.Kind /= Success then
         return;
      elsif Work.Kind /= Quality_Manager.Storage.Work_Item_Record then
         Result := Make_Result
           (Invalid_Request, "assessment work is not durably queued", "qm.maintenance.work-state");
      elsif To_String (Work.State) /=
        Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Queued)
      then
         Result := Make_Result
           (Invalid_Request, "assessment work is not durably queued", "qm.maintenance.work-state");
      else
         Decode_Work_Project (Work, Project, Result);
      end if;
   end Load_Queued_Work;

   procedure Plan_Assessment is
   begin
      Selector := To_Unbounded_String
        (Ada.Strings.Fixed.Trim (Positive'Image (Project.Quality_Project_Id), Ada.Strings.Both));
      Quality_Manager.Integrations.Quality.Plan_Check
        (Item.Quality, To_String (Selector), "", False, Response);
      Decode_Plan (Response, Project, Plan, Local);
      if Local.Kind /= Success then
         Stop_Work (Quality_Manager.Model.Queued, Quality_Manager.Model.Blocked, Message (Local));
         Can_Continue := False;
      else
         Transition
           (Item.Database.all, Work_Id, Quality_Manager.Model.Queued, Quality_Manager.Model.Executing,
            "executing", "authoritative assessment dispatched", "", Result);
      end if;
   end Plan_Assessment;

   function Evidence_Matches return Boolean is
   begin
      if not Evidence.Completed then
         return False;
      elsif Evidence.Project_Id /= Project.Quality_Project_Id then
         return False;
      elsif Evidence.Project_Path /= Project.Canonical_Path then
         return False;
      elsif Evidence.Source_Fingerprint /= Plan.Source_Fingerprint then
         return False;
      elsif Evidence.Policy_Fingerprint /= Plan.Policy_Fingerprint then
         return False;
      else
         return Evidence.Toolchain_Fingerprint = Plan.Toolchain_Fingerprint;
      end if;
   end Evidence_Matches;

   procedure Establish_Evidence is
   begin
      Quality_Manager.Verification.Establish_Assessment
        (Item.Database.all, Item.Quality,
         (Operation => Quality_Manager.Identities.Operation_Identity
            ("maintenance-assessment", Work_Id),
          Work_Id => To_Unbounded_String (Work_Id),
          Project => Project,
          Project_Selector => Selector,
          Profile => Null_Unbounded_String,
          Candidate_Source => Plan.Source_Fingerprint,
          Policy_Fingerprint => Plan.Policy_Fingerprint,
          Toolchain_Fingerprint => Plan.Toolchain_Fingerprint),
         Evidence, Local);
      if Local.Kind /= Success then
         Stop_Work
           (Quality_Manager.Model.Executing, Quality_Manager.Model.Needs_Intervention, Message (Local));
         Can_Continue := False;
      elsif not Evidence_Matches then
         Stop_Work
           (Quality_Manager.Model.Executing, Quality_Manager.Model.Inconclusive,
            "assessment evidence is unfinished, stale, or mismatched");
         Can_Continue := False;
      end if;
   end Establish_Evidence;

   procedure Persist_Observation is
   begin
      Quality_Manager.Storage.Records.Save
        (Item.Database.all,
         Quality_Manager.Storage.Schema.Project'
           (Key => Project,
            Enabled => True,
            Last_Assessment_Run => Evidence.Assessment_Id,
            Last_Source_Fingerprint => Evidence.Source_Fingerprint),
         Result);
      if Result.Kind = Success and then not Evidence.Complete then
         Stop_Work
           (Quality_Manager.Model.Executing, Quality_Manager.Model.Inconclusive,
            "assessment evidence is incomplete");
         Can_Continue := False;
      end if;
   end Persist_Observation;

   procedure Plan_Remediation is
   begin
      if Evidence.Violations = 0 then
         return;
      end if;
      Quality_Manager.Planning.Generate_Or_Reconcile
        (Item.Database.all, Item.Planner, Project, Positive (Evidence.Assessment_Id),
         To_String (Evidence.Source_Fingerprint), To_String (Evidence.Policy_Fingerprint),
         Quality_Manager.Model.Maintenance, Work_Id, Local);
      if Local.Kind /= Success then
         Result := Make_Result (Success);
      end if;
   end Plan_Remediation;

   procedure Finalize_Observation is
      Assessment : constant String := "assessment:" & Natural'Image (Evidence.Assessment_Id);
   begin
      Transition
        (Item.Database.all, Work_Id, Quality_Manager.Model.Executing,
         Quality_Manager.Model.Awaiting_Integration, "measured",
         "assessment completed", Assessment, Result);
      if Result.Kind = Success then
         Transition
           (Item.Database.all, Work_Id, Quality_Manager.Model.Awaiting_Integration,
            Quality_Manager.Model.Awaiting_Assessment, "integration-not-required",
            "measurement work requires no source integration", Assessment, Result);
      end if;
      if Result.Kind = Success then
         Plan_Remediation;
      end if;
      if Result.Kind = Success then
         Transition
           (Item.Database.all, Work_Id, Quality_Manager.Model.Awaiting_Assessment,
            Quality_Manager.Model.Verifying, "verifying",
            "authoritative assessment evidence adopted", Assessment, Result);
      end if;
      if Result.Kind = Success then
         Transition
           (Item.Database.all, Work_Id, Quality_Manager.Model.Verifying,
            Quality_Manager.Model.Verified, "verified",
            (if Evidence.Violations = 0
             then "quality observation is healthy"
             else "quality observation completed with actionable violations"),
            Assessment, Result);
      end if;
   end Finalize_Observation;
begin
   Load_Queued_Work;
   if Result.Kind /= Success or else not Can_Continue then
      return;
   end if;
   Plan_Assessment;
   if Result.Kind /= Success or else not Can_Continue then
      return;
   end if;
   Establish_Evidence;
   if Result.Kind /= Success or else not Can_Continue then
      return;
   end if;
   Persist_Observation;
   if Result.Kind /= Success or else not Can_Continue then
      return;
   end if;
   Finalize_Observation;
end Execute_Assessment;

