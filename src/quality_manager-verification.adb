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
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Status   : Unbounded_String;
      Version  : Natural;
      type Indicator_Array is array (Positive range 1 .. 33) of Unbounded_String;
      Indicators : Indicator_Array := [others => Null_Unbounded_String];

      function Valid_Indicator (Value : String) return Boolean is
        (Value'Length = 6
         and then (for all Index in Value'First .. Value'First + 2 => Value (Index) in 'A' .. 'Z')
         and then Value (Value'First + 3) = '-'
         and then (for all Index in Value'First + 4 .. Value'Last => Value (Index) in '0' .. '9'));
   begin
      Evidence := (others => <>);
      if Response.Status.Kind not in Success | Negative_Result then
         Result := Response.Status;
         return;
      end if;
      Parse (To_String (Response.Document), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      declare
         Root    : constant Jsonlib.Documents.Node := Document.Root;
         Results : constant Jsonlib.Documents.Node := Document.Member (Root, "results");
         Executions : constant Jsonlib.Documents.Node := Document.Member (Root, "executions");
      begin
         if not Natural_Field (Document, Root, "schema_version", Version)
           or else Version /= 1
           or else not Natural_Field (Document, Root, "assessment_id", Evidence.Assessment_Id)
           or else not Natural_Field (Document, Root, "project_id", Evidence.Project_Id)
           or else not String_Field (Document, Root, "project_path", Evidence.Project_Path)
           or else not String_Field (Document, Root, "source_fingerprint", Evidence.Source_Fingerprint)
           or else not String_Field (Document, Root, "policy_fingerprint", Evidence.Policy_Fingerprint)
           or else not String_Field
             (Document, Root, "toolchain_fingerprint", Evidence.Toolchain_Fingerprint)
           or else not String_Field (Document, Root, "status", Status)
           or else not Jsonlib.Documents.Is_Present (Results)
           or else Document.Kind (Results) /= Jsonlib.Documents.Array_Value
           or else Document.Length (Results) /= 33
           or else not Jsonlib.Documents.Is_Present (Executions)
           or else Document.Kind (Executions) /= Jsonlib.Documents.Array_Value
         then
            Result := Make_Result
              (Incompatible_Contract, "assessment evidence is incomplete", "qm.verification.assessment");
            return;
         end if;
         Evidence.Completed := To_String (Status) in "ASSESSMENT_COMPLETED" | "completed";
         Evidence.Indicator_Count := Document.Length (Results);
         Evidence.Complete := Evidence.Completed;
         for Index in 1 .. Document.Length (Results) loop
            declare
               Item       : constant Jsonlib.Documents.Node := Document.Element (Results, Index);
               Indicator  : Unbounded_String;
               Compliance : Unbounded_String;
               Execution  : Unbounded_String;
               Summary    : Unbounded_String;
               Evidence_Text : Unbounded_String;
               Applicable : Boolean;
               Measurement : Jsonlib.Documents.Node;
               Findings    : Jsonlib.Documents.Node;
            begin
               if Document.Kind (Item) /= Jsonlib.Documents.Object_Value
                 or else not String_Field (Document, Item, "indicator", Indicator)
                 or else not String_Field (Document, Item, "compliance", Compliance)
                 or else not String_Field (Document, Item, "execution", Execution)
                 or else not Boolean_Field (Document, Item, "applicable", Applicable)
                 or else not String_Field (Document, Item, "summary", Summary)
                 or else not String_Field (Document, Item, "evidence", Evidence_Text)
               then
                  Evidence.Complete := False;
               else
                  Measurement := Document.Member (Item, "measurement");
                  Findings := Document.Member (Item, "findings");
                  if not Valid_Indicator (To_String (Indicator))
                    or else (for some Prior in 1 .. Index - 1 => Indicators (Prior) = Indicator)
                    or else not Jsonlib.Documents.Is_Present (Measurement)
                    or else Document.Kind (Measurement) /= Jsonlib.Documents.Object_Value
                    or else not Jsonlib.Documents.Is_Present (Findings)
                    or else Document.Kind (Findings) /= Jsonlib.Documents.Array_Value
                  then
                     Evidence.Complete := False;
                  end if;
                  Indicators (Index) := Indicator;
                  if To_String (Compliance) = "violation" then
                     Evidence.Violations := Evidence.Violations + 1;
                  elsif To_String (Compliance) not in "pass" | "not-applicable" then
                     Evidence.Complete := False;
                  end if;
                  if To_String (Indicator) = "TST-03"
                    and then Jsonlib.Documents.Is_Present (Measurement)
                    and then Document.Kind (Measurement) = Jsonlib.Documents.Object_Value
                  then
                     if not Natural_Field
                       (Document, Measurement, "basis_points", Evidence.Coverage_Basis_Points)
                     then
                        Evidence.Complete := False;
                     end if;
                  elsif To_String (Indicator) = "PRF-01" then
                     Evidence.Proof_Applicable := Applicable;
                     Evidence.Proof_Passed := not Applicable or else To_String (Compliance) = "pass";
                  end if;
                  if Applicable then
                     if To_String (Execution) /= "succeeded"
                       or else To_String (Compliance) = "not-applicable"
                     then
                        Evidence.Complete := False;
                     end if;
                  elsif To_String (Compliance) /= "not-applicable" then
                     Evidence.Complete := False;
                  end if;
               end if;
            end;
         end loop;
      end;
      Result := Make_Result (Success);
   exception
      when others =>
         Evidence := (others => <>);
         Result := Make_Result
           (Incompatible_Contract, "invalid assessment evidence", "qm.verification.assessment");
   end Decode_Assessment;

   procedure Decode_Regression
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Regression_Evidence;
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Status   : Unbounded_String;
      Kind     : Unbounded_String;
      Version  : Natural;
   begin
      Evidence := (others => <>);
      if Response.Status.Kind /= Success then
         Result := Response.Status;
         return;
      end if;
      Parse (To_String (Response.Document), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      declare
         Root    : constant Jsonlib.Documents.Node := Document.Root;
         Changes : constant Jsonlib.Documents.Node := Document.Member (Root, "changes");
      begin
         if not Natural_Field (Document, Root, "schema_version", Version)
           or else Version /= 1
           or else not String_Field (Document, Root, "kind", Kind)
           or else To_String (Kind) /= "assessment-comparison"
           or else not Natural_Field (Document, Root, "project_id", Evidence.Project_Id)
           or else Evidence.Project_Id = 0
           or else not String_Field (Document, Root, "status", Status)
           or else not Natural_Field (Document, Root, "baseline_id", Evidence.Baseline_Id)
           or else not Natural_Field (Document, Root, "current_id", Evidence.Current_Id)
           or else not Boolean_Field (Document, Root, "policy_changed", Evidence.Policy_Changed)
           or else not Jsonlib.Documents.Is_Present (Changes)
           or else Document.Kind (Changes) /= Jsonlib.Documents.Array_Value
         then
            Result := Make_Result
              (Incompatible_Contract, "regression comparison is incomplete", "qm.verification.regression");
            return;
         end if;
         Evidence.Comparable := To_String (Status) = "comparison-available";
         Evidence.Compatibility_Failure := Evidence.Policy_Changed
           or else To_String (Status) in "toolchain-changed" | "no-compatible-baseline";
         Evidence.Regression_Count := Document.Length (Changes);
         for Index in 1 .. Document.Length (Changes) loop
            declare
               Item   : constant Jsonlib.Documents.Node := Document.Element (Changes, Index);
               Indicator : Unbounded_String;
               Change : Unbounded_String;
               Before : Unbounded_String;
               After  : Unbounded_String;
            begin
               if Document.Kind (Item) /= Jsonlib.Documents.Object_Value
                 or else not String_Field (Document, Item, "indicator", Indicator)
                 or else not String_Field (Document, Item, "change", Change)
                 or else not String_Field (Document, Item, "before", Before)
                 or else not String_Field (Document, Item, "after", After)
                 or else To_String (Change) not in
                   "new-violation" | "worsened-metric" | "increased-severity" |
                   "failed-gate" | "lost-evidence" | "introduced-finding" |
                   "reintroduced-finding" | "policy-induced-change"
               then
                  Result := Make_Result
                    (Incompatible_Contract,
                     "regression change is malformed",
                     "qm.verification.regression-change");
                  return;
               end if;
            end;
         end loop;
      end;
      Result := Make_Result (Success);
   exception
      when others =>
         Evidence := (others => <>);
         Result := Make_Result
           (Incompatible_Contract, "invalid regression comparison", "qm.verification.regression");
   end Decode_Regression;

   procedure Decode_Improve
     (Response         : Quality_Manager.Integrations.JSON_CLI.Response;
      Expected_Task_Id : String;
      Evidence         : out Improve_Evidence;
      Result           : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Version  : Natural;
      Command  : Unbounded_String;
   begin
      Evidence := (others => <>);
      if Response.Status.Kind not in Success | Negative_Result then
         Result := Response.Status;
         return;
      end if;
      Parse (To_String (Response.Document), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      declare
         Root : constant Jsonlib.Documents.Node := Document.Root;
         Data : constant Jsonlib.Documents.Node := Document.Member (Root, "data");
      begin
         if not Natural_Field (Document, Root, "schema_version", Version)
           or else Version /= 2
           or else not String_Field (Document, Root, "command", Command)
           or else To_String (Command) /= "verify"
           or else not Jsonlib.Documents.Is_Present (Data)
           or else Document.Kind (Data) /= Jsonlib.Documents.Object_Value
         then
            Result := Make_Result
              (Incompatible_Contract, "Improve verification data is missing", "qm.verification.improve");
            return;
         end if;
         declare
            Tasks : constant Jsonlib.Documents.Node := Document.Member (Data, "tasks");
            Plan_Outcome : Unbounded_String;
            Explanation  : Unbounded_String;
         begin
            if not String_Field (Document, Data, "plan_id", Evidence.Plan_Id)
              or else not Natural_Field (Document, Data, "baseline_run", Evidence.Baseline_Run)
              or else not Natural_Field (Document, Data, "verification_run", Evidence.Verification_Run)
              or else not String_Field (Document, Data, "outcome", Evidence.Outcome)
              or else not String_Field (Document, Data, "plan_outcome", Plan_Outcome)
              or else not String_Field (Document, Data, "project_outcome", Evidence.Project_Outcome)
              or else not Boolean_Field (Document, Data, "comparable", Evidence.Comparable)
              or else not Natural_Field (Document, Data, "new_critical", Evidence.New_Critical)
              or else not String_Field (Document, Data, "explanation", Explanation)
              or else not Jsonlib.Documents.Is_Present (Tasks)
              or else Document.Kind (Tasks) /= Jsonlib.Documents.Array_Value
            then
               Result := Make_Result
                 (Incompatible_Contract, "Improve verification is incomplete", "qm.verification.improve");
               return;
            end if;
            for Index in 1 .. Document.Length (Tasks) loop
               declare
                  Item    : constant Jsonlib.Documents.Node := Document.Element (Tasks, Index);
                  Task_Id : Unbounded_String;
                  Outcome : Unbounded_String;
                  Explanation : Unbounded_String;
                  Matched : Natural;
                  Total   : Natural;
               begin
                  if Document.Kind (Item) /= Jsonlib.Documents.Object_Value
                    or else not String_Field (Document, Item, "task_id", Task_Id)
                    or else not String_Field (Document, Item, "outcome", Outcome)
                    or else not Natural_Field (Document, Item, "matched", Matched)
                    or else not Natural_Field (Document, Item, "total", Total)
                    or else not String_Field (Document, Item, "explanation", Explanation)
                  then
                     Result := Make_Result
                       (Incompatible_Contract,
                        "Improve task verification is malformed",
                        "qm.verification.improve-task");
                     return;
                  elsif To_String (Task_Id) = Expected_Task_Id then
                     if Evidence.Task_Found then
                        Result := Make_Result
                          (Integrity_Error,
                           "Improve returned duplicate task results",
                           "qm.verification.task-duplicate");
                        return;
                     end if;
                     Evidence.Task_Found := True;
                     Evidence.Task_Id := Task_Id;
                     Evidence.Task_Outcome := Outcome;
                  end if;
               end;
            end loop;
         end;
      end;
      Result := Make_Result (Success);
   exception
      when others =>
         Evidence := (others => <>);
         Result := Make_Result
           (Incompatible_Contract, "invalid Improve verification", "qm.verification.improve");
   end Decode_Improve;

   procedure Decide
     (Native     : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Assessment : Assessment_Evidence;
      Regression : Regression_Evidence;
      Improve    : Improve_Evidence;
      Context    : Verification_Context;
      Decision   : out Verification_Decision) is
   begin
      Decision := (others => <>);
      Decision.Native_Gate :=
        Native.State = Quality_Manager.Integrations.Runner.Completed_State
        and then To_String (Native.Workspace_State) = "integrated";
      Decision.Freshness_Gate :=
        Assessment.Complete
        and then Assessment.Assessment_Id = Context.Current_Assessment
        and then Assessment.Project_Id = Context.Project_Id
        and then Assessment.Project_Path = Context.Project_Path
        and then Assessment.Source_Fingerprint = Context.Candidate_Source
        and then Assessment.Policy_Fingerprint = Context.Policy_Fingerprint
        and then Assessment.Toolchain_Fingerprint = Context.Toolchain_Fingerprint;
      Decision.Quality_Gate :=
        Improve.Task_Found
        and then Improve.Task_Id = Context.Improve_Task_Id
        and then Improve.Plan_Id = Context.Improve_Plan_Id
        and then Improve.Baseline_Run = Context.Baseline_Assessment
        and then Improve.Verification_Run = Context.Current_Assessment
        and then Improve.Comparable
        and then To_String (Improve.Task_Outcome) = "verified";
      Decision.Regression_Gate :=
        Regression.Comparable
        and then not Regression.Policy_Changed
        and then not Regression.Compatibility_Failure
        and then Regression.Project_Id = Context.Project_Id
        and then Regression.Baseline_Id = Context.Baseline_Assessment
        and then Regression.Current_Id = Context.Current_Assessment
        and then Regression.Regression_Count = 0
        and then Improve.New_Critical = 0
        and then To_String (Improve.Project_Outcome) /= "regressed";
      Decision.Verified := Decision.Native_Gate
        and then Decision.Quality_Gate
        and then Decision.Regression_Gate
        and then Decision.Freshness_Gate;

      if Decision.Verified then
         Decision.Outcome := Quality_Manager.Model.Satisfied;
         Decision.Diagnostic := To_Unbounded_String ("all independent verification gates passed");
      elsif not Decision.Freshness_Gate then
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
      Result   : out Operation_Result) is
      Item      : Quality_Manager.Storage.Stored_Entity;
      State     : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
      Response  : Quality_Manager.Integrations.JSON_CLI.Response;
      Run       : Natural := 0;
      Pending   : constant String := "assessment:pending:" & Number (Request.Operation);
      Intent    : constant String := Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value ("authoritative-assessment-v1"),
          Quality_Manager.Identities.Text_Value (To_String (Request.Work_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Project.Quality_Database_Id)),
          Quality_Manager.Identities.Number_Value
            (Interfaces.Unsigned_64 (Request.Project.Quality_Project_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Project.Canonical_Path)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Project_Selector)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Candidate_Source)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Policy_Fingerprint)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Toolchain_Fingerprint)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Profile))]);
   begin
      Evidence := (others => <>);
      if Request.Operation = 0
        or else Length (Request.Work_Id) = 0
        or else Length (Request.Project.Quality_Database_Id) = 0
        or else Length (Request.Project.Canonical_Path) = 0
        or else Length (Request.Project_Selector) = 0
        or else Length (Request.Profile) = 0
        or else Length (Request.Candidate_Source) = 0
        or else Length (Request.Policy_Fingerprint) = 0
        or else Length (Request.Toolchain_Fingerprint) = 0
      then
         Result := Make_Result
           (Invalid_Request, "assessment request is incomplete", "qm.verify.assessment-request");
         return;
      end if;
      Read_Journal (Store, Request.Operation, Item, State, Result);
      if Result.Kind = Success then
         if not Has_Intent (Item, Intent, Pending) then
            Result := Make_Result
              (Integrity_Error, "assessment operation identity has another intent", "qm.verify.assessment-intent");
            return;
         end if;
      elsif Result.Kind = Not_Found then
         Quality_Manager.Storage.Prepare_Operation
           (Store, Request.Operation, "authoritative-assessment", Intent, Pending, Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Prepared;
      else
         return;
      end if;

      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Storage.Advance_Operation
           (Store, Request.Operation, State, Quality_Manager.Journal.Needs_Intervention,
            Pending, "Ada Quality cannot reconcile an interrupted check by operation identity", Result);
         if Result.Kind = Success then
            Result := Make_Result
              (Authorization_Required,
               "interrupted assessment requires explicit reconciliation",
               "qm.verify.assessment-ambiguous");
         end if;
         return;
      elsif State in Quality_Manager.Journal.Reconciling | Quality_Manager.Journal.Committed then
         Run := Assessment_External_Id (Item);
         if Run = 0 then
            Result := Make_Result
              (Integrity_Error, "assessment journal has no durable run identity", "qm.verify.assessment-run");
            return;
         end if;
         Quality_Manager.Integrations.Quality.Read_Assessment (Quality, Positive (Run), Response);
      elsif State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Request.Operation, State, Quality_Manager.Journal.Invoking, Pending, "", Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Invoking;
         Quality_Manager.Integrations.Quality.Run_Check
           (Quality, To_String (Request.Project_Selector), To_String (Request.Profile), False, Response);
      else
         Result := Make_Result
           (Authorization_Required, "assessment operation is terminally blocked", "qm.verify.assessment-terminal");
         return;
      end if;

      Decode_Assessment (Response, Evidence, Result);
      if Result.Kind /= Success or else Evidence.Assessment_Id = 0 then
         return;
      end if;
      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Storage.Advance_Operation
           (Store, Request.Operation, State, Quality_Manager.Journal.Reconciling,
            "assessment:" & Ada.Strings.Fixed.Trim
              (Natural'Image (Evidence.Assessment_Id), Ada.Strings.Both),
            "completed assessment observed", Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Reconciling;
      end if;
      if State = Quality_Manager.Journal.Reconciling then
         Quality_Manager.Storage.Advance_Operation
           (Store, Request.Operation, State, Quality_Manager.Journal.Committed,
            "assessment:" & Ada.Strings.Fixed.Trim
              (Natural'Image (Evidence.Assessment_Id), Ada.Strings.Both),
            "assessment adopted", Result);
      end if;
   end Establish_Assessment;

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
      Result      : out Operation_Result) is
      Assessment_Result : Assessment_Evidence;
      Regression_Result : Regression_Evidence;
      Improve_Result    : Improve_Evidence;
      Comparison        : Quality_Manager.Integrations.JSON_CLI.Response;
      Context           : Verification_Context;
      Record_Item       : Quality_Manager.Storage.Schema.Verification;
      Target            : Quality_Manager.Model.Work_State;
      Work_Record       : Quality_Manager.Storage.Stored_Entity;
      Current_State     : Quality_Manager.Model.Work_State;
   begin
      Decision := (others => <>);
      if Length (Request.Work_Id) = 0
        or else Length (Request.Candidate_Revision) = 0
        or else Length (Request.Candidate_Source) = 0
        or else Length (Request.Contract_Digest) = 0
        or else Request.Assessment_Operation = 0
        or else Request.Improve_Operation = 0
      then
         Result := Make_Result (Invalid_Request, "verification request is incomplete", "qm.verify.request");
         return;
      end if;

      Establish_Assessment
        (Store, Quality,
         (Operation => Request.Assessment_Operation,
          Work_Id => Request.Work_Id,
          Project => Request.Project,
          Project_Selector => Request.Project_Selector,
          Profile => Request.Profile,
          Candidate_Source => Request.Candidate_Source,
          Policy_Fingerprint => Request.Policy_Fingerprint,
          Toolchain_Fingerprint => Request.Toolchain_Fingerprint),
         Assessment_Result, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Enter_Verifying
        (Store, To_String (Request.Work_Id), Positive (Assessment_Result.Assessment_Id), Result);
      if Result.Kind /= Success then
         return;
      end if;
      Quality_Manager.Integrations.Quality.Compare
        (Quality, Request.Baseline_Assessment, Positive (Assessment_Result.Assessment_Id), Comparison);
      Decode_Regression (Comparison, Regression_Result, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Improve_Verification
        (Store, Planner, Request, Positive (Assessment_Result.Assessment_Id), Improve_Result, Result);
      if Result.Kind /= Success then
         return;
      end if;

      Context :=
        (Project_Id            => Request.Project.Quality_Project_Id,
         Project_Path          => Request.Project.Canonical_Path,
         Candidate_Source      => Request.Candidate_Source,
         Policy_Fingerprint    => Request.Policy_Fingerprint,
         Toolchain_Fingerprint => Request.Toolchain_Fingerprint,
         Baseline_Assessment   => Request.Baseline_Assessment,
         Current_Assessment    => Positive (Assessment_Result.Assessment_Id),
         Improve_Plan_Id       => Request.Improve_Plan_Id,
         Improve_Task_Id       => Request.Improve_Task_Id);
      Decide (Native, Assessment_Result, Regression_Result, Improve_Result, Context, Decision);

      Record_Item :=
        (Composite_Key => To_Unbounded_String
           (Quality_Manager.Identities.Canonical_Digest
              ([Quality_Manager.Identities.Text_Value (To_String (Request.Work_Id)),
                Quality_Manager.Identities.Number_Value
                  (Interfaces.Unsigned_64 (Assessment_Result.Assessment_Id)),
                Quality_Manager.Identities.Text_Value (To_String (Request.Contract_Digest))])),
         Work_Id => Request.Work_Id,
         Assessment =>
           (Project => Request.Project, Run_Id => Positive (Assessment_Result.Assessment_Id)),
         Contract_Digest => Request.Contract_Digest,
         Native_Result => To_Unbounded_String
           (Quality_Manager.Integrations.Runner.Execution_State'Image (Native.State)),
         Improve_Result => Improve_Result.Task_Outcome,
         Regression_Result => To_Unbounded_String
           (Natural'Image (Regression_Result.Regression_Count)),
         Candidate_Revision => Request.Candidate_Revision,
         Source_Fingerprint => Assessment_Result.Source_Fingerprint,
         Policy_Fingerprint => Assessment_Result.Policy_Fingerprint,
         Toolchain_Fingerprint => Assessment_Result.Toolchain_Fingerprint);
      Quality_Manager.Storage.Records.Save (Store, Record_Item, Result);
      if Result.Kind /= Success then
         return;
      end if;

      Target := Final_State (Decision, Request);
      Quality_Manager.Storage.Read (Store, To_String (Request.Work_Id), Work_Record, Result);
      if Result.Kind /= Success then
         return;
      end if;
      begin
         Current_State := Quality_Manager.Model.Work_State'Value (To_String (Work_Record.State));
      exception
         when Constraint_Error =>
            Result := Make_Result (Incompatible_Contract, "unknown final work state", "qm.verify.final-state");
            return;
      end;
      if Current_State = Target then
         Result := Make_Result (Success);
      elsif Current_State = Quality_Manager.Model.Verifying then
         Quality_Manager.Storage.Transition_Work
           (Store, To_String (Request.Work_Id), Current_State, Target,
            "event:" & To_String (Request.Work_Id) & ":verified:" &
              Positive'Image (Assessment_Result.Assessment_Id),
            To_String (Decision.Diagnostic),
            "assessment:" & Positive'Image (Assessment_Result.Assessment_Id), Result);
      else
         Result := Make_Result
           (Invalid_Request, "work changed during verification", "qm.verify.concurrent-state");
      end if;
      if Result.Kind = Success and then not Decision.Verified then
         Result := Make_Result (Negative_Result, To_String (Decision.Diagnostic), "qm.verify.negative");
      end if;
   end Verify_Remediation;
end Quality_Manager.Verification;
