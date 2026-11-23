separate (Quality_Manager.Dispatch)
procedure Publish_Approved
  (Store     : in out Quality_Manager.Storage.Store;
   Planner   : Quality_Manager.Integrations.Improve.Adapter;
   Work      : Quality_Manager.Storage.Schema.Work_Item;
   Approval  : Quality_Manager.Storage.Schema.Approval;
   Now       : Interfaces.Unsigned_64;
   Published : out Quality_Manager.Storage.Schema.Dispatch;
   Result    : out Operation_Result) is
   Dispatch_Id : constant String := Quality_Manager.Identities.Dispatch_Identity
     (To_String (Work.Work_Id), To_String (Work.Improve_Plan_Id),
      (if Work.Improve_Revision = 0 then 1 else Positive (Work.Improve_Revision)),
      To_String (Work.Improve_Task_Id));
   Approval_Operation : constant Quality_Manager.Identities.Operation_Id :=
     Quality_Manager.Identities.Operation_Identity ("improve-approval", To_String (Work.Work_Id));
   Publish_Operation : constant Quality_Manager.Identities.Operation_Id :=
     Quality_Manager.Identities.Operation_Identity ("improve-publication", To_String (Work.Work_Id));
   Approval_Intent : constant String := Quality_Manager.Identities.Canonical_Digest
     ([Quality_Manager.Identities.Text_Value ("improve-approval-v1"),
       Quality_Manager.Identities.Text_Value (To_String (Work.Improve_Plan_Id)),
       Quality_Manager.Identities.Number_Value (Interfaces.Unsigned_64 (Work.Improve_Revision)),
       Quality_Manager.Identities.Text_Value (To_String (Work.Improve_Content_SHA256)),
       Quality_Manager.Identities.Text_Value (To_String (Approval.Approval_Id))]);
   Publication_Intent : constant String := Quality_Manager.Identities.Canonical_Digest
     ([Quality_Manager.Identities.Text_Value ("improve-publication-v1"),
       Quality_Manager.Identities.Text_Value (Dispatch_Id),
       Quality_Manager.Identities.Text_Value (To_String (Work.Improve_Task_Id))]);
   Journal_Item : Quality_Manager.Storage.Stored_Entity;
   State : Quality_Manager.Journal.Journal_State;
   Response : Quality_Manager.Integrations.JSON_CLI.Response;
   Native_Task, Ignored_Task : Unbounded_String;

   procedure Ensure_Journal
     (Operation : Quality_Manager.Identities.Operation_Id;
      Kind, Intent, External_Id : String) is
   begin
      Read_Journal (Store, Operation, Journal_Item, State, Result);
      if Result.Kind = Not_Found then
         Quality_Manager.Storage.Prepare_Operation
           (Store, Operation, Kind, Intent, External_Id, Result);
         State := Quality_Manager.Journal.Prepared;
      elsif Result.Kind = Success
        and then not Has_Exact_Intent (Journal_Item, Intent, External_Id)
      then
         Result := Make_Result
           (Integrity_Error, "operation identity is bound to another Improve intent",
            "qm.dispatch.improve-intent");
      elsif Result.Kind = Success
        and then State in Quality_Manager.Journal.Aborted | Quality_Manager.Journal.Needs_Intervention
      then
         Result := Make_Result
           (Authorization_Required, "Improve operation is terminally blocked",
            "qm.dispatch.improve-terminal");
      end if;
   end Ensure_Journal;

   procedure Commit_Journal
     (Operation : Quality_Manager.Identities.Operation_Id;
      External_Id, Diagnostic : String) is
   begin
      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, State, Quality_Manager.Journal.Reconciling,
            External_Id, Diagnostic, Result);
         State := Quality_Manager.Journal.Reconciling;
      end if;
      if Result.Kind = Success and then State = Quality_Manager.Journal.Reconciling then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, State, Quality_Manager.Journal.Committed,
            External_Id, Diagnostic, Result);
         State := Quality_Manager.Journal.Committed;
      end if;
   end Commit_Journal;
   procedure Initialize_Output is
   begin
      Published :=
        (Dispatch_Id => Null_Unbounded_String, Work_Id => Null_Unbounded_String,
         Logical_Remediation => Null_Unbounded_String,
         Improve_Task => (Null_Unbounded_String, 1, Null_Unbounded_String),
         Native_Task_Id => Null_Unbounded_String, Authorization_Id => Null_Unbounded_String,
         State => Quality_Manager.Model.Published, Active => False);
   end Initialize_Output;

   procedure Validate_Work is
   begin
      if Work.Improve_Revision = 0 then
         Result := Make_Result
           (Invalid_Request, "publication work is incomplete or ineligible",
            "qm.dispatch.publication-work");
      elsif Length (Work.Work_Id) = 0 then
         Result := Make_Result
           (Invalid_Request, "publication work is incomplete or ineligible",
            "qm.dispatch.publication-work");
      elsif Length (Work.Improve_Plan_Id) = 0 then
         Result := Make_Result
           (Invalid_Request, "publication work is incomplete or ineligible",
            "qm.dispatch.publication-work");
      elsif Length (Work.Improve_Task_Id) = 0 then
         Result := Make_Result
           (Invalid_Request, "publication work is incomplete or ineligible",
            "qm.dispatch.publication-work");
      elsif Length (Work.Improve_Content_SHA256) = 0 then
         Result := Make_Result
           (Invalid_Request, "publication work is incomplete or ineligible",
            "qm.dispatch.publication-work");
      elsif Length (Work.Effective_Policy_Digest) = 0 then
         Result := Make_Result
           (Invalid_Request, "publication work is incomplete or ineligible",
            "qm.dispatch.publication-work");
      elsif Work.State not in Quality_Manager.Model.Awaiting_Approval |
                               Quality_Manager.Model.Publishable |
                               Quality_Manager.Model.Publishing |
                               Quality_Manager.Model.Published
      then
         Result := Make_Result
           (Invalid_Request, "publication work is incomplete or ineligible",
            "qm.dispatch.publication-work");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Work;

   procedure Validate_Approval_Record is
   begin
      Validate_Durable_Approval (Store, Approval, Result);
      if Result.Kind = Success then
         Quality_Manager.Policies.Validate_Approval
           (Approval, Work.Project, To_String (Work.Improve_Plan_Id), Positive (Work.Improve_Revision),
            To_String (Work.Improve_Content_SHA256), "publish",
            To_String (Work.Effective_Policy_Digest), Now, Result);
      end if;
   end Validate_Approval_Record;

   procedure Approve_Work is
   begin
      if Work.State /= Quality_Manager.Model.Awaiting_Approval then
         return;
      end if;
      Ensure_Journal
        (Approval_Operation, "improve-exact-approval", Approval_Intent,
         "improve-approval:" & To_String (Work.Improve_Plan_Id));
      if Result.Kind = Success and then State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Approval_Operation, State, Quality_Manager.Journal.Invoking,
            "improve-approval:" & To_String (Work.Improve_Plan_Id), "", Result);
         State := Quality_Manager.Journal.Invoking;
      end if;
      if Result.Kind = Success then
         Quality_Manager.Integrations.Improve.Approve_Exact_Revision
           (Planner, To_String (Work.Improve_Plan_Id), Positive (Work.Improve_Revision),
            To_String (Work.Improve_Content_SHA256), Response);
         Decode_Approval (Response, Work, Result);
      end if;
      if Result.Kind = Success then
         Commit_Journal
           (Approval_Operation, "improve-approval:" & To_String (Work.Improve_Plan_Id),
            "exact Improve approval confirmed");
      end if;
      if Result.Kind = Success then
         Quality_Manager.Storage.Transition_Work
           (Store, To_String (Work.Work_Id), Quality_Manager.Model.Awaiting_Approval,
            Quality_Manager.Model.Publishable, "event:" & To_String (Work.Work_Id) & ":publishable",
            "exact approval confirmed", To_String (Approval.Approval_Id), Result);
      end if;
   end Approve_Work;

   procedure Preflight_Work is
   begin
      if Work.State not in Quality_Manager.Model.Awaiting_Approval | Quality_Manager.Model.Publishable then
         return;
      end if;
      Quality_Manager.Integrations.Improve.Preflight_Publication
        (Planner, To_String (Work.Improve_Plan_Id), Positive (Work.Improve_Revision),
         To_String (Work.Improve_Task_Id), Response);
      Decode_Publication (Response, Work, True, Ignored_Task, Result);
      if Result.Kind = Success then
         Quality_Manager.Storage.Transition_Work
           (Store, To_String (Work.Work_Id), Quality_Manager.Model.Publishable,
            Quality_Manager.Model.Publishing, "event:" & To_String (Work.Work_Id) & ":publishing",
            "Improve publication preflight passed", To_String (Work.Improve_Task_Id), Result);
      end if;
   end Preflight_Work;

   procedure Publish_Work is
   begin
      Ensure_Journal
        (Publish_Operation, "improve-publication", Publication_Intent,
         "improve-publication:" & Dispatch_Id);
      if Result.Kind = Success and then State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Publish_Operation, State, Quality_Manager.Journal.Invoking,
            "improve-publication:" & Dispatch_Id, "", Result);
         State := Quality_Manager.Journal.Invoking;
      end if;
      if Result.Kind = Success then
         Quality_Manager.Integrations.Improve.Publish_Task
           (Planner, To_String (Work.Improve_Plan_Id), Positive (Work.Improve_Revision),
            To_String (Work.Improve_Task_Id), Response);
         Decode_Publication (Response, Work, False, Native_Task, Result);
      end if;
      if Result.Kind = Success then
         Commit_Journal
           (Publish_Operation, "improve-publication:" & Dispatch_Id,
            "native task mapping confirmed");
      end if;
   end Publish_Work;

   procedure Save_Publication is
   begin
      Published :=
        (Dispatch_Id => To_Unbounded_String (Dispatch_Id), Work_Id => Work.Work_Id,
         Logical_Remediation => Work.Global_Remediation,
         Improve_Task =>
           (Plan_Id => Work.Improve_Plan_Id, Revision => Positive (Work.Improve_Revision),
            Task_Id => Work.Improve_Task_Id),
         Native_Task_Id => Native_Task, Authorization_Id => Approval.Approval_Id,
         State => Quality_Manager.Model.Published, Active => True);
      Bind_Published_Task (Store, Published, Result);
      if Result.Kind = Success and then Work.State /= Quality_Manager.Model.Published then
         Quality_Manager.Storage.Transition_Work
           (Store, To_String (Work.Work_Id), Quality_Manager.Model.Publishing,
            Quality_Manager.Model.Published, "event:" & To_String (Work.Work_Id) & ":published",
            "Improve native task mapping adopted", To_String (Native_Task), Result);
      end if;
   end Save_Publication;
begin
   Initialize_Output;
   Validate_Work;
   if Result.Kind /= Success then
      return;
   end if;
   Validate_Approval_Record;
   if Result.Kind /= Success then
      return;
   end if;
   Approve_Work;
   if Result.Kind /= Success then
      return;
   end if;
   Preflight_Work;
   if Result.Kind /= Success then
      return;
   end if;
   Publish_Work;
   if Result.Kind /= Success then
      return;
   end if;
   Save_Publication;
exception
   when Constraint_Error =>
      Result := Make_Result
        (Invalid_Request, "publication identity is out of range", "qm.dispatch.publication-range");
end Publish_Approved;

