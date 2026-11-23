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

      procedure Validate_Header
        (Root    : Jsonlib.Documents.Node;
         Data    : Jsonlib.Documents.Node;
         Matches : in out Boolean) is
      begin
         if not Natural_Field (Document, Root, "schema_version", Version) then Matches := False;
         elsif Version /= 2 then Matches := False;
         end if;
         if not String_Field (Document, Root, "command", Command) then Matches := False;
         elsif To_String (Command) /= "plan approve" then Matches := False;
         end if;
         if not Jsonlib.Documents.Is_Present (Data) then Matches := False;
         elsif Document.Kind (Data) /= Jsonlib.Documents.Object_Value then Matches := False;
         end if;
      end Validate_Header;

      procedure Validate_Data
        (Data    : Jsonlib.Documents.Node;
         Matches : in out Boolean) is
      begin
         if not String_Field (Document, Data, "plan_id", Plan_Id) then Matches := False;
         elsif Plan_Id /= Work.Improve_Plan_Id then Matches := False;
         end if;
         if not Natural_Field (Document, Data, "revision", Revision) then Matches := False;
         elsif Revision /= Work.Improve_Revision then Matches := False;
         end if;
         if not String_Field (Document, Data, "content_sha256", Content) then Matches := False;
         elsif Content /= Work.Improve_Content_SHA256 then Matches := False;
         end if;
         if not Boolean_Field (Document, Data, "approved", Approved) then Matches := False;
         elsif not Approved then Matches := False;
         end if;
      end Validate_Data;
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
         Matches : Boolean := True;
      begin
         Validate_Header (Root, Data, Matches);
         Validate_Data (Data, Matches);
         if not Matches then
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

      procedure Validate_Publication_Header
        (Root : Jsonlib.Documents.Node;
         Data : Jsonlib.Documents.Node;
         Valid : in out Boolean) is
      begin
         if not Natural_Field (Document, Root, "schema_version", Version) then Valid := False;
         elsif Version /= 2 then Valid := False;
         end if;
         if not String_Field (Document, Root, "command", Command) then Valid := False;
         elsif To_String (Command) /= "apply" then Valid := False;
         end if;
         if not Jsonlib.Documents.Is_Present (Data) then Valid := False;
         elsif Document.Kind (Data) /= Jsonlib.Documents.Object_Value then Valid := False;
         end if;
      end Validate_Publication_Header;

      procedure Validate_Publication_Data
        (Data : Jsonlib.Documents.Node;
         Valid : in out Boolean) is
      begin
         if not String_Field (Document, Data, "plan_id", Plan_Id) then Valid := False;
         elsif Plan_Id /= Work.Improve_Plan_Id then Valid := False;
         end if;
         if not Natural_Field (Document, Data, "revision", Revision) then Valid := False;
         elsif Revision /= Work.Improve_Revision then Valid := False;
         end if;
         if not String_Field (Document, Data, "content_sha256", Content) then Valid := False;
         elsif Content /= Work.Improve_Content_SHA256 then Valid := False;
         end if;
         if not Boolean_Field (Document, Data, "dry_run", Actual_Dry_Run) then Valid := False;
         elsif Actual_Dry_Run /= Dry_Run then Valid := False;
         end if;
      end Validate_Publication_Data;

      procedure Validate_Identity
        (Root : Jsonlib.Documents.Node;
         Data : Jsonlib.Documents.Node) is
         Valid : Boolean := True;
      begin
         Validate_Publication_Header (Root, Data, Valid);
         Validate_Publication_Data (Data, Valid);
         Result :=
           (if Valid then Make_Result (Success)
            else Make_Result
              (Incompatible_Contract, "Improve publication identity is mismatched",
               "qm.dispatch.publication-contract"));
      end Validate_Identity;

      procedure Read_Task_Mappings (Tasks : Jsonlib.Documents.Node) is
      begin
         if not Jsonlib.Documents.Is_Present (Tasks) then
            Result := Make_Result
              (Incompatible_Contract, "Improve publication task mapping is incomplete",
               "qm.dispatch.publication-tasks");
            return;
         elsif Document.Kind (Tasks) /= Jsonlib.Documents.Array_Value then
            Result := Make_Result
              (Incompatible_Contract, "Improve publication task mapping is incomplete",
               "qm.dispatch.publication-tasks");
            return;
         elsif Document.Length (Tasks) = 0 or else Document.Length (Tasks) > 100 then
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
               elsif Improve_Task = Work.Improve_Task_Id then
                  Matches := Matches + 1;
                  Native_Task := Harness_Task;
               end if;
            end;
         end loop;
      end Read_Task_Mappings;
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
         Validate_Identity (Root, Data);
         if Result.Kind /= Success then
            return;
         end if;
         Tasks := Document.Member (Data, "tasks");
         Read_Task_Mappings (Tasks);
         if Result.Kind /= Success then
            return;
         end if;
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

      procedure Match_String
        (Parent   : Jsonlib.Documents.Node;
         Name     : String;
         Expected : Unbounded_String;
         Actual   : out Unbounded_String;
         Matches  : in out Boolean) is
      begin
         if not String_Field (Document, Parent, Name, Actual) then
            Matches := False;
         elsif Actual /= Expected then
            Matches := False;
         end if;
      end Match_String;

      procedure Match_Natural
        (Parent   : Jsonlib.Documents.Node;
         Name     : String;
         Expected : Natural;
         Actual   : out Natural;
         Matches  : in out Boolean) is
      begin
         if not Natural_Field (Document, Parent, Name, Actual) then
            Matches := False;
         elsif Actual /= Expected then
            Matches := False;
         end if;
      end Match_Natural;

      procedure Match_Unsigned
        (Parent   : Jsonlib.Documents.Node;
         Name     : String;
         Expected : Interfaces.Unsigned_64;
         Actual   : out Interfaces.Unsigned_64;
         Matches  : in out Boolean) is
      begin
         if not Unsigned_Field (Parent, Name, Actual) then
            Matches := False;
         elsif Actual /= Expected then
            Matches := False;
         end if;
      end Match_Unsigned;
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
         Matches : Boolean := True;
      begin
         if Document.Kind (Root) /= Jsonlib.Documents.Object_Value then
            Matches := False;
         elsif not Jsonlib.Documents.Is_Present (Project) then
            Matches := False;
         elsif Document.Kind (Project) /= Jsonlib.Documents.Object_Value then
            Matches := False;
         end if;
         if Matches then
            Match_String
              (Project, "quality_database_id", Approval.Project.Quality_Database_Id, Database_Id, Matches);
            Match_Natural
              (Project, "quality_project_id", Approval.Project.Quality_Project_Id, Project_Id, Matches);
            Match_String (Project, "canonical_path", Approval.Project.Canonical_Path, Path, Matches);
            Match_String (Root, "plan_id", Approval.Plan_Id, Plan_Id, Matches);
            Match_Natural (Root, "plan_revision", Approval.Plan_Revision, Revision, Matches);
            Match_String (Root, "content_digest", Approval.Content_Digest, Content, Matches);
            Match_String (Root, "action", Approval.Authorized_Action, Action, Matches);
            Match_String (Root, "policy_digest", Approval.Policy_Digest, Policy, Matches);
            Match_String (Root, "approver", Approval.Approver, Approver, Matches);
            Match_Unsigned (Root, "created_at", Approval.Created_At, Created, Matches);
            Match_Unsigned (Root, "expires_at", Approval.Expires_At, Expires, Matches);
         end if;
         if not Matches then
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
      Result    : out Operation_Result) is separate;

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
      Result                    : out Operation_Result) is separate;

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
      Result           : out Operation_Result) is separate;

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
      Result                    : out Operation_Result) is separate;

   procedure Integrate_Persisted
     (Store            : in out Quality_Manager.Storage.Store;
      Runner           : Quality_Manager.Integrations.Runner.Adapter;
      Work_Id          : String;
      Lease_Owner      : String;
      Now              : Interfaces.Unsigned_64;
      Lease_Expires_At : Interfaces.Unsigned_64;
      Snapshot         : out Quality_Manager.Integrations.Runner.Task_Snapshot;
      Result           : out Operation_Result) is separate;
end Quality_Manager.Dispatch;
