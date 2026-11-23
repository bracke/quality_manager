with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Quality_Manager.Journal;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Schema;

package body Quality_Manager.Verification is
   use type Jsonlib.Documents.Value_Kind;
   use type Quality_Manager.Integrations.Runner.Execution_State;
   use type Quality_Manager.Identities.Operation_Id;
   use type Quality_Manager.Model.Outcome_Kind;
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Journal.Journal_State;
   use type Quality_Manager.Storage.Record_Kind;
   use type Quality_Manager.Results.Result_Kind;
   use Quality_Manager.Results;

   Maximum_JSON : constant Positive := 16 * 1_024 * 1_024;

   procedure Parse
     (Text     : String;
      Document : in out Jsonlib.Documents.Document;
      Result   : out Operation_Result) is
      Error : Jsonlib.Errors.Error_Info;
   begin
      Jsonlib.Parsers.Parse
        (Text, Document, Error,
         (Max_Depth => 64,
          Max_Length => Maximum_JSON,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Incompatible_Contract,
            "invalid verification JSON: " & Jsonlib.Errors.Identifier (Error.Code),
            "qm.verification.json");
      else
         Result := Make_Result (Success);
      end if;
   end Parse;

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

   procedure Decode_Assessment
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Assessment_Evidence;
      Result   : out Operation_Result) is separate;

   procedure Decode_Regression
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Regression_Evidence;
      Result   : out Operation_Result) is separate;

   procedure Decode_Improve
     (Response         : Quality_Manager.Integrations.JSON_CLI.Response;
      Expected_Task_Id : String;
      Evidence         : out Improve_Evidence;
      Result           : out Operation_Result) is separate;

   procedure Decide
     (Native     : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Assessment : Assessment_Evidence;
      Regression : Regression_Evidence;
      Improve    : Improve_Evidence;
      Context    : Verification_Context;
      Decision   : out Verification_Decision) is
      function Native_Passes return Boolean is
        (Native.State = Quality_Manager.Integrations.Runner.Completed_State
         and then To_String (Native.Workspace_State) = "integrated");

      function Freshness_Passes return Boolean is
        (Assessment.Complete
         and then Assessment.Assessment_Id = Context.Current_Assessment
         and then Assessment.Project_Id = Context.Project_Id
         and then Assessment.Project_Path = Context.Project_Path
         and then Assessment.Source_Fingerprint = Context.Candidate_Source
         and then Assessment.Policy_Fingerprint = Context.Policy_Fingerprint
         and then Assessment.Toolchain_Fingerprint = Context.Toolchain_Fingerprint);

      function Quality_Passes return Boolean is
        (Improve.Task_Found
         and then Improve.Task_Id = Context.Improve_Task_Id
         and then Improve.Plan_Id = Context.Improve_Plan_Id
         and then Improve.Baseline_Run = Context.Baseline_Assessment
         and then Improve.Verification_Run = Context.Current_Assessment
         and then Improve.Comparable
         and then To_String (Improve.Task_Outcome) = "verified");

      function Regression_Passes return Boolean is
        (Regression.Comparable
         and then not Regression.Policy_Changed
         and then not Regression.Compatibility_Failure
         and then Regression.Project_Id = Context.Project_Id
         and then Regression.Baseline_Id = Context.Baseline_Assessment
         and then Regression.Current_Id = Context.Current_Assessment
         and then Regression.Regression_Count = 0
         and then Improve.New_Critical = 0
         and then To_String (Improve.Project_Outcome) /= "regressed");

      procedure Set_Failure_Outcome is
      begin
         if not Decision.Freshness_Gate then
            Decision.Outcome := Quality_Manager.Model.Evidence_Unavailable;
            Decision.Diagnostic := To_Unbounded_String ("assessment evidence is incomplete, stale, or mismatched");
         elsif not Decision.Native_Gate then
            Decision.Outcome := Quality_Manager.Model.Execution_Failed;
            Decision.Diagnostic := To_Unbounded_String ("native completion or integration gate did not pass");
         elsif Regression.Compatibility_Failure or else not Improve.Comparable then
            Decision.Outcome := Quality_Manager.Model.Policy_Incompatible;
            Decision.Diagnostic := To_Unbounded_String ("baseline, policy, or toolchain evidence is incompatible");
         elsif not Decision.Regression_Gate then
            Decision.Outcome := Quality_Manager.Model.Regression;
            Decision.Diagnostic := To_Unbounded_String ("candidate introduced or cannot exclude a regression");
         else
            Decision.Outcome := Quality_Manager.Model.Unresolved;
            Decision.Diagnostic := To_Unbounded_String ("Improve acceptance criteria remain unresolved");
         end if;
      end Set_Failure_Outcome;
   begin
      Decision := (others => <>);
      Decision.Native_Gate := Native_Passes;
      Decision.Freshness_Gate := Freshness_Passes;
      Decision.Quality_Gate := Quality_Passes;
      Decision.Regression_Gate := Regression_Passes;
      Decision.Verified := Decision.Native_Gate
        and then Decision.Quality_Gate
        and then Decision.Regression_Gate
        and then Decision.Freshness_Gate;

      if Decision.Verified then
         Decision.Outcome := Quality_Manager.Model.Satisfied;
         Decision.Diagnostic := To_Unbounded_String ("all independent verification gates passed");
      else
         Set_Failure_Outcome;
      end if;
   end Decide;

   function Retry_For
     (Outcome          : Quality_Manager.Model.Outcome_Kind;
      Attempts_Used    : Natural;
      Maximum_Attempts : Positive) return Retry_Action is
   begin
      if Outcome = Quality_Manager.Model.Satisfied then
         return No_Retry;
      elsif Attempts_Used >= Maximum_Attempts then
         return Block_Work;
      end if;
      case Outcome is
         when Quality_Manager.Model.No_Outcome => return Retry_Idempotent_Operation;
         when Quality_Manager.Model.Unresolved => return Replan_Remediation;
         when Quality_Manager.Model.Regression => return Reject_Candidate;
         when Quality_Manager.Model.Evidence_Unavailable => return Repair_Evidence;
         when Quality_Manager.Model.Policy_Incompatible => return Establish_Compatible_Baseline;
         when Quality_Manager.Model.Execution_Failed => return Start_New_Execution_Attempt;
         when Quality_Manager.Model.Authorization_Required => return Escalate;
         when Quality_Manager.Model.Satisfied => return No_Retry;
      end case;
   end Retry_For;

   function Number (Value : Quality_Manager.Identities.Operation_Id) return String is
     (Ada.Strings.Fixed.Trim
        (Quality_Manager.Identities.Operation_Id'Image (Value), Ada.Strings.Both));

   function Journal_Key (Value : Quality_Manager.Identities.Operation_Id) return String is
     ("journal:" & Number (Value));

   procedure Read_Journal
     (Store     : in out Quality_Manager.Storage.Store;
      Operation : Quality_Manager.Identities.Operation_Id;
      Item      : out Quality_Manager.Storage.Stored_Entity;
      State     : out Quality_Manager.Journal.Journal_State;
      Result    : out Operation_Result) is
   begin
      State := Quality_Manager.Journal.Prepared;
      Quality_Manager.Storage.Read (Store, Journal_Key (Operation), Item, Result);
      if Result.Kind /= Success then
         return;
      elsif Item.Kind /= Quality_Manager.Storage.Journal_Record then
         Result := Make_Result (Integrity_Error, "verification operation is not a journal", "qm.verify.journal");
         return;
      end if;
      begin
         State := Quality_Manager.Journal.Journal_State'Value (To_String (Item.State));
      exception
         when Constraint_Error =>
            Result := Make_Result
              (Incompatible_Contract, "unknown verification journal state", "qm.verify.journal-state");
      end;
   end Read_Journal;

   function Has_Intent
     (Item        : Quality_Manager.Storage.Stored_Entity;
      Intent      : String;
      External_Id : String) return Boolean is
      Payload : constant String := To_String (Item.Payload);
   begin
      return Ada.Strings.Fixed.Index (Payload, "intent=" & Intent) > 0
        and then Ada.Strings.Fixed.Index (Payload, "external_id=" & External_Id) > 0;
   end Has_Intent;

   function Assessment_External_Id
     (Item : Quality_Manager.Storage.Stored_Entity) return Natural is
      Payload : constant String := To_String (Item.Payload);
      Marker  : constant String := "external_id=assessment:";
      Start   : constant Natural := Ada.Strings.Fixed.Index
        (Payload, Marker, Going => Ada.Strings.Backward);
      Last    : Natural;
   begin
      if Start = 0 then
         return 0;
      end if;
      Last := Start + Marker'Length;
      while Last <= Payload'Last and then Payload (Last) in '0' .. '9' loop
         Last := Last + 1;
      end loop;
      if Last = Start + Marker'Length then
         return 0;
      end if;
      return Natural'Value (Payload (Start + Marker'Length .. Last - 1));
   exception
      when Constraint_Error =>
         return 0;
   end Assessment_External_Id;

   procedure Establish_Assessment
     (Store    : in out Quality_Manager.Storage.Store;
      Quality  : Quality_Manager.Integrations.Quality.Adapter;
      Request  : Assessment_Request;
      Evidence : out Assessment_Evidence;
      Result   : out Operation_Result) is separate;

   procedure Improve_Verification
     (Store    : in out Quality_Manager.Storage.Store;
      Planner  : Quality_Manager.Integrations.Improve.Adapter;
      Request  : Remediation_Request;
      Run       : Positive;
      Evidence  : out Improve_Evidence;
      Result    : out Operation_Result) is
      Item       : Quality_Manager.Storage.Stored_Entity;
      State      : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
      Response   : Quality_Manager.Integrations.JSON_CLI.Response;
      External_Id : constant String := "improve-verification:" & Number (Request.Improve_Operation);
      Intent     : constant String := Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value ("improve-task-verification-v1"),
          Quality_Manager.Identities.Text_Value (To_String (Request.Improve_Plan_Id)),
          Quality_Manager.Identities.Number_Value
            (Interfaces.Unsigned_64 (Request.Improve_Plan_Revision)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Improve_Task_Id)),
          Quality_Manager.Identities.Number_Value (Interfaces.Unsigned_64 (Run))]);
   begin
      Evidence := (others => <>);
      Read_Journal (Store, Request.Improve_Operation, Item, State, Result);
      if Result.Kind = Success then
         if not Has_Intent (Item, Intent, External_Id) then
            Result := Make_Result
              (Integrity_Error, "Improve verification identity has another intent", "qm.verify.improve-intent");
            return;
         end if;
      elsif Result.Kind = Not_Found then
         Quality_Manager.Storage.Prepare_Operation
           (Store, Request.Improve_Operation, "improve-task-verification", Intent, External_Id, Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Prepared;
      else
         return;
      end if;

      if State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Request.Improve_Operation, State, Quality_Manager.Journal.Invoking, External_Id, "", Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Invoking;
      elsif State in Quality_Manager.Journal.Aborted | Quality_Manager.Journal.Needs_Intervention then
         Result := Make_Result
           (Authorization_Required, "Improve verification is terminally blocked", "qm.verify.improve-terminal");
         return;
      end if;

      --  Improve persists this exact task/revision/run verification
      --  idempotently, so replay after Invoking is safe.
      Quality_Manager.Integrations.Improve.Verify_Task
        (Planner, To_String (Request.Improve_Task_Id), Request.Improve_Plan_Revision, Run, Response);
      Decode_Improve (Response, To_String (Request.Improve_Task_Id), Evidence, Result);
      if Result.Kind /= Success then
         return;
      end if;
      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Storage.Advance_Operation
           (Store, Request.Improve_Operation, State, Quality_Manager.Journal.Reconciling,
            External_Id, To_String (Evidence.Task_Outcome), Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Reconciling;
      end if;
      if State = Quality_Manager.Journal.Reconciling then
         Quality_Manager.Storage.Advance_Operation
           (Store, Request.Improve_Operation, State, Quality_Manager.Journal.Committed,
            External_Id, "verification adopted", Result);
      end if;
   end Improve_Verification;

   procedure Enter_Verifying
     (Store   : in out Quality_Manager.Storage.Store;
      Work_Id : String;
      Run     : Positive;
      Result  : out Operation_Result) is
      Item : Quality_Manager.Storage.Stored_Entity;
      State : Quality_Manager.Model.Work_State;
      Event : constant String := "event:" & Work_Id & ":verify:" & Positive'Image (Run);
   begin
      Quality_Manager.Storage.Read (Store, Work_Id, Item, Result);
      if Result.Kind /= Success then
         return;
      end if;
      begin
         State := Quality_Manager.Model.Work_State'Value (To_String (Item.State));
      exception
         when Constraint_Error =>
            Result := Make_Result (Incompatible_Contract, "unknown work state", "qm.verify.work-state");
            return;
      end;
      if State in Quality_Manager.Model.Verifying | Quality_Manager.Model.Verified then
         Result := Make_Result (Success);
      elsif State = Quality_Manager.Model.Awaiting_Assessment then
         Quality_Manager.Storage.Transition_Work
           (Store, Work_Id, State, Quality_Manager.Model.Verifying, Event,
            "fresh assessment completed", "assessment:" & Positive'Image (Run), Result);
      else
         Result := Make_Result
           (Invalid_Request, "work is not awaiting verification", "qm.verify.work-precondition");
      end if;
   end Enter_Verifying;

   function Final_State
     (Decision : Verification_Decision;
      Request  : Remediation_Request) return Quality_Manager.Model.Work_State is
      Retry : constant Retry_Action := Retry_For
        (Decision.Outcome, Request.Attempts_Used, Request.Maximum_Attempts);
   begin
      if Decision.Verified then
         return Quality_Manager.Model.Verified;
      elsif Retry = Replan_Remediation then
         return Quality_Manager.Model.Planning;
      elsif Retry = Start_New_Execution_Attempt then
         return Quality_Manager.Model.Planning;
      elsif Retry = Repair_Evidence then
         return Quality_Manager.Model.Inconclusive;
      elsif Retry = Escalate then
         return Quality_Manager.Model.Needs_Intervention;
      else
         return Quality_Manager.Model.Blocked;
      end if;
   end Final_State;

   procedure Verify_Remediation
     (Store       : in out Quality_Manager.Storage.Store;
      Quality     : Quality_Manager.Integrations.Quality.Adapter;
      Planner     : Quality_Manager.Integrations.Improve.Adapter;
      Native      : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Request     : Remediation_Request;
      Decision    : out Verification_Decision;
      Result      : out Operation_Result) is separate;
end Quality_Manager.Verification;
