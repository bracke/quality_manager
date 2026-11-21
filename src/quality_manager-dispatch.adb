with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Journal;
with Quality_Manager.Storage.Records;

package body Quality_Manager.Dispatch is
   use type Quality_Manager.Integrations.Runner.Execution_State;
   use type Quality_Manager.Identities.Operation_Id;
   use type Quality_Manager.Journal.Journal_State;
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
