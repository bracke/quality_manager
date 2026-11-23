with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Model;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Schema;
with Quality_Manager.Verification;

package body Quality_Manager.Recovery is
   use type Jsonlib.Documents.Value_Kind;
   use type Quality_Manager.Identities.Operation_Id;
   use type Quality_Manager.Journal.Journal_State;
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Storage.Record_Kind;
   use Quality_Manager.Results;

   procedure Reconstruct
     (Store   : in out Quality_Manager.Storage.Store;
      Maximum : Positive;
      Work    : out Recovery_Vectors.Vector;
      Result  : out Quality_Manager.Results.Operation_Result) is
      Entries : Quality_Manager.Storage.Entity_Vectors.Vector;
   begin
      Work.Clear;
      Quality_Manager.Storage.Recovery_Entries (Store, Entries, Maximum, Result);
      if Result.Kind /= Quality_Manager.Results.Success then
         return;
      end if;
      for Record_Item of Entries loop
         declare
            State : constant Quality_Manager.Journal.Journal_State :=
              Quality_Manager.Journal.Journal_State'Value (To_String (Record_Item.State));
         begin
            Work.Append
              (Recovery_Item'
                 (Operation_Key => Record_Item.Entity_Key,
                  State         => State,
                  Action        => Quality_Manager.Journal.Action_For (State)));
         end;
      end loop;
   exception
      when Constraint_Error =>
         Work.Clear;
         Result := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Incompatible_Contract,
            "unknown journal state during startup reconstruction",
            "qm.recovery.state");
   end Reconstruct;

   function Operation_Number (Value : Quality_Manager.Identities.Operation_Id) return String is
     (Ada.Strings.Fixed.Trim
        (Interfaces.Unsigned_64'Image (Interfaces.Unsigned_64 (Value)), Ada.Strings.Both));

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

   procedure Decode_Project
     (Work    : Quality_Manager.Storage.Stored_Entity;
      Project : out Quality_Manager.Identities.Project_Key;
      Result  : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
      Database : Unbounded_String;
      Path     : Unbounded_String;
      Id       : Natural;
   begin
      Project := (Null_Unbounded_String, 1, Null_Unbounded_String);
      Jsonlib.Parsers.Parse
        (To_String (Work.Payload), Document, Error,
         (Max_Depth => 16, Max_Length => 1 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Integrity_Error, "persisted recovery work is invalid JSON", "qm.recovery.work-json");
         return;
      end if;
      declare
         Node : constant Jsonlib.Documents.Node := Document.Member (Document.Root, "project");
      begin
         if not Jsonlib.Documents.Is_Present (Node)
           or else Document.Kind (Node) /= Jsonlib.Documents.Object_Value
           or else not String_Field (Document, Node, "quality_database_id", Database)
           or else not Natural_Field (Document, Node, "quality_project_id", Id)
           or else Id = 0
           or else not String_Field (Document, Node, "canonical_path", Path)
           or else Length (Database) = 0
           or else Length (Path) = 0
         then
            Result := Make_Result
              (Integrity_Error, "persisted recovery work has no qualified project", "qm.recovery.work-project");
            return;
         end if;
      end;
      Project := (Database, Positive (Id), Path);
      Result := Make_Result (Success);
   exception
      when others =>  --  AQ: audited exception boundary
         Result := Make_Result
           (Integrity_Error, "persisted recovery work is malformed", "qm.recovery.work-project");
   end Decode_Project;

   procedure Transition
     (Store    : in out Quality_Manager.Storage.Store;
      Work_Id  : String;
      From     : Quality_Manager.Model.Work_State;
      Target   : Quality_Manager.Model.Work_State;
      Phase    : String;
      Evidence : String;
      Result   : out Operation_Result) is
   begin
      Quality_Manager.Storage.Transition_Work
        (Store, Work_Id, From, Target,
         "event:" & Work_Id & ":assessment-reconcile:" & Phase,
         "operator supplied exact completed assessment", Evidence, Result);
   end Transition;

   procedure Complete_Work
     (Store    : in out Quality_Manager.Storage.Store;
      Work_Id  : String;
      Evidence : Quality_Manager.Verification.Assessment_Evidence;
      Result   : out Operation_Result) is
      Work  : Quality_Manager.Storage.Stored_Entity;
      State : Quality_Manager.Model.Work_State;
      Ref   : constant String := "assessment:" &
        Ada.Strings.Fixed.Trim (Positive'Image (Positive (Evidence.Assessment_Id)), Ada.Strings.Both);

      procedure Advance
        (Expected : Quality_Manager.Model.Work_State;
         Target   : Quality_Manager.Model.Work_State;
         Phase    : String) is
      begin
         if Result.Kind = Success and then State = Expected then
            Transition (Store, Work_Id, State, Target, Phase, Ref, Result);
            if Result.Kind = Success then
               State := Target;
            end if;
         end if;
      end Advance;

      procedure Complete_Incomplete is
      begin
         Advance
           (Quality_Manager.Model.Needs_Intervention,
            Quality_Manager.Model.Awaiting_Assessment, "adopted");
         Advance
           (Quality_Manager.Model.Executing,
            Quality_Manager.Model.Inconclusive, "incomplete");
         Advance
           (Quality_Manager.Model.Awaiting_Assessment,
            Quality_Manager.Model.Inconclusive, "incomplete");
      end Complete_Incomplete;

      procedure Complete_Current is
      begin
         Advance
           (Quality_Manager.Model.Needs_Intervention,
            Quality_Manager.Model.Awaiting_Integration, "adopted");
         Advance
           (Quality_Manager.Model.Executing,
            Quality_Manager.Model.Awaiting_Integration, "adopted");
         Advance
           (Quality_Manager.Model.Awaiting_Integration,
            Quality_Manager.Model.Awaiting_Assessment, "integration-not-required");
         Advance
           (Quality_Manager.Model.Awaiting_Assessment,
            Quality_Manager.Model.Verifying, "verifying");
         Advance
           (Quality_Manager.Model.Verifying,
            Quality_Manager.Model.Verified, "verified");
      end Complete_Current;
   begin
      Quality_Manager.Storage.Read (Store, Work_Id, Work, Result);
      if Result.Kind /= Success then
         return;
      end if;
      begin
         State := Quality_Manager.Model.Work_State'Value (To_String (Work.State));
      exception
         when Constraint_Error =>
            Result := Make_Result
              (Incompatible_Contract, "recovery work has an unknown state", "qm.recovery.work-state");
            return;
      end;
      if State in Quality_Manager.Model.Verified | Quality_Manager.Model.Inconclusive then
         Result := Make_Result (Success);
      elsif not Evidence.Complete then
         Complete_Incomplete;
      else
         Complete_Current;
      end if;
   end Complete_Work;

   procedure Reconcile_Assessment
     (Store     : in out Quality_Manager.Storage.Store;
      Quality   : Quality_Manager.Integrations.Quality.Adapter;
      Operation : Quality_Manager.Identities.Operation_Id;
      Run       : Positive;
      Result    : out Operation_Result) is
      Journal  : Quality_Manager.Storage.Stored_Entity;
      Entries  : Quality_Manager.Storage.Entity_Vectors.Vector;
      Work     : Quality_Manager.Storage.Stored_Entity;
      Project  : Quality_Manager.Identities.Project_Key;
      Matches  : Natural := 0;
      Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : Quality_Manager.Verification.Assessment_Evidence;
      State    : Quality_Manager.Journal.Journal_State;
      Selector : Unbounded_String;
      Intent   : Unbounded_String;
      External : constant String := "assessment:" &
        Ada.Strings.Fixed.Trim (Positive'Image (Run), Ada.Strings.Both);
      procedure Load_Journal is
      begin
         if Operation = 0 then
            Result := Make_Result
              (Invalid_Request, "operation identity must be nonzero", "qm.recovery.operation");
            return;
         end if;
         Quality_Manager.Storage.Read
           (Store, "journal:" & Operation_Number (Operation), Journal, Result);
         if Result.Kind /= Success then
            return;
         elsif Journal.Kind /= Quality_Manager.Storage.Journal_Record then
            Result := Make_Result
              (Integrity_Error, "operation identity is not a journal record",
               "qm.recovery.journal-kind");
            return;
         end if;
         begin
            State := Quality_Manager.Journal.Journal_State'Value (To_String (Journal.State));
         exception
            when Constraint_Error =>
               Result := Make_Result
                 (Incompatible_Contract, "assessment journal state is unknown",
                  "qm.recovery.journal-state");
               return;
         end;
         if State not in Quality_Manager.Journal.Invoking |
                         Quality_Manager.Journal.Reconciling |
                         Quality_Manager.Journal.Committed
         then
            Result := Make_Result
              (Invalid_Request, "assessment journal is not reconcilable",
               "qm.recovery.journal-state");
         end if;
      end Load_Journal;

      procedure Find_Work is
      begin
         Quality_Manager.Storage.List
           (Store, Quality_Manager.Storage.Work_Item_Record, Entries, 100_000, Result);
         if Result.Kind /= Success then
            return;
         end if;
         for Candidate of Entries loop
            if Quality_Manager.Identities.Operation_Identity
              ("maintenance-assessment", To_String (Candidate.Entity_Key)) = Operation
            then
               Work := Candidate;
               Matches := Matches + 1;
            end if;
         end loop;
         if Matches /= 1 then
            Result := Make_Result
              (Integrity_Error, "assessment operation does not identify exactly one work item",
               "qm.recovery.work");
         else
            Decode_Project (Work, Project, Result);
         end if;
      end Find_Work;

      function Evidence_Matches return Boolean is
      begin
         if not Evidence.Completed then return False;
         elsif Evidence.Assessment_Id /= Run then return False;
         elsif Evidence.Project_Id /= Project.Quality_Project_Id then return False;
         else return Evidence.Project_Path = Project.Canonical_Path;
         end if;
      end Evidence_Matches;

      procedure Read_Evidence is
      begin
         Quality_Manager.Integrations.Quality.Read_Assessment (Quality, Run, Response);
         Quality_Manager.Verification.Decode_Assessment (Response, Evidence, Result);
         if Result.Kind = Success and then not Evidence_Matches then
            Result := Make_Result
              (Integrity_Error, "assessment does not match the interrupted work",
               "qm.recovery.assessment");
         end if;
      end Read_Evidence;

      procedure Build_Intent is
      begin
         Selector := To_Unbounded_String
           (Ada.Strings.Fixed.Trim
              (Positive'Image (Project.Quality_Project_Id), Ada.Strings.Both));
         Intent := To_Unbounded_String
           (Quality_Manager.Identities.Canonical_Digest
              ([Quality_Manager.Identities.Text_Value ("authoritative-assessment-v1"),
                Quality_Manager.Identities.Text_Value (To_String (Work.Entity_Key)),
                Quality_Manager.Identities.Text_Value (To_String (Project.Quality_Database_Id)),
                Quality_Manager.Identities.Number_Value
                  (Interfaces.Unsigned_64 (Project.Quality_Project_Id)),
                Quality_Manager.Identities.Text_Value (To_String (Project.Canonical_Path)),
                Quality_Manager.Identities.Text_Value (To_String (Selector)),
                Quality_Manager.Identities.Text_Value (To_String (Evidence.Source_Fingerprint)),
                Quality_Manager.Identities.Text_Value (To_String (Evidence.Policy_Fingerprint)),
                Quality_Manager.Identities.Text_Value (To_String (Evidence.Toolchain_Fingerprint)),
                Quality_Manager.Identities.Text_Value ("")]));
      end Build_Intent;

      procedure Reject_Mismatch is
         Work_State : Quality_Manager.Model.Work_State;
      begin
         if State /= Quality_Manager.Journal.Invoking then
            Result := Make_Result
              (Integrity_Error, "assessment does not match the persisted invocation intent",
               "qm.recovery.intent");
            return;
         end if;
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, State, Quality_Manager.Journal.Aborted,
            External, "completed assessment does not match invocation intent", Result);
         if Result.Kind /= Success then
            return;
         end if;
         begin
            Work_State := Quality_Manager.Model.Work_State'Value (To_String (Work.State));
         exception
            when Constraint_Error =>
               Result := Make_Result
                 (Incompatible_Contract, "recovery work has an unknown state",
                  "qm.recovery.work-state");
               return;
         end;
         if Work_State in Quality_Manager.Model.Executing |
                          Quality_Manager.Model.Needs_Intervention
         then
            Transition
              (Store, To_String (Work.Entity_Key), Work_State, Quality_Manager.Model.Blocked,
               "rejected", External, Result);
         end if;
         if Result.Kind = Success then
            Result := Make_Result
              (Negative_Result,
               "assessment was observed but rejected because its invocation intent differs",
               "qm.recovery.intent-mismatch");
         end if;
      end Reject_Mismatch;

      procedure Commit_Reconciliation is
      begin
         if State = Quality_Manager.Journal.Invoking then
            Quality_Manager.Storage.Advance_Operation
              (Store, Operation, State, Quality_Manager.Journal.Reconciling,
               External, "operator confirmed completed assessment", Result);
            if Result.Kind = Success then
               State := Quality_Manager.Journal.Reconciling;
            end if;
         end if;
         if Result.Kind = Success and then State = Quality_Manager.Journal.Reconciling then
            Quality_Manager.Storage.Advance_Operation
              (Store, Operation, State, Quality_Manager.Journal.Committed,
               External, "assessment reconciled", Result);
         end if;
         if Result.Kind = Success then
            Quality_Manager.Storage.Records.Save
              (Store,
               Quality_Manager.Storage.Schema.Project'
                 (Key => Project,
                  Enabled => True,
                  Last_Assessment_Run => Run,
                  Last_Source_Fingerprint => Evidence.Source_Fingerprint),
               Result);
         end if;
         if Result.Kind = Success then
            Complete_Work (Store, To_String (Work.Entity_Key), Evidence, Result);
         end if;
      end Commit_Reconciliation;
   begin
      Load_Journal;
      if Result.Kind /= Success then
         return;
      end if;
      Find_Work;
      if Result.Kind /= Success then
         return;
      end if;
      Read_Evidence;
      if Result.Kind /= Success then
         return;
      end if;
      Build_Intent;
      if Ada.Strings.Fixed.Index (To_String (Journal.Payload), "intent=" & To_String (Intent)) = 0 then
         Reject_Mismatch;
         return;
      end if;
      Commit_Reconciliation;
   end Reconcile_Assessment;
end Quality_Manager.Recovery;
