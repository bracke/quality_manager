with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Journal;
with Quality_Manager.Policies;
with Quality_Manager.Storage.Decoding;
with Quality_Manager.Storage.Records;

package body Quality_Manager.Dispatch is
   use type Quality_Manager.Integrations.Runner.Execution_State;
   use type Jsonlib.Documents.Value_Kind;
   use type Interfaces.Unsigned_64;
   use type Quality_Manager.Identities.Operation_Id;
   use type Quality_Manager.Journal.Journal_State;
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Storage.Record_Kind;
   use Quality_Manager.Results;

   function Number (Operation : Quality_Manager.Identities.Operation_Id) return String is
     (Ada.Strings.Fixed.Trim
        (Quality_Manager.Identities.Operation_Id'Image (Operation), Ada.Strings.Both));

   function Operation_Name
     (Operation : Quality_Manager.Identities.Operation_Id) return String is
     ("qm-execution-" & Number (Operation));

   function Coordinator_State
     (State : Quality_Manager.Integrations.Runner.Execution_State)
      return Quality_Manager.Model.Work_State is
   begin
      case State is
         when Quality_Manager.Integrations.Runner.Not_Ready_State |
              Quality_Manager.Integrations.Runner.Blocked_State =>
            return Quality_Manager.Model.Blocked;
         when Quality_Manager.Integrations.Runner.Ready_State =>
            return Quality_Manager.Model.Queued;
         when Quality_Manager.Integrations.Runner.Executing_State =>
            return Quality_Manager.Model.Executing;
         when Quality_Manager.Integrations.Runner.Awaiting_Integration_State =>
            return Quality_Manager.Model.Awaiting_Integration;
         when Quality_Manager.Integrations.Runner.Verifying_State |
              Quality_Manager.Integrations.Runner.Completed_State =>
            return Quality_Manager.Model.Awaiting_Assessment;
         when Quality_Manager.Integrations.Runner.Failed_State =>
            return Quality_Manager.Model.Failed;
         when Quality_Manager.Integrations.Runner.Cancelled_State =>
            return Quality_Manager.Model.Cancelled;
      end case;
   end Coordinator_State;

   procedure Bind_Published_Task
     (Store    : in out Quality_Manager.Storage.Store;
      Dispatch : Quality_Manager.Storage.Schema.Dispatch;
      Result   : out Operation_Result) is
   begin
      if Length (Dispatch.Dispatch_Id) = 0
        or else Length (Dispatch.Work_Id) = 0
        or else Length (Dispatch.Logical_Remediation) = 0
        or else Length (Dispatch.Improve_Task.Plan_Id) = 0
        or else Length (Dispatch.Improve_Task.Task_Id) = 0
        or else Length (Dispatch.Native_Task_Id) = 0
      then
         Result := Make_Result
           (Invalid_Request, "published task mapping is incomplete", "qm.dispatch.mapping");
      elsif not Dispatch.Active then
         Result := Make_Result
           (Invalid_Request, "new published dispatch must be active", "qm.dispatch.inactive");
      else
         Quality_Manager.Storage.Records.Save (Store, Dispatch, Result);
      end if;
   end Bind_Published_Task;

   function Journal_Key (Operation : Quality_Manager.Identities.Operation_Id) return String is
     ("journal:" & Number (Operation));

   function Intent_For
     (Dispatch_Id : String;
      Request     : Quality_Manager.Integrations.Runner.Execution_Request) return String is
     (Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value ("model-runner-execution-v1"),
          Quality_Manager.Identities.Text_Value (Dispatch_Id),
          Quality_Manager.Identities.Text_Value (To_String (Request.Project_Path)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Task_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Expected_Task_Revision)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Expected_Project_Identity)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Expected_Source_Fingerprint)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Execution_Policy)),
          Quality_Manager.Identities.Number_Value (Interfaces.Unsigned_64 (Request.Timeout_Seconds))]));

   function Has_Exact_Intent
     (Record_Item : Quality_Manager.Storage.Stored_Entity;
      Intent      : String;
      External_Id : String) return Boolean is
      Payload : constant String := To_String (Record_Item.Payload);
   begin
      return Ada.Strings.Fixed.Index (Payload, "intent=" & Intent) > 0
        and then Ada.Strings.Fixed.Index (Payload, "external_id=" & External_Id) > 0;
   end Has_Exact_Intent;

   procedure Read_Journal
     (Store      : in out Quality_Manager.Storage.Store;
      Operation  : Quality_Manager.Identities.Operation_Id;
      Journal_Item : out Quality_Manager.Storage.Stored_Entity;
      State      : out Quality_Manager.Journal.Journal_State;
      Result     : out Operation_Result) is
   begin
      State := Quality_Manager.Journal.Prepared;
      Quality_Manager.Storage.Read (Store, Journal_Key (Operation), Journal_Item, Result);
      if Result.Kind /= Success then
         return;
      end if;
      if Journal_Item.Kind /= Quality_Manager.Storage.Journal_Record then
         Result := Make_Result (Integrity_Error, "operation key is not a journal", "qm.dispatch.journal-kind");
         return;
      end if;
      begin
         State := Quality_Manager.Journal.Journal_State'Value (To_String (Journal_Item.State));
      exception
         when Constraint_Error =>
            Result := Make_Result
              (Incompatible_Contract, "unknown journal state", "qm.dispatch.journal-state");
      end;
   end Read_Journal;

   function String_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Unbounded_String) return Boolean is
      Node : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.String_Value
      then
         Value := Null_Unbounded_String;
         return False;
      end if;
      Value := To_Unbounded_String (Document.As_String (Node));
      return True;
   end String_Field;

   function Natural_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Natural) return Boolean is
      Node   : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
      Number : Long_Long_Integer;
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.Integer_Value
      then
         Value := 0;
         return False;
      end if;
      Number := Document.As_Integer (Node);
      if Number not in 0 .. Long_Long_Integer (Natural'Last) then
         Value := 0;
         return False;
      end if;
      Value := Natural (Number);
      return True;
   end Natural_Field;

   function Boolean_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Boolean) return Boolean is
      Node : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.Boolean_Value
      then
         Value := False;
         return False;
      end if;
      Value := Document.As_Boolean (Node);
      return True;
   end Boolean_Field;

   procedure Decode_Approval
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Work     : Quality_Manager.Storage.Schema.Work_Item;
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
      Version, Revision : Natural;
      Command, Plan_Id, Content : Unbounded_String;
      Approved : Boolean;
   begin
      if Response.Status.Kind /= Success then
         Result := Response.Status;
         return;
      end if;
      Jsonlib.Parsers.Parse
        (To_String (Response.Document), Document, Error,
         (Max_Depth => 16, Max_Length => 1_048_576,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Incompatible_Contract, "invalid Improve approval JSON", "qm.dispatch.approval-json");
         return;
      end if;
      declare
         Root : constant Jsonlib.Documents.Node := Document.Root;
         Data : constant Jsonlib.Documents.Node := Document.Member (Root, "data");
      begin
         if not Natural_Field (Document, Root, "schema_version", Version)
           or else Version /= 2
           or else not String_Field (Document, Root, "command", Command)
           or else To_String (Command) /= "plan approve"
           or else not Jsonlib.Documents.Is_Present (Data)
           or else Document.Kind (Data) /= Jsonlib.Documents.Object_Value
           or else not String_Field (Document, Data, "plan_id", Plan_Id)
           or else Plan_Id /= Work.Improve_Plan_Id
           or else not Natural_Field (Document, Data, "revision", Revision)
           or else Revision /= Work.Improve_Revision
           or else not String_Field (Document, Data, "content_sha256", Content)
           or else Content /= Work.Improve_Content_SHA256
           or else not Boolean_Field (Document, Data, "approved", Approved)
           or else not Approved
         then
            Result := Make_Result
              (Incompatible_Contract, "Improve approval does not match authorized work",
               "qm.dispatch.approval-contract");
            return;
         end if;
      end;
      Result := Make_Result (Success);
   end Decode_Approval;

   procedure Decode_Publication
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Work     : Quality_Manager.Storage.Schema.Work_Item;
      Dry_Run  : Boolean;
      Native_Task : out Unbounded_String;
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
      Version, Revision : Natural;
      Command, Plan_Id, Content : Unbounded_String;
      Actual_Dry_Run : Boolean;
      Matches : Natural := 0;
   begin
      Native_Task := Null_Unbounded_String;
      if Response.Status.Kind /= Success then
         Result := Response.Status;
         return;
      end if;
      Jsonlib.Parsers.Parse
        (To_String (Response.Document), Document, Error,
         (Max_Depth => 32, Max_Length => 4 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Incompatible_Contract, "invalid Improve publication JSON", "qm.dispatch.publication-json");
         return;
      end if;
      declare
         Root  : constant Jsonlib.Documents.Node := Document.Root;
         Data  : constant Jsonlib.Documents.Node := Document.Member (Root, "data");
         Tasks : Jsonlib.Documents.Node;
      begin
         if not Natural_Field (Document, Root, "schema_version", Version)
           or else Version /= 2
           or else not String_Field (Document, Root, "command", Command)
           or else To_String (Command) /= "apply"
           or else not Jsonlib.Documents.Is_Present (Data)
           or else Document.Kind (Data) /= Jsonlib.Documents.Object_Value
           or else not String_Field (Document, Data, "plan_id", Plan_Id)
           or else Plan_Id /= Work.Improve_Plan_Id
           or else not Natural_Field (Document, Data, "revision", Revision)
           or else Revision /= Work.Improve_Revision
           or else not String_Field (Document, Data, "content_sha256", Content)
           or else Content /= Work.Improve_Content_SHA256
           or else not Boolean_Field (Document, Data, "dry_run", Actual_Dry_Run)
           or else Actual_Dry_Run /= Dry_Run
         then
            Result := Make_Result
              (Incompatible_Contract, "Improve publication identity is mismatched",
               "qm.dispatch.publication-contract");
            return;
         end if;
         Tasks := Document.Member (Data, "tasks");
         if not Jsonlib.Documents.Is_Present (Tasks)
           or else Document.Kind (Tasks) /= Jsonlib.Documents.Array_Value
           or else Document.Length (Tasks) = 0
           or else Document.Length (Tasks) > 100
         then
            Result := Make_Result
              (Incompatible_Contract, "Improve publication task mapping is incomplete",
               "qm.dispatch.publication-tasks");
            return;
         end if;
         for Index in 1 .. Document.Length (Tasks) loop
            declare
               Node : constant Jsonlib.Documents.Node := Document.Element (Tasks, Index);
               Improve_Task, Harness_Task : Unbounded_String;
            begin
               if Document.Kind (Node) /= Jsonlib.Documents.Object_Value
                 or else not String_Field (Document, Node, "improve_task_id", Improve_Task)
                 or else not String_Field (Document, Node, "harness_task_id", Harness_Task)
               then
                  Result := Make_Result
                    (Incompatible_Contract, "Improve publication mapping is invalid",
                     "qm.dispatch.publication-mapping");
                  return;
               end if;
               if Improve_Task = Work.Improve_Task_Id then
                  Matches := Matches + 1;
                  Native_Task := Harness_Task;
               end if;
            end;
         end loop;
      end;
      if Matches /= 1 or else Length (Native_Task) = 0 then
         Result := Make_Result
           (Incompatible_Contract, "Improve did not return one exact native task mapping",
            "qm.dispatch.publication-selection");
      else
         Result := Make_Result (Success);
      end if;
   end Decode_Publication;

   procedure Validate_Durable_Approval
     (Store    : in out Quality_Manager.Storage.Store;
      Approval : Quality_Manager.Storage.Schema.Approval;
      Result   : out Operation_Result) is
      Item : Quality_Manager.Storage.Stored_Entity;
      Document : Jsonlib.Documents.Document;
      Error : Jsonlib.Errors.Error_Info;
      Plan_Id, Content, Action, Policy, Approver : Unbounded_String;
      Database_Id, Path : Unbounded_String;
      Revision, Project_Id : Natural;
      Created, Expires : Interfaces.Unsigned_64 := 0;

      function Unsigned_Field
        (Parent : Jsonlib.Documents.Node; Name : String;
         Value : out Interfaces.Unsigned_64) return Boolean is
         Node : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
         Number : Long_Long_Integer;
      begin
         if not Jsonlib.Documents.Is_Present (Node)
           or else Document.Kind (Node) /= Jsonlib.Documents.Integer_Value
         then
            Value := 0;
            return False;
         end if;
         Number := Document.As_Integer (Node);
         if Number < 0 then
            Value := 0;
            return False;
         end if;
         Value := Interfaces.Unsigned_64 (Number);
         return True;
      end Unsigned_Field;
   begin
      Quality_Manager.Storage.Read
        (Store, "approval:" & To_String (Approval.Approval_Id), Item, Result);
      if Result.Kind /= Success then
         if Result.Kind = Not_Found then
            Result := Make_Result
              (Authorization_Required, "approval is not durable", "qm.dispatch.approval-missing");
         end if;
         return;
      elsif Item.Kind /= Quality_Manager.Storage.Approval_Record
        or else To_String (Item.State) /= "APPROVED"
      then
         Result := Make_Result
           (Integrity_Error, "approval storage record is invalid", "qm.dispatch.approval-record");
         return;
      end if;
      Jsonlib.Parsers.Parse
        (To_String (Item.Payload), Document, Error,
         (Max_Depth => 16, Max_Length => 1_048_576,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Integrity_Error, "durable approval is invalid JSON", "qm.dispatch.approval-storage-json");
         return;
      end if;
      declare
         Root : constant Jsonlib.Documents.Node := Document.Root;
         Project : constant Jsonlib.Documents.Node := Document.Member (Root, "project");
      begin
         if Document.Kind (Root) /= Jsonlib.Documents.Object_Value
           or else not Jsonlib.Documents.Is_Present (Project)
           or else Document.Kind (Project) /= Jsonlib.Documents.Object_Value
           or else not String_Field (Document, Project, "quality_database_id", Database_Id)
           or else Database_Id /= Approval.Project.Quality_Database_Id
           or else not Natural_Field (Document, Project, "quality_project_id", Project_Id)
           or else Project_Id /= Approval.Project.Quality_Project_Id
           or else not String_Field (Document, Project, "canonical_path", Path)
           or else Path /= Approval.Project.Canonical_Path
           or else not String_Field (Document, Root, "plan_id", Plan_Id)
           or else Plan_Id /= Approval.Plan_Id
           or else not Natural_Field (Document, Root, "plan_revision", Revision)
           or else Revision /= Approval.Plan_Revision
           or else not String_Field (Document, Root, "content_digest", Content)
           or else Content /= Approval.Content_Digest
           or else not String_Field (Document, Root, "action", Action)
           or else Action /= Approval.Authorized_Action
           or else not String_Field (Document, Root, "policy_digest", Policy)
           or else Policy /= Approval.Policy_Digest
           or else not String_Field (Document, Root, "approver", Approver)
           or else Approver /= Approval.Approver
           or else not Unsigned_Field (Root, "created_at", Created)
           or else Created /= Approval.Created_At
           or else not Unsigned_Field (Root, "expires_at", Expires)
           or else Expires /= Approval.Expires_At
         then
            Result := Make_Result
              (Integrity_Error, "durable approval does not match the supplied authorization",
               "qm.dispatch.approval-storage-mismatch");
            return;
         end if;
      end;
      Result := Make_Result (Success);
   end Validate_Durable_Approval;

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
   begin
      Published :=
        (Dispatch_Id => Null_Unbounded_String, Work_Id => Null_Unbounded_String,
         Logical_Remediation => Null_Unbounded_String,
         Improve_Task => (Null_Unbounded_String, 1, Null_Unbounded_String),
         Native_Task_Id => Null_Unbounded_String, Authorization_Id => Null_Unbounded_String,
         State => Quality_Manager.Model.Published, Active => False);
      if Work.Improve_Revision = 0
        or else Length (Work.Work_Id) = 0
        or else Length (Work.Improve_Plan_Id) = 0
        or else Length (Work.Improve_Task_Id) = 0
        or else Length (Work.Improve_Content_SHA256) = 0
        or else Length (Work.Effective_Policy_Digest) = 0
        or else Work.State not in Quality_Manager.Model.Awaiting_Approval |
                                  Quality_Manager.Model.Publishable |
                                  Quality_Manager.Model.Publishing |
                                  Quality_Manager.Model.Published
      then
         Result := Make_Result
           (Invalid_Request, "publication work is incomplete or ineligible", "qm.dispatch.publication-work");
         return;
      end if;
      Validate_Durable_Approval (Store, Approval, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Quality_Manager.Policies.Validate_Approval
        (Approval, Work.Project, To_String (Work.Improve_Plan_Id), Positive (Work.Improve_Revision),
         To_String (Work.Improve_Content_SHA256), "publish", To_String (Work.Effective_Policy_Digest), Now, Result);
      if Result.Kind /= Success then
         return;
      end if;

      if Work.State = Quality_Manager.Model.Awaiting_Approval then
         Ensure_Journal
           (Approval_Operation, "improve-exact-approval", Approval_Intent,
            "improve-approval:" & To_String (Work.Improve_Plan_Id));
         if Result.Kind /= Success then return; end if;
         if State = Quality_Manager.Journal.Prepared then
            Quality_Manager.Storage.Advance_Operation
              (Store, Approval_Operation, State, Quality_Manager.Journal.Invoking,
               "improve-approval:" & To_String (Work.Improve_Plan_Id), "", Result);
            State := Quality_Manager.Journal.Invoking;
         end if;
         if Result.Kind /= Success then return; end if;
         Quality_Manager.Integrations.Improve.Approve_Exact_Revision
           (Planner, To_String (Work.Improve_Plan_Id), Positive (Work.Improve_Revision),
            To_String (Work.Improve_Content_SHA256), Response);
         Decode_Approval (Response, Work, Result);
         if Result.Kind /= Success then return; end if;
         Commit_Journal
           (Approval_Operation, "improve-approval:" & To_String (Work.Improve_Plan_Id),
            "exact Improve approval confirmed");
         if Result.Kind /= Success then return; end if;
         Quality_Manager.Storage.Transition_Work
           (Store, To_String (Work.Work_Id), Quality_Manager.Model.Awaiting_Approval,
            Quality_Manager.Model.Publishable, "event:" & To_String (Work.Work_Id) & ":publishable",
            "exact approval confirmed", To_String (Approval.Approval_Id), Result);
         if Result.Kind /= Success then return; end if;
      end if;

      if Work.State in Quality_Manager.Model.Awaiting_Approval | Quality_Manager.Model.Publishable then
         Quality_Manager.Integrations.Improve.Preflight_Publication
           (Planner, To_String (Work.Improve_Plan_Id), Positive (Work.Improve_Revision),
            To_String (Work.Improve_Task_Id), Response);
         Decode_Publication (Response, Work, True, Ignored_Task, Result);
         if Result.Kind /= Success then return; end if;
         Quality_Manager.Storage.Transition_Work
           (Store, To_String (Work.Work_Id), Quality_Manager.Model.Publishable,
            Quality_Manager.Model.Publishing, "event:" & To_String (Work.Work_Id) & ":publishing",
            "Improve publication preflight passed", To_String (Work.Improve_Task_Id), Result);
         if Result.Kind /= Success then return; end if;
      end if;

      Ensure_Journal
        (Publish_Operation, "improve-publication", Publication_Intent,
         "improve-publication:" & Dispatch_Id);
      if Result.Kind /= Success then return; end if;
      if State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Publish_Operation, State, Quality_Manager.Journal.Invoking,
            "improve-publication:" & Dispatch_Id, "", Result);
         State := Quality_Manager.Journal.Invoking;
      end if;
      if Result.Kind /= Success then return; end if;
      Quality_Manager.Integrations.Improve.Publish_Task
        (Planner, To_String (Work.Improve_Plan_Id), Positive (Work.Improve_Revision),
         To_String (Work.Improve_Task_Id), Response);
      Decode_Publication (Response, Work, False, Native_Task, Result);
      if Result.Kind /= Success then return; end if;
      Commit_Journal
        (Publish_Operation, "improve-publication:" & Dispatch_Id,
         "native task mapping confirmed");
      if Result.Kind /= Success then return; end if;
      Published :=
        (Dispatch_Id => To_Unbounded_String (Dispatch_Id), Work_Id => Work.Work_Id,
         Logical_Remediation => Work.Global_Remediation,
         Improve_Task =>
           (Plan_Id => Work.Improve_Plan_Id, Revision => Positive (Work.Improve_Revision),
            Task_Id => Work.Improve_Task_Id),
         Native_Task_Id => Native_Task, Authorization_Id => Approval.Approval_Id,
         State => Quality_Manager.Model.Published, Active => True);
      Bind_Published_Task (Store, Published, Result);
      if Result.Kind /= Success then return; end if;
      if Work.State /= Quality_Manager.Model.Published then
         Quality_Manager.Storage.Transition_Work
           (Store, To_String (Work.Work_Id), Quality_Manager.Model.Publishing,
            Quality_Manager.Model.Published, "event:" & To_String (Work.Work_Id) & ":published",
            "Improve native task mapping adopted", To_String (Native_Task), Result);
      end if;
   exception
      when Constraint_Error =>
         Result := Make_Result
           (Invalid_Request, "publication identity is out of range", "qm.dispatch.publication-range");
   end Publish_Approved;

   procedure Mark_Intervention
     (Store       : in out Quality_Manager.Storage.Store;
      Operation   : Quality_Manager.Identities.Operation_Id;
      State       : Quality_Manager.Journal.Journal_State;
      External_Id : String;
      Diagnostic  : String) is
      Ignored : Operation_Result;
   begin
      if State in Quality_Manager.Journal.Prepared |
                  Quality_Manager.Journal.Invoking |
                  Quality_Manager.Journal.Reconciling
      then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, State, Quality_Manager.Journal.Needs_Intervention,
            External_Id, Diagnostic, Ignored);
      end if;
   end Mark_Intervention;

   procedure Complete_Attempt
     (Store       : in out Quality_Manager.Storage.Store;
      Operation   : Quality_Manager.Identities.Operation_Id;
      Dispatch_Id : String;
      Request     : Quality_Manager.Integrations.Runner.Execution_Request;
      Snapshot    : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result      : out Operation_Result) is
      Outcome : Quality_Manager.Model.Outcome_Kind;
      Attempt : Quality_Manager.Storage.Schema.Attempt;
   begin
      case Snapshot.State is
         when Quality_Manager.Integrations.Runner.Awaiting_Integration_State |
              Quality_Manager.Integrations.Runner.Verifying_State |
              Quality_Manager.Integrations.Runner.Completed_State =>
            Outcome := Quality_Manager.Model.Satisfied;
         when Quality_Manager.Integrations.Runner.Cancelled_State =>
            Outcome := Quality_Manager.Model.Authorization_Required;
         when Quality_Manager.Integrations.Runner.Failed_State =>
            Outcome := Quality_Manager.Model.Execution_Failed;
         when others =>
            Outcome := Quality_Manager.Model.Unresolved;
      end case;
      Attempt :=
        (Attempt           => Quality_Manager.Identities.Attempt_Id (Operation),
         Dispatch_Id       => To_Unbounded_String (Dispatch_Id),
         Execution_Identity => To_Unbounded_String (Operation_Name (Operation)),
         Started_At        => 0,
         Finished_At       => 0,
         Timeout_Seconds   => Request.Timeout_Seconds,
         Outcome           => Outcome);
      Quality_Manager.Storage.Records.Save (Store, Attempt, Result);
   end Complete_Attempt;

   procedure Execute_Or_Reconcile
     (Store                     : in out Quality_Manager.Storage.Store;
      Runner                    : Quality_Manager.Integrations.Runner.Adapter;
      Operation                 : Quality_Manager.Identities.Operation_Id;
      Dispatch_Id               : String;
      Project_Resource          : String;
      Lease_Owner               : String;
      Expected_Lease_Generation : Interfaces.Unsigned_64;
      New_Lease_Generation      : Interfaces.Unsigned_64;
      Lease_Expires_At          : Interfaces.Unsigned_64;
      Request                   : Quality_Manager.Integrations.Runner.Execution_Request;
      Snapshot                  : out Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result                    : out Operation_Result) is
      Journal_Item : Quality_Manager.Storage.Stored_Entity;
      State       : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
      Response    : Quality_Manager.Integrations.JSON_CLI.Response;
      Checked     : Operation_Result;
      External_Id : constant String := Operation_Name (Operation);
      Intent      : constant String := Intent_For (Dispatch_Id, Request);
   begin
      Snapshot := (others => <>);
      if Operation = 0
        or else Dispatch_Id = ""
        or else Project_Resource = ""
        or else Lease_Owner = ""
      then
         Result := Make_Result
           (Invalid_Request, "execution coordination identity is incomplete", "qm.dispatch.identity");
         return;
      elsif To_String (Request.Operation_Id) /= External_Id then
         Result := Make_Result
           (Invalid_Request, "external operation identity does not match journal identity", "qm.dispatch.operation");
         return;
      end if;

      Read_Journal (Store, Operation, Journal_Item, State, Result);
      if Result.Kind = Success then
         if not Has_Exact_Intent (Journal_Item, Intent, External_Id) then
            Result := Make_Result
              (Integrity_Error, "operation identity is bound to different execution intent", "qm.dispatch.intent");
            return;
         end if;
      elsif Result.Kind = Not_Found then
         Quality_Manager.Storage.Acquire_Lease
           (Store, Project_Resource, Lease_Owner, Expected_Lease_Generation,
            New_Lease_Generation, Lease_Expires_At, Result);
         if Result.Kind /= Success then
            return;
         end if;
         Quality_Manager.Storage.Prepare_Operation
           (Store, Operation, "model-runner-execution", Intent, External_Id, Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Prepared;
      else
         return;
      end if;

      if State = Quality_Manager.Journal.Aborted then
         Result := Make_Result (Negative_Result, "native operation was aborted", "qm.dispatch.aborted");
         return;
      elsif State = Quality_Manager.Journal.Needs_Intervention then
         Result := Make_Result
           (Authorization_Required, "native operation requires intervention", "qm.dispatch.intervention");
         return;
      elsif State = Quality_Manager.Journal.Committed then
         Quality_Manager.Integrations.Runner.Status
           (Runner, To_String (Request.Project_Path), External_Id, Response);
      elsif State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
            External_Id, "", Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Invoking;
         Quality_Manager.Integrations.Runner.Execute (Runner, Request, Response);
      elsif State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Integrations.Runner.Status
           (Runner, To_String (Request.Project_Path), External_Id, Response);
         if Response.Status.Kind = Not_Found then
            --  Authoritative lookup proved that the previous invocation did
            --  not create an operation. The same durable ID is safe to use.
            Quality_Manager.Integrations.Runner.Execute (Runner, Request, Response);
         end if;
      else
         Quality_Manager.Integrations.Runner.Status
           (Runner, To_String (Request.Project_Path), External_Id, Response);
      end if;
      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Checked);
      if Checked.Kind /= Success then
         if Checked.Kind in Authorization_Required | Integrity_Error | Incompatible_Contract | Stale_Evidence then
            Mark_Intervention (Store, Operation, State, External_Id, Message (Checked));
         end if;
         Result := Checked;
         return;
      end if;
      Quality_Manager.Integrations.Runner.Validate_Execution (Snapshot, Request, Checked);
      if Checked.Kind /= Success then
         Mark_Intervention (Store, Operation, State, External_Id, Message (Checked));
         Result := Checked;
         return;
      end if;

      if Snapshot.State = Quality_Manager.Integrations.Runner.Executing_State then
         Result := Make_Result (Not_Ready, "native execution is still running", "qm.dispatch.executing");
         return;
      end if;
      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
            External_Id, To_String (Snapshot.Audit_Reference), Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Reconciling;
      end if;
      if State = Quality_Manager.Journal.Reconciling then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, Quality_Manager.Journal.Reconciling, Quality_Manager.Journal.Committed,
            External_Id, To_String (Snapshot.Native_Result), Result);
         if Result.Kind /= Success then
            return;
         end if;
      end if;

      Complete_Attempt (Store, Operation, Dispatch_Id, Request, Snapshot, Result);
      if Result.Kind /= Success then
         return;
      end if;
      case Snapshot.State is
         when Quality_Manager.Integrations.Runner.Awaiting_Integration_State |
              Quality_Manager.Integrations.Runner.Verifying_State |
              Quality_Manager.Integrations.Runner.Completed_State =>
            Result := Make_Result (Success);
         when Quality_Manager.Integrations.Runner.Cancelled_State =>
            Result := Make_Result (Interrupted, "native execution was cancelled", "qm.dispatch.cancelled");
         when others =>
            Result := Make_Result (Negative_Result, "native execution did not complete", "qm.dispatch.negative");
      end case;
   end Execute_Or_Reconcile;

   procedure Queue_Persisted
     (Store   : in out Quality_Manager.Storage.Store;
      Runner  : Quality_Manager.Integrations.Runner.Adapter;
      Work_Id : String;
      Result  : out Operation_Result) is
      Work      : Quality_Manager.Storage.Schema.Work_Item;
      Mapping   : Quality_Manager.Storage.Schema.Dispatch;
      Snapshot  : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Response  : Quality_Manager.Integrations.JSON_CLI.Response;
   begin
      Quality_Manager.Storage.Decoding.Read_Work (Store, Work_Id, Work, Result);
      if Result.Kind /= Success then
         return;
      elsif Work.State not in Quality_Manager.Model.Published | Quality_Manager.Model.Queued then
         Result := Make_Result
           (Not_Ready, "published remediation is not queueable", "qm.dispatch.queue-state");
         return;
      elsif Length (Work.Planned_Source_Fingerprint) = 0 then
         Result := Make_Result
           (Stale_Evidence, "remediation has no assessed source fingerprint", "qm.dispatch.source-missing");
         return;
      end if;
      Quality_Manager.Storage.Decoding.Read_Active_Dispatch
        (Store, To_String (Work.Global_Remediation), Mapping, Result);
      if Result.Kind /= Success then
         return;
      elsif Mapping.Work_Id /= Work.Work_Id
        or else Mapping.Improve_Task.Plan_Id /= Work.Improve_Plan_Id
        or else Natural (Mapping.Improve_Task.Revision) /= Work.Improve_Revision
        or else Mapping.Improve_Task.Task_Id /= Work.Improve_Task_Id
      then
         Result := Make_Result
           (Integrity_Error, "published dispatch does not match persisted remediation", "qm.dispatch.mapping-drift");
         return;
      end if;
      Quality_Manager.Integrations.Runner.Inspect
        (Runner, To_String (Work.Project.Canonical_Path), To_String (Mapping.Native_Task_Id), Response);
      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Result);
      if Result.Kind /= Success then
         return;
      elsif Snapshot.Task_Id /= Mapping.Native_Task_Id then
         Result := Make_Result
           (Integrity_Error, "inspected native task does not match publication", "qm.dispatch.native-task");
         return;
      elsif Snapshot.Source_Fingerprint /= Work.Planned_Source_Fingerprint then
         Result := Make_Result
           (Stale_Evidence, "native project source changed after planning", "qm.dispatch.source-drift");
         return;
      elsif not Snapshot.Ready
        or else Snapshot.State /= Quality_Manager.Integrations.Runner.Ready_State
      then
         Result := Make_Result
           (Not_Ready, "published native task is not ready", "qm.dispatch.native-not-ready");
         return;
      end if;
      if Work.State = Quality_Manager.Model.Published then
         Quality_Manager.Storage.Transition_Work
           (Store, Work_Id, Quality_Manager.Model.Published, Quality_Manager.Model.Queued,
            "event:" & Work_Id & ":native:queued", "native task readiness confirmed",
            To_String (Mapping.Native_Task_Id), Result);
      else
         Result := Make_Result (Success);
      end if;
   end Queue_Persisted;

   procedure Execute_Persisted
     (Store            : in out Quality_Manager.Storage.Store;
      Runner           : Quality_Manager.Integrations.Runner.Adapter;
      Work_Id          : String;
      Lease_Owner      : String;
      Now              : Interfaces.Unsigned_64;
      Lease_Expires_At : Interfaces.Unsigned_64;
      Timeout_Seconds  : Positive;
      Snapshot         : out Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result           : out Operation_Result) is
      Work       : Quality_Manager.Storage.Schema.Work_Item;
      Mapping    : Quality_Manager.Storage.Schema.Dispatch;
      Inspected  : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Response   : Quality_Manager.Integrations.JSON_CLI.Response;
      Operation  : Quality_Manager.Identities.Operation_Id;
      Request    : Quality_Manager.Integrations.Runner.Execution_Request;
      Lease      : Quality_Manager.Storage.Stored_Entity;
      Expected   : Interfaces.Unsigned_64 := 0;
      Resource   : Unbounded_String;
      Current    : Quality_Manager.Model.Work_State;

      procedure Move_To
        (Target : Quality_Manager.Model.Work_State;
         Phase  : String;
         Cause  : String;
         Evidence : String := "") is
      begin
         if Current = Target then
            Result := Make_Result (Success);
            return;
         end if;
         Quality_Manager.Storage.Transition_Work
           (Store, Work_Id, Current, Target,
            "event:" & Work_Id & ":native:" & Phase,
            Cause, Evidence, Result);
         if Result.Kind = Success then
            Current := Target;
         end if;
      end Move_To;

      function Lease_Available return Boolean is
         Expires : Interfaces.Unsigned_64;
      begin
         Quality_Manager.Storage.Read
           (Store, "lease:" & To_String (Resource), Lease, Result);
         if Result.Kind = Not_Found then
            Result := Make_Result (Success);
            Expected := 0;
            return True;
         elsif Result.Kind /= Success then
            return False;
         elsif Lease.Kind /= Quality_Manager.Storage.Lease_Record then
            Result := Make_Result
              (Integrity_Error, "project execution lease has the wrong record kind", "qm.dispatch.lease-kind");
            return False;
         end if;
         Expected := Lease.Generation;
         Expires := Interfaces.Unsigned_64'Value
           (Ada.Strings.Fixed.Trim (To_String (Lease.Payload), Ada.Strings.Both));
         if To_String (Lease.State) /= Lease_Owner and then Expires > Now then
            Result := Make_Result
              (Not_Ready, "another coordinator owns the project execution lease", "qm.dispatch.lease-owned");
            return False;
         end if;
         Result := Make_Result (Success);
         return True;
      exception
         when Constraint_Error =>
            Result := Make_Result
              (Integrity_Error, "project execution lease is malformed", "qm.dispatch.lease-value");
            return False;
      end Lease_Available;
   begin
      Snapshot := (others => <>);
      if Work_Id = "" or else Lease_Owner = "" or else Lease_Expires_At <= Now then
         Result := Make_Result
           (Invalid_Request, "persisted execution coordination is incomplete", "qm.dispatch.persisted-identity");
         return;
      end if;
      Quality_Manager.Storage.Decoding.Read_Work (Store, Work_Id, Work, Result);
      if Result.Kind /= Success then
         return;
      elsif Work.State not in Quality_Manager.Model.Queued |
                               Quality_Manager.Model.Executing
      then
         Result := Make_Result
           (Not_Ready, "persisted remediation is not executable", "qm.dispatch.persisted-state");
         return;
      elsif Length (Work.Planned_Source_Fingerprint) = 0 then
         Result := Make_Result
           (Stale_Evidence, "remediation has no assessed source fingerprint", "qm.dispatch.source-missing");
         return;
      end if;
      Current := Work.State;
      Quality_Manager.Storage.Decoding.Read_Active_Dispatch
        (Store, To_String (Work.Global_Remediation), Mapping, Result);
      if Result.Kind /= Success then
         return;
      elsif Mapping.Work_Id /= Work.Work_Id
        or else Mapping.Improve_Task.Plan_Id /= Work.Improve_Plan_Id
        or else Natural (Mapping.Improve_Task.Revision) /= Work.Improve_Revision
        or else Mapping.Improve_Task.Task_Id /= Work.Improve_Task_Id
      then
         Result := Make_Result
           (Integrity_Error, "published dispatch does not match persisted remediation", "qm.dispatch.mapping-drift");
         return;
      end if;

      Quality_Manager.Integrations.Runner.Inspect
        (Runner, To_String (Work.Project.Canonical_Path), To_String (Mapping.Native_Task_Id), Response);
      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Inspected, Result);
      if Result.Kind /= Success then
         return;
      elsif Inspected.Task_Id /= Mapping.Native_Task_Id then
         Result := Make_Result
           (Integrity_Error, "inspected native task does not match publication", "qm.dispatch.native-task");
         return;
      elsif Inspected.Source_Fingerprint /= Work.Planned_Source_Fingerprint then
         Result := Make_Result
           (Stale_Evidence, "native project source changed after planning", "qm.dispatch.source-drift");
         return;
      elsif Length (Inspected.Task_Revision) = 0
        or else Length (Inspected.Project_Identity) = 0
        or else Length (Inspected.Execution_Policy) = 0
      then
         Result := Make_Result
           (Incompatible_Contract, "native inspection lacks execution identity", "qm.dispatch.inspect-identity");
         return;
      elsif Current in Quality_Manager.Model.Published | Quality_Manager.Model.Queued
        and then (not Inspected.Ready
                  or else Inspected.State /= Quality_Manager.Integrations.Runner.Ready_State)
      then
         Result := Make_Result
           (Not_Ready, "published native task is not ready", "qm.dispatch.native-not-ready");
         return;
      end if;

      Operation := Quality_Manager.Identities.Operation_Identity
        ("model-runner-execution", To_String (Mapping.Dispatch_Id));
      Resource := To_Unbounded_String
        ("project-execution:"
         & Quality_Manager.Identities.Canonical_Digest
             ([Quality_Manager.Identities.Text_Value
                 (To_String (Work.Project.Quality_Database_Id)),
               Quality_Manager.Identities.Number_Value
                 (Interfaces.Unsigned_64 (Work.Project.Quality_Project_Id)),
               Quality_Manager.Identities.Text_Value
                 (To_String (Work.Project.Canonical_Path))]));
      Request :=
        (Project_Path => Work.Project.Canonical_Path,
         Task_Id => Mapping.Native_Task_Id,
         Operation_Id => To_Unbounded_String (Operation_Name (Operation)),
         Expected_Task_Revision => Inspected.Task_Revision,
         Expected_Project_Identity => Inspected.Project_Identity,
         Expected_Source_Fingerprint => Work.Planned_Source_Fingerprint,
         Execution_Policy => Inspected.Execution_Policy,
         Timeout_Seconds => Timeout_Seconds);
      if not Lease_Available then
         return;
      elsif Expected = Interfaces.Unsigned_64'Last then
         Result := Make_Result
           (Integrity_Error, "project execution lease generation is exhausted", "qm.dispatch.lease-generation");
         return;
      end if;

      if Current = Quality_Manager.Model.Queued then
         Move_To
           (Quality_Manager.Model.Executing, "executing", "native task execution prepared",
            To_String (Mapping.Dispatch_Id));
         if Result.Kind /= Success then
            return;
         end if;
      end if;

      Execute_Or_Reconcile
        (Store, Runner, Operation, To_String (Mapping.Dispatch_Id), To_String (Resource), Lease_Owner,
         Expected, Expected + 1, Lease_Expires_At, Request, Snapshot, Result);
      if Result.Kind = Not_Ready then
         return;
      elsif Result.Kind = Success then
         declare
            Target : constant Quality_Manager.Model.Work_State := Coordinator_State (Snapshot.State);
         begin
            if Target = Quality_Manager.Model.Awaiting_Integration then
               Move_To
                 (Target, "awaiting-integration", "native execution completed in isolated workspace",
                  To_String (Snapshot.Audit_Reference));
            elsif Target = Quality_Manager.Model.Awaiting_Assessment
              and then To_String (Snapshot.Workspace_State) = "integrated"
            then
               Move_To
                 (Quality_Manager.Model.Awaiting_Integration, "integration-observed",
                  "native execution reports integrated workspace", To_String (Snapshot.Audit_Reference));
               if Result.Kind = Success then
                  Move_To
                    (Quality_Manager.Model.Awaiting_Assessment, "awaiting-assessment",
                     "integrated native work awaits independent assessment",
                     To_String (Snapshot.Source_Fingerprint));
               end if;
            else
               Result := Make_Result
                 (Incompatible_Contract, "native execution completed in an invalid coordinator state",
                  "qm.dispatch.native-state");
            end if;
         end;
      elsif Snapshot.State = Quality_Manager.Integrations.Runner.Cancelled_State then
         declare
            Failure : constant Operation_Result := Result;
         begin
            Move_To (Quality_Manager.Model.Cancelled, "cancelled", "native execution was cancelled");
            if Result.Kind = Success then
               Result := Failure;
            end if;
         end;
      elsif Snapshot.State = Quality_Manager.Integrations.Runner.Failed_State then
         declare
            Failure : constant Operation_Result := Result;
         begin
            Move_To (Quality_Manager.Model.Failed, "failed", "native execution failed");
            if Result.Kind = Success then
               Result := Failure;
            end if;
         end;
      end if;
   exception
      when Constraint_Error =>
         Snapshot := (others => <>);
         Result := Make_Result
           (Integrity_Error, "persisted execution identity is out of range", "qm.dispatch.persisted-range");
   end Execute_Persisted;

   function Integration_Intent
     (Request : Quality_Manager.Integrations.Runner.Execution_Request) return String is
     (Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value ("model-runner-integration-v1"),
          Quality_Manager.Identities.Text_Value (To_String (Request.Project_Path)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Task_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Operation_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Expected_Task_Revision)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Expected_Project_Identity)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Expected_Source_Fingerprint)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Execution_Policy))]));

   procedure Validate_Integration
     (Snapshot : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Request  : Quality_Manager.Integrations.Runner.Execution_Request;
      Result   : out Operation_Result) is
   begin
      if Snapshot.Operation_Id /= Request.Operation_Id then
         Result := Make_Result (Integrity_Error, "integration operation identity mismatch", "qm.integration.operation");
      elsif Snapshot.Task_Id /= Request.Task_Id then
         Result := Make_Result (Integrity_Error, "integration task identity mismatch", "qm.integration.task");
      elsif Snapshot.Task_Revision /= Request.Expected_Task_Revision then
         Result := Make_Result (Stale_Evidence, "integration task revision changed", "qm.integration.task-revision");
      elsif Snapshot.Project_Identity /= Request.Expected_Project_Identity then
         Result := Make_Result (Integrity_Error, "integration project identity mismatch", "qm.integration.project");
      elsif Snapshot.Execution_Policy /= Request.Execution_Policy then
         Result := Make_Result
           (Authorization_Required, "integration policy changed", "qm.integration.policy");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Integration;

   procedure Integrate_Or_Reconcile
     (Store                     : in out Quality_Manager.Storage.Store;
      Runner                    : Quality_Manager.Integrations.Runner.Adapter;
      Journal_Operation         : Quality_Manager.Identities.Operation_Id;
      Project_Resource          : String;
      Lease_Owner               : String;
      Expected_Lease_Generation : Interfaces.Unsigned_64;
      New_Lease_Generation      : Interfaces.Unsigned_64;
      Lease_Expires_At          : Interfaces.Unsigned_64;
      Request                   : Quality_Manager.Integrations.Runner.Execution_Request;
      Snapshot                  : out Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result                    : out Operation_Result) is
      Journal_Item : Quality_Manager.Storage.Stored_Entity;
      State        : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
      Response     : Quality_Manager.Integrations.JSON_CLI.Response;
      Recovered    : Quality_Manager.Integrations.JSON_CLI.Response;
      Checked      : Operation_Result;
      External_Id  : constant String := To_String (Request.Operation_Id);
      Intent       : constant String := Integration_Intent (Request);
   begin
      Snapshot := (others => <>);
      if Journal_Operation = 0
        or else Project_Resource = ""
        or else Lease_Owner = ""
        or else External_Id = ""
      then
         Result := Make_Result
           (Invalid_Request, "integration coordination identity is incomplete", "qm.integration.identity");
         return;
      end if;

      Read_Journal (Store, Journal_Operation, Journal_Item, State, Result);
      if Result.Kind = Success then
         if not Has_Exact_Intent (Journal_Item, Intent, External_Id) then
            Result := Make_Result
              (Integrity_Error, "journal identity is bound to another integration", "qm.integration.intent");
            return;
         end if;
      elsif Result.Kind = Not_Found then
         Quality_Manager.Storage.Acquire_Lease
           (Store, Project_Resource, Lease_Owner, Expected_Lease_Generation,
            New_Lease_Generation, Lease_Expires_At, Result);
         if Result.Kind /= Success then
            return;
         end if;
         Quality_Manager.Storage.Prepare_Operation
           (Store, Journal_Operation, "model-runner-integration", Intent, External_Id, Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Prepared;
      else
         return;
      end if;

      if State = Quality_Manager.Journal.Aborted then
         Result := Make_Result (Negative_Result, "native integration was aborted", "qm.integration.aborted");
         return;
      elsif State = Quality_Manager.Journal.Needs_Intervention then
         Result := Make_Result
           (Authorization_Required, "native integration requires intervention", "qm.integration.intervention");
         return;
      elsif State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Journal_Operation, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
            External_Id, "", Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Invoking;
         Quality_Manager.Integrations.Runner.Integrate
           (Runner, To_String (Request.Project_Path), External_Id, Response);
      else
         if State = Quality_Manager.Journal.Invoking then
            Quality_Manager.Integrations.Runner.Recover
              (Runner, To_String (Request.Project_Path), Recovered);
            if Recovered.Status.Kind /= Success then
               Result := Recovered.Status;
               return;
            end if;
         end if;
         Quality_Manager.Integrations.Runner.Status
           (Runner, To_String (Request.Project_Path), External_Id, Response);
      end if;

      Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Checked);
      if Checked.Kind /= Success then
         if Checked.Kind in Authorization_Required | Integrity_Error | Incompatible_Contract | Stale_Evidence then
            Mark_Intervention (Store, Journal_Operation, State, External_Id, Message (Checked));
         end if;
         Result := Checked;
         return;
      end if;
      Validate_Integration (Snapshot, Request, Checked);
      if Checked.Kind /= Success then
         Mark_Intervention (Store, Journal_Operation, State, External_Id, Message (Checked));
         Result := Checked;
         return;
      end if;

      if State = Quality_Manager.Journal.Invoking
        and then To_String (Snapshot.Workspace_State) /= "integrated"
      then
         --  Native recovery and status established that the workspace is
         --  still active, so taking it in has not committed. Re-enter the
         --  native idempotent operation instead of copying files ourselves.
         Quality_Manager.Integrations.Runner.Integrate
           (Runner, To_String (Request.Project_Path), External_Id, Response);
         Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Snapshot, Checked);
         if Checked.Kind /= Success then
            if Checked.Kind in Authorization_Required | Integrity_Error |
                               Incompatible_Contract | Stale_Evidence
            then
               Mark_Intervention (Store, Journal_Operation, State, External_Id, Message (Checked));
            end if;
            Result := Checked;
            return;
         end if;
         Validate_Integration (Snapshot, Request, Checked);
         if Checked.Kind /= Success then
            Mark_Intervention (Store, Journal_Operation, State, External_Id, Message (Checked));
            Result := Checked;
            return;
         end if;
      end if;

      if To_String (Snapshot.Workspace_State) /= "integrated" then
         Result := Make_Result
           (Not_Ready, "native workspace is not authoritatively integrated", "qm.integration.pending");
         return;
      end if;
      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Storage.Advance_Operation
           (Store, Journal_Operation, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
            External_Id, To_String (Snapshot.Audit_Reference), Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Reconciling;
      end if;
      if State = Quality_Manager.Journal.Reconciling then
         Quality_Manager.Storage.Advance_Operation
           (Store, Journal_Operation, Quality_Manager.Journal.Reconciling, Quality_Manager.Journal.Committed,
            External_Id, To_String (Snapshot.Source_Fingerprint), Result);
         if Result.Kind /= Success then
            return;
         end if;
      end if;
      Result := Make_Result (Success);
   end Integrate_Or_Reconcile;
end Quality_Manager.Dispatch;
