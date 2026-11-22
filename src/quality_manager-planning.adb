with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Journal;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Schema;

package body Quality_Manager.Planning is
   use type Ada.Containers.Count_Type;
   use type Jsonlib.Documents.Value_Kind;
   use type Quality_Manager.Journal.Journal_State;
   use type Quality_Manager.Results.Result_Kind;
   use Quality_Manager.Results;

   Maximum_JSON     : constant Positive := 16 * 1_024 * 1_024;
   Maximum_Tasks    : constant Positive := 100;
   Maximum_Findings : constant Positive := 10_000;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);
   package String_Sorting is new String_Vectors.Generic_Sorting;

   type Planned_Task is record
      Task_Id            : Unbounded_String;
      Finding_Identities : Unbounded_String;
      Finding_Digest     : Unbounded_String;
   end record;

   package Task_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Planned_Task);

   type Plan_Result is record
      Plan_Id     : Unbounded_String;
      Revision    : Natural := 0;
      Fingerprint : Unbounded_String;
      Content_SHA256 : Unbounded_String;
      Tasks       : Task_Vectors.Vector;
   end record;

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

   function Valid_Content_SHA256 (Value : String) return Boolean is
      Prefix : constant String := "plan-content-sha256-v2:";
   begin
      return Value'Length = Prefix'Length + 64
        and then Value (Value'First .. Value'First + Prefix'Length - 1) = Prefix
        and then
          (for all Index in Value'First + Prefix'Length .. Value'Last =>
             Value (Index) in '0' .. '9' | 'a' .. 'f');
   end Valid_Content_SHA256;

   procedure Decode
     (Response         : Quality_Manager.Integrations.JSON_CLI.Response;
      Project          : Quality_Manager.Identities.Project_Key;
      Assessment_Run   : Positive;
      Candidate_Source : String;
      Plan             : out Plan_Result;
      Result           : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
      Version  : Natural;
      Project_Id : Natural;
      Run_Id     : Natural;
      Command    : Unbounded_String;
      Source     : Unbounded_String;
      Dry_Run    : Boolean;
      Stored     : Boolean;
   begin
      Plan := (others => <>);
      if Response.Status.Kind /= Success then
         Result := Response.Status;
         return;
      end if;
      Jsonlib.Parsers.Parse
        (To_String (Response.Document), Document, Error,
         (Max_Depth => 64, Max_Length => Maximum_JSON,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Incompatible_Contract, "invalid Improve plan JSON", "qm.planning.json");
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
           or else To_String (Command) /= "plan"
           or else not Jsonlib.Documents.Is_Present (Data)
           or else Document.Kind (Data) /= Jsonlib.Documents.Object_Value
           or else not String_Field (Document, Data, "plan_id", Plan.Plan_Id)
           or else Length (Plan.Plan_Id) = 0
           or else not Natural_Field (Document, Data, "revision", Plan.Revision)
           or else Plan.Revision = 0
           or else not Natural_Field (Document, Data, "project_id", Project_Id)
           or else Project_Id /= Project.Quality_Project_Id
           or else not Natural_Field (Document, Data, "run_id", Run_Id)
           or else Run_Id /= Assessment_Run
           or else not String_Field (Document, Data, "working_source_fingerprint", Source)
           or else To_String (Source) /= Candidate_Source
           or else not String_Field (Document, Data, "fingerprint", Plan.Fingerprint)
           or else Length (Plan.Fingerprint) = 0
           or else not String_Field (Document, Data, "content_sha256", Plan.Content_SHA256)
           or else not Valid_Content_SHA256 (To_String (Plan.Content_SHA256))
           or else not Boolean_Field (Document, Data, "dry_run", Dry_Run)
           or else Dry_Run
           or else not Boolean_Field (Document, Data, "stored", Stored)
           or else not Stored
         then
            Result := Make_Result
              (Incompatible_Contract, "Improve plan identity is incomplete or mismatched", "qm.planning.identity");
            return;
         end if;
         Tasks := Document.Member (Data, "tasks");
         if not Jsonlib.Documents.Is_Present (Tasks)
           or else Document.Kind (Tasks) /= Jsonlib.Documents.Array_Value
           or else Document.Length (Tasks) = 0
           or else Document.Length (Tasks) > Maximum_Tasks
         then
            Result := Make_Result
              (Negative_Result, "Improve produced no bounded remediation tasks", "qm.planning.tasks");
            return;
         end if;
         for Index in 1 .. Document.Length (Tasks) loop
            declare
               Node      : constant Jsonlib.Documents.Node := Document.Element (Tasks, Index);
               Task_Id   : Unbounded_String;
               Findings  : Jsonlib.Documents.Node;
               Values    : String_Vectors.Vector;
               Text      : Unbounded_String;
            begin
               if Document.Kind (Node) /= Jsonlib.Documents.Object_Value
                 or else not String_Field (Document, Node, "id", Task_Id)
                 or else Length (Task_Id) = 0
                 or else (for some Existing of Plan.Tasks => Existing.Task_Id = Task_Id)
               then
                  Result := Make_Result
                    (Incompatible_Contract, "Improve task identity is invalid", "qm.planning.task");
                  return;
               end if;
               Findings := Document.Member (Node, "findings");
               if not Jsonlib.Documents.Is_Present (Findings)
                 or else Document.Kind (Findings) /= Jsonlib.Documents.Array_Value
                 or else Document.Length (Findings) = 0
                 or else Document.Length (Findings) > Maximum_Findings
               then
                  Result := Make_Result
                    (Incompatible_Contract, "Improve task has no bounded finding set", "qm.planning.findings");
                  return;
               end if;
               for Finding_Index in 1 .. Document.Length (Findings) loop
                  declare
                     Finding : constant Jsonlib.Documents.Node := Document.Element (Findings, Finding_Index);
                  begin
                     if Document.Kind (Finding) /= Jsonlib.Documents.String_Value
                       or else Document.As_String (Finding)'Length = 0
                     then
                        Result := Make_Result
                          (Incompatible_Contract, "Improve finding identity is invalid", "qm.planning.finding");
                        return;
                     end if;
                     Values.Append (Document.As_String (Finding));
                  end;
               end loop;
               String_Sorting.Sort (Values);
               if Values.Length > 1 then
                  for Finding_Index in Values.First_Index + 1 .. Values.Last_Index loop
                     if Values (Finding_Index - 1) = Values (Finding_Index) then
                        Result := Make_Result
                          (Integrity_Error, "Improve task repeats a finding identity", "qm.planning.finding-duplicate");
                        return;
                     end if;
                  end loop;
               end if;
               for Finding of Values loop
                  if Length (Text) > 0 then
                     Append (Text, ASCII.LF);
                  end if;
                  Append (Text, Finding);
               end loop;
               declare
                  Fields : Quality_Manager.Identities.Identity_Field_Array (1 .. Natural (Values.Length));
               begin
                  for Finding_Index in Values.First_Index .. Values.Last_Index loop
                     Fields (Finding_Index) := Quality_Manager.Identities.Text_Value (Values (Finding_Index));
                  end loop;
                  Task_Vectors.Append
                    (Plan.Tasks,
                     Planned_Task'
                       (Task_Id => Task_Id,
                        Finding_Identities => Text,
                        Finding_Digest => To_Unbounded_String
                          (Quality_Manager.Identities.Canonical_Digest (Fields))));
               end;
            end;
         end loop;
      end;
      Result := Make_Result (Success);
   exception
      when others =>
         Plan := (others => <>);
         Result := Make_Result
           (Incompatible_Contract, "invalid Improve plan evidence", "qm.planning.contract");
   end Decode;

   function Number (Value : Quality_Manager.Identities.Operation_Id) return String is
     (Ada.Strings.Fixed.Trim
        (Interfaces.Unsigned_64'Image (Interfaces.Unsigned_64 (Value)), Ada.Strings.Both));

   function External_Id (Plan : Plan_Result) return String is
     ("improve-plan:" & To_String (Plan.Plan_Id) & ":" &
      Ada.Strings.Fixed.Trim (Natural'Image (Plan.Revision), Ada.Strings.Both));

   procedure Persist_Tasks
     (Store          : in out Quality_Manager.Storage.Store;
      Project        : Quality_Manager.Identities.Project_Key;
      Assessment_Run : Positive;
      Candidate_Source : String;
      Policy_Digest  : String;
      Workflow       : Quality_Manager.Model.Workflow_Kind;
      Plan           : Plan_Result;
      Result         : out Operation_Result) is
   begin
      for Plan_Task of Plan.Tasks loop
         declare
            Work_Id : constant String := Quality_Manager.Identities.Work_Identity
              (Project, Assessment_Run, To_String (Plan_Task.Finding_Digest),
               Quality_Manager.Model.Workflow_Kind'Image (Workflow));
            Global_Id : constant String := Quality_Manager.Identities.Global_Remediation_Identity
              (Project, Assessment_Run, To_String (Plan_Task.Finding_Digest));
         begin
            Quality_Manager.Storage.Records.Save
              (Store,
               Quality_Manager.Storage.Schema.Work_Item'
                 (Work_Id => To_Unbounded_String (Work_Id),
                  Global_Remediation => To_Unbounded_String (Global_Id),
                  Project => Project,
                  Origin => Workflow,
                  Finding_Identities => Plan_Task.Finding_Identities,
                  Priority => 200,
                  Baseline_Assessment_Run => Assessment_Run,
                  Improve_Plan_Id => Plan.Plan_Id,
                  Improve_Revision => Plan.Revision,
                  Improve_Task_Id => Plan_Task.Task_Id,
                  Improve_Content_SHA256 => Plan.Content_SHA256,
                  Planned_Source_Fingerprint => To_Unbounded_String (Candidate_Source),
                  Effective_Policy_Digest => To_Unbounded_String (Policy_Digest),
                  State => Quality_Manager.Model.Awaiting_Approval,
                  Outcome => Quality_Manager.Model.Authorization_Required),
               Result);
            if Result.Kind /= Success then
               return;
            end if;
         end;
      end loop;
      Result := Make_Result (Success);
   end Persist_Tasks;

   procedure Generate_Or_Reconcile
     (Store            : in out Quality_Manager.Storage.Store;
      Planner          : Quality_Manager.Integrations.Improve.Adapter;
      Project          : Quality_Manager.Identities.Project_Key;
      Assessment_Run   : Positive;
      Candidate_Source : String;
      Policy_Digest    : String;
      Workflow         : Quality_Manager.Model.Workflow_Kind;
      Stable_Id        : String;
      Result           : out Operation_Result) is
      Operation : constant Quality_Manager.Identities.Operation_Id :=
        Quality_Manager.Identities.Operation_Identity ("improve-plan", Stable_Id);
      Pending   : constant String := "improve-plan:pending";
      Intent    : constant String := Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value ("improve-plan-v1"),
          Quality_Manager.Identities.Text_Value (To_String (Project.Quality_Database_Id)),
          Quality_Manager.Identities.Number_Value
            (Interfaces.Unsigned_64 (Project.Quality_Project_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Project.Canonical_Path)),
          Quality_Manager.Identities.Number_Value (Interfaces.Unsigned_64 (Assessment_Run)),
          Quality_Manager.Identities.Text_Value (Candidate_Source),
          Quality_Manager.Identities.Text_Value (Policy_Digest),
          Quality_Manager.Identities.Text_Value
            (Quality_Manager.Model.Workflow_Kind'Image (Workflow))]);
      Item     : Quality_Manager.Storage.Stored_Entity;
      State    : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
      Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Plan     : Plan_Result;
   begin
      Quality_Manager.Storage.Read (Store, "journal:" & Number (Operation), Item, Result);
      if Result.Kind = Not_Found then
         Quality_Manager.Storage.Prepare_Operation
           (Store, Operation, "improve-plan", Intent, Pending, Result);
         if Result.Kind /= Success then
            return;
         end if;
      elsif Result.Kind /= Success then
         return;
      else
         begin
            State := Quality_Manager.Journal.Journal_State'Value (To_String (Item.State));
         exception
            when Constraint_Error =>
               Result := Make_Result
                 (Incompatible_Contract, "unknown planning journal state", "qm.planning.journal-state");
               return;
         end;
         if Ada.Strings.Fixed.Index (To_String (Item.Payload), "intent=" & Intent) = 0 then
            Result := Make_Result
              (Integrity_Error, "planning operation identity has another intent", "qm.planning.intent");
            return;
         end if;
      end if;

      if State = Quality_Manager.Journal.Prepared then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, State, Quality_Manager.Journal.Invoking, Pending, "", Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Invoking;
      elsif State in Quality_Manager.Journal.Aborted | Quality_Manager.Journal.Needs_Intervention then
         Result := Make_Result
           (Authorization_Required, "Improve planning operation is terminally blocked", "qm.planning.terminal");
         return;
      end if;

      --  Improve stores repeated generation for the same exact assessment as
      --  one plan revision, so replay from Invoking is idempotent.
      if State = Quality_Manager.Journal.Invoking then
         Quality_Manager.Integrations.Improve.Generate_Plan
           (Planner,
            Ada.Strings.Fixed.Trim (Positive'Image (Project.Quality_Project_Id), Ada.Strings.Both),
            Assessment_Run, Response);
         Decode (Response, Project, Assessment_Run, Candidate_Source, Plan, Result);
         if Result.Kind /= Success then
            return;
         end if;
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, State, Quality_Manager.Journal.Reconciling,
            External_Id (Plan), "exact assessment plan observed", Result);
         if Result.Kind /= Success then
            return;
         end if;
         State := Quality_Manager.Journal.Reconciling;
      else
         declare
            Payload : constant String := To_String (Item.Payload);
            Marker  : constant String := "external_id=improve-plan:";
            Start   : constant Natural := Ada.Strings.Fixed.Index
              (Payload, Marker, Going => Ada.Strings.Backward);
            Split   : Natural;
         begin
            if Start = 0 then
               Result := Make_Result
                 (Integrity_Error, "planning journal has no external plan", "qm.planning.external-id");
               return;
            end if;
            Split := Ada.Strings.Fixed.Index
              (Payload, ":", From => Start + Marker'Length);
            if Split = 0 then
               Result := Make_Result
                 (Integrity_Error, "planning journal external identity is invalid", "qm.planning.external-id");
               return;
            end if;
            declare
               Last : Natural := Split + 1;
            begin
               while Last <= Payload'Last and then Payload (Last) in '0' .. '9' loop
                  Last := Last + 1;
               end loop;
               Quality_Manager.Integrations.Improve.Read_Plan
                 (Planner, Payload (Start + Marker'Length .. Split - 1),
                  Natural'Value (Payload (Split + 1 .. Last - 1)), Response);
            end;
         exception
            when Constraint_Error =>
               Result := Make_Result
                 (Integrity_Error, "planning journal external identity is invalid", "qm.planning.external-id");
               return;
         end;
         Decode (Response, Project, Assessment_Run, Candidate_Source, Plan, Result);
         if Result.Kind /= Success then
            return;
         end if;
      end if;

      Persist_Tasks
        (Store, Project, Assessment_Run, Candidate_Source, Policy_Digest, Workflow, Plan, Result);
      if Result.Kind /= Success then
         return;
      end if;
      if State = Quality_Manager.Journal.Reconciling then
         Quality_Manager.Storage.Advance_Operation
           (Store, Operation, State, Quality_Manager.Journal.Committed,
            External_Id (Plan), "approval-gated remediation work persisted", Result);
      end if;
   end Generate_Or_Reconcile;
end Quality_Manager.Planning;
