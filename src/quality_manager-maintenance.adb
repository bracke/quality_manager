with Ada.Calendar;
with Ada.Calendar.Conversions;
with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Quality_Manager.Config;
with Quality_Manager.Dispatch;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Model;
with Quality_Manager.Planning;
with Quality_Manager.Priorities;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Decoding;
with Quality_Manager.Storage.Schema;
with Quality_Manager.Verification;

package body Quality_Manager.Maintenance is
   use type Jsonlib.Documents.Value_Kind;
   use type Interfaces.Unsigned_64;
   use type Quality_Manager.Integrations.Runner.Execution_State;
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Scheduler.Store_Access;
   use type Quality_Manager.Scheduler.Work_Resource;
   use type Quality_Manager.Storage.Record_Kind;
   use Quality_Manager.Results;

   function Due_Reason (Evidence : Evidence_Identity) return Assessment_Reason is
   begin
      if Evidence.Assessment_Run = 0 then
         return No_Assessment;
      elsif not Evidence.Assessment_Complete then
         return Evidence_Incomplete;
      elsif Evidence.Previous_Source /= Evidence.Current_Source then
         return Source_Changed;
      elsif Evidence.Previous_Policy /= Evidence.Current_Policy then
         return Policy_Changed;
      elsif Evidence.Previous_Toolchain /= Evidence.Current_Toolchain then
         return Toolchain_Changed;
      elsif Evidence.Refresh_Due then
         return Scheduled_Refresh;
      else
         return Evidence_Current;
      end if;
   end Due_Reason;

   function Assessment_Due (Evidence : Evidence_Identity) return Boolean is
     (Due_Reason (Evidence) /= Evidence_Current);

   procedure Initialize
     (Item      : out Context;
      Store     : Quality_Manager.Scheduler.Store_Access;
      Scheduler : access Quality_Manager.Scheduler.Scheduler_Type;
      Quality   : Quality_Manager.Integrations.Quality.Adapter;
      Planner   : Quality_Manager.Integrations.Improve.Adapter;
      Runner    : Quality_Manager.Integrations.Runner.Adapter;
      Maximum_Task_Seconds : Positive := 3_600;
      Maximum_Attempts : Positive := 2) is
   begin
      Item.Database := Store;
      Item.Queue := Scheduler_Access (Scheduler);
      Item.Quality := Quality;
      Item.Planner := Planner;
      Item.Runner := Runner;
      Item.Maximum_Task_Seconds := Maximum_Task_Seconds;
      Item.Maximum_Attempts := Maximum_Attempts;
   end Initialize;

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

   function Selected (Selector : String; Id : Positive; Path : String) return Boolean is
     (Selector = ""
      or else Selector = Ada.Strings.Fixed.Trim (Positive'Image (Id), Ada.Strings.Both)
      or else Selector = Path);

   function Cycle_Identity
     (Database : String;
      Project  : Positive;
      Path     : String) return String is
      Now : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Include_Time_Fraction => True);
   begin
      return Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value (Database),
          Quality_Manager.Identities.Number_Value (Interfaces.Unsigned_64 (Project)),
          Quality_Manager.Identities.Text_Value (Path),
          Quality_Manager.Identities.Text_Value (Now)]);
   end Cycle_Identity;

   type Assessment_Plan is record
      Source_Fingerprint    : Unbounded_String;
      Policy_Fingerprint    : Unbounded_String;
      Toolchain_Fingerprint : Unbounded_String;
   end record;

   procedure Decode_Plan
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Project  : Quality_Manager.Identities.Project_Key;
      Plan     : out Assessment_Plan;
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
      Version  : Natural;
      Kind     : Unbounded_String;
      Action   : Unbounded_String;
      Id       : Natural;
      Path     : Unbounded_String;
   begin
      Plan := (others => <>);
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
           (Incompatible_Contract, "invalid assessment plan JSON", "qm.maintenance.plan-json");
         return;
      end if;
      declare
         Root     : constant Jsonlib.Documents.Node := Document.Root;
         Projects : constant Jsonlib.Documents.Node := Document.Member (Root, "projects");
      begin
         if not Natural_Field (Document, Root, "schema_version", Version)
           or else Version /= 1
           or else not String_Field (Document, Root, "kind", Kind)
           or else To_String (Kind) /= "check-plan"
           or else not Jsonlib.Documents.Is_Present (Projects)
           or else Document.Kind (Projects) /= Jsonlib.Documents.Array_Value
           or else Document.Length (Projects) /= 1
         then
            Result := Make_Result
              (Incompatible_Contract, "assessment plan contract is incomplete", "qm.maintenance.plan");
            return;
         end if;
         declare
            Node : constant Jsonlib.Documents.Node := Document.Element (Projects, 1);
         begin
            if Document.Kind (Node) /= Jsonlib.Documents.Object_Value
              or else not Natural_Field (Document, Node, "project_id", Id)
              or else Id /= Project.Quality_Project_Id
              or else not String_Field (Document, Node, "path", Path)
              or else Path /= Project.Canonical_Path
              or else not String_Field (Document, Node, "action", Action)
              or else To_String (Action) not in "assess" | "reuse"
              or else not String_Field
                (Document, Node, "source_fingerprint", Plan.Source_Fingerprint)
              or else not String_Field
                (Document, Node, "policy_fingerprint", Plan.Policy_Fingerprint)
              or else not String_Field
                (Document, Node, "toolchain_fingerprint", Plan.Toolchain_Fingerprint)
              or else Length (Plan.Source_Fingerprint) = 0
              or else Length (Plan.Policy_Fingerprint) = 0
              or else Length (Plan.Toolchain_Fingerprint) = 0
            then
               Result := Make_Result
                 (Incompatible_Contract,
                  "assessment plan identity is incomplete or mismatched",
                  "qm.maintenance.plan-identity");
               return;
            end if;
         end;
      end;
      Result := Make_Result (Success);
   exception
      when others =>
         Plan := (others => <>);
         Result := Make_Result
           (Incompatible_Contract, "invalid assessment plan", "qm.maintenance.plan");
   end Decode_Plan;

   procedure Transition
     (Store    : in out Quality_Manager.Storage.Store;
      Work_Id  : String;
      From     : Quality_Manager.Model.Work_State;
      Target   : Quality_Manager.Model.Work_State;
      Phase    : String;
      Cause    : String;
      Evidence : String;
      Result   : out Operation_Result) is
   begin
      Quality_Manager.Storage.Transition_Work
        (Store, Work_Id, From, Target,
         "event:" & Work_Id & ":maintenance:" & Phase,
         Cause, Evidence, Result);
   end Transition;

   procedure Decode_Work_Project
     (Item    : Quality_Manager.Storage.Stored_Entity;
      Project : out Quality_Manager.Identities.Project_Key;
      Result  : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
      Id       : Natural;
      Database : Unbounded_String;
      Path     : Unbounded_String;
   begin
      Project := (Null_Unbounded_String, 1, Null_Unbounded_String);
      Jsonlib.Parsers.Parse
        (To_String (Item.Payload), Document, Error,
         (Max_Depth => 16, Max_Length => 1 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Integrity_Error, "persisted assessment work is invalid JSON", "qm.maintenance.work-json");
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
              (Integrity_Error, "persisted assessment work has no qualified project",
               "qm.maintenance.work-project");
            return;
         end if;
      end;
      Project := (Database, Positive (Id), Path);
      Result := Make_Result (Success);
   exception
      when others =>
         Result := Make_Result
           (Integrity_Error, "persisted assessment work is malformed", "qm.maintenance.work-project");
   end Decode_Work_Project;

   function Project_Record_Key
     (Project : Quality_Manager.Identities.Project_Key) return String is
     ("project:" & Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value (To_String (Project.Quality_Database_Id)),
          Quality_Manager.Identities.Number_Value
            (Interfaces.Unsigned_64 (Project.Quality_Project_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Project.Canonical_Path))]));

   procedure Read_Project_Observation
     (Store   : in out Quality_Manager.Storage.Store;
      Project : Quality_Manager.Identities.Project_Key;
      Value   : out Quality_Manager.Storage.Schema.Project;
      Result  : out Operation_Result) is
      Item       : Quality_Manager.Storage.Stored_Entity;
      Parsed_Key : Quality_Manager.Identities.Project_Key;
      Run        : Natural;
      Source     : Unbounded_String;
      Local      : Operation_Result;
      Document   : Jsonlib.Documents.Document;
      Error      : Jsonlib.Errors.Error_Info;
   begin
      Value := (Project, True, 0, Null_Unbounded_String);
      Quality_Manager.Storage.Read (Store, Project_Record_Key (Project), Item, Result);
      if Result.Kind = Not_Found then
         Result := Make_Result (Success);
         return;
      elsif Result.Kind /= Success then
         return;
      elsif Item.Kind /= Quality_Manager.Storage.Project_Record then
         Result := Make_Result
           (Integrity_Error, "project identity resolves to another record kind", "qm.maintenance.project-kind");
         return;
      end if;
      Decode_Work_Project (Item, Parsed_Key, Local);
      if Local.Kind /= Success or else not Quality_Manager.Identities.Equal (Parsed_Key, Project) then
         Result := Make_Result
           (Integrity_Error, "persisted project identity is inconsistent", "qm.maintenance.project-identity");
         return;
      end if;
      Jsonlib.Parsers.Parse
        (To_String (Item.Payload), Document, Error,
         (Max_Depth => 16, Max_Length => 1 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error)
        or else not Natural_Field (Document, Document.Root, "last_assessment_run", Run)
        or else not String_Field (Document, Document.Root, "last_source_fingerprint", Source)
      then
         Result := Make_Result
           (Integrity_Error, "persisted project observation is incomplete", "qm.maintenance.project-observation");
         return;
      end if;
      Value :=
        (Key => Project,
         Enabled => To_String (Item.State) = "ENABLED",
         Last_Assessment_Run => Run,
         Last_Source_Fingerprint => Source);
      Result := Make_Result (Success);
   exception
      when others =>
         Result := Make_Result
           (Integrity_Error, "persisted project observation is malformed", "qm.maintenance.project-observation");
   end Read_Project_Observation;

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

      procedure Stop_Work
        (From       : Quality_Manager.Model.Work_State;
         Target     : Quality_Manager.Model.Work_State;
         Diagnostic : String) is
      begin
         Transition
           (Item.Database.all, Work_Id, From, Target, "blocked", Diagnostic, "", Result);
      end Stop_Work;
   begin
      Quality_Manager.Storage.Read (Item.Database.all, Work_Id, Work, Result);
      if Result.Kind /= Success then
         return;
      elsif Work.Kind /= Quality_Manager.Storage.Work_Item_Record
        or else To_String (Work.State) /= Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Queued)
      then
         Result := Make_Result
           (Invalid_Request, "assessment work is not durably queued", "qm.maintenance.work-state");
         return;
      end if;
      Decode_Work_Project (Work, Project, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Selector := To_Unbounded_String
        (Ada.Strings.Fixed.Trim (Positive'Image (Project.Quality_Project_Id), Ada.Strings.Both));
      Quality_Manager.Integrations.Quality.Plan_Check
        (Item.Quality, To_String (Selector), "", False, Response);
      Decode_Plan (Response, Project, Plan, Local);
      if Local.Kind /= Success then
         Stop_Work (Quality_Manager.Model.Queued, Quality_Manager.Model.Blocked, Message (Local));
         return;
      end if;

      Transition
        (Item.Database.all, Work_Id, Quality_Manager.Model.Queued, Quality_Manager.Model.Executing,
         "executing", "authoritative assessment dispatched", "", Result);
      if Result.Kind /= Success then
         return;
      end if;
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
         return;
      elsif not Evidence.Completed
        or else Evidence.Project_Id /= Project.Quality_Project_Id
        or else Evidence.Project_Path /= Project.Canonical_Path
        or else Evidence.Source_Fingerprint /= Plan.Source_Fingerprint
        or else Evidence.Policy_Fingerprint /= Plan.Policy_Fingerprint
        or else Evidence.Toolchain_Fingerprint /= Plan.Toolchain_Fingerprint
      then
         Stop_Work
           (Quality_Manager.Model.Executing, Quality_Manager.Model.Inconclusive,
            "assessment evidence is unfinished, stale, or mismatched");
         return;
      end if;

      --  Retain every completed, identity-matched observation, including an
      --  incomplete result. Completeness determines compliance, not whether
      --  the durable assessment happened.
      Quality_Manager.Storage.Records.Save
        (Item.Database.all,
         Quality_Manager.Storage.Schema.Project'
           (Key => Project,
            Enabled => True,
            Last_Assessment_Run => Evidence.Assessment_Id,
            Last_Source_Fingerprint => Evidence.Source_Fingerprint),
         Result);
      if Result.Kind /= Success then
         return;
      elsif not Evidence.Complete then
         Stop_Work
           (Quality_Manager.Model.Executing, Quality_Manager.Model.Inconclusive,
            "assessment evidence is incomplete");
         return;
      end if;
      Transition
        (Item.Database.all, Work_Id, Quality_Manager.Model.Executing,
         Quality_Manager.Model.Awaiting_Integration, "measured",
         "assessment completed", "assessment:" & Natural'Image (Evidence.Assessment_Id), Result);
      if Result.Kind = Success then
         Transition
           (Item.Database.all, Work_Id, Quality_Manager.Model.Awaiting_Integration,
            Quality_Manager.Model.Awaiting_Assessment, "integration-not-required",
            "measurement work requires no source integration",
            "assessment:" & Natural'Image (Evidence.Assessment_Id), Result);
      end if;
      if Result.Kind = Success and then Evidence.Violations > 0 then
         Quality_Manager.Planning.Generate_Or_Reconcile
           (Item.Database.all, Item.Planner, Project, Positive (Evidence.Assessment_Id),
            To_String (Evidence.Source_Fingerprint), To_String (Evidence.Policy_Fingerprint),
            Quality_Manager.Model.Maintenance,
            Work_Id, Local);
         --  The assessment observation remains valid even when planning is
         --  blocked. Its journal exposes the independent planning failure.
         if Local.Kind /= Success then
            Result := Make_Result (Success);
         end if;
      end if;
      if Result.Kind = Success then
         Transition
           (Item.Database.all, Work_Id, Quality_Manager.Model.Awaiting_Assessment,
            Quality_Manager.Model.Verifying, "verifying",
            "authoritative assessment evidence adopted",
            "assessment:" & Natural'Image (Evidence.Assessment_Id), Result);
      end if;
      if Result.Kind = Success then
         Transition
           (Item.Database.all, Work_Id, Quality_Manager.Model.Verifying,
            Quality_Manager.Model.Verified, "verified",
            (if Evidence.Violations = 0
             then "quality observation is healthy"
             else "quality observation completed with actionable violations"),
            "assessment:" & Natural'Image (Evidence.Assessment_Id), Result);
      end if;
   end Execute_Assessment;

   procedure Execute_Queued_Assessments
     (Item   : in out Context;
      Result : out Operation_Result) is
      Work_Id  : Unbounded_String;
      Resource : Quality_Manager.Scheduler.Work_Resource;
      Found    : Boolean;
   begin
      Result := Make_Result (Success);
      loop
         Quality_Manager.Scheduler.Take_Next (Item.Queue.all, Work_Id, Resource, Found);
         exit when not Found;
         if Resource /= Quality_Manager.Scheduler.Assessment_Resource then
            Quality_Manager.Scheduler.Complete (Item.Queue.all, To_String (Work_Id));
            Result := Make_Result
              (Integrity_Error, "maintenance selected non-assessment work", "qm.maintenance.resource");
            return;
         end if;
         Execute_Assessment (Item, To_String (Work_Id), Result);
         Quality_Manager.Scheduler.Complete (Item.Queue.all, To_String (Work_Id));
         if Result.Kind /= Success then
            return;
         end if;
      end loop;
   end Execute_Queued_Assessments;

   function Unix_Now return Interfaces.Unsigned_64 is
      Value : constant Long_Long_Integer := Long_Long_Integer
        (Ada.Calendar.Conversions.To_Unix_Time_64 (Ada.Calendar.Clock));
   begin
      return (if Value < 0 then 0 else Interfaces.Unsigned_64 (Value));
   end Unix_Now;

   procedure Reconcile_Authorized_Remediations
     (Item             : in out Context;
      Project_Selector : String;
      Now              : Interfaces.Unsigned_64;
      Result           : out Operation_Result) is
      Values    : Quality_Manager.Storage.Entity_Vectors.Vector;
      Work      : Quality_Manager.Storage.Schema.Work_Item;
      Approval  : Quality_Manager.Storage.Schema.Approval;
      Published : Quality_Manager.Storage.Schema.Dispatch;
      Local     : Operation_Result;

      procedure Stop_Work
        (State      : Quality_Manager.Model.Work_State;
         Work_Id    : String;
         Target     : Quality_Manager.Model.Work_State;
         Diagnostic : String) is
      begin
         Quality_Manager.Storage.Transition_Work
           (Item.Database.all, Work_Id, State, Target,
            "event:" & Work_Id & ":maintenance:remediation-stop",
            "autonomous-remediation", Diagnostic, Local);
      end Stop_Work;

      procedure Queue (Value : Quality_Manager.Storage.Schema.Work_Item) is
      begin
         Quality_Manager.Dispatch.Queue_Persisted
           (Item.Database.all, Item.Runner, To_String (Value.Work_Id), Local);
         if Local.Kind = Success then
            Quality_Manager.Scheduler.Enqueue (Item.Queue.all, To_String (Value.Work_Id));
            Local := Quality_Manager.Scheduler.Last_Result (Item.Queue.all);
            if Local.Kind /= Success then
               Result := Local;
            end if;
         elsif Local.Kind = Stale_Evidence then
            Stop_Work
              (Value.State, To_String (Value.Work_Id), Quality_Manager.Model.Blocked, Message (Local));
            if Local.Kind /= Success then
               Result := Local;
            end if;
         elsif Local.Kind not in Not_Ready | Temporarily_Unavailable then
            Stop_Work
              (Value.State, To_String (Value.Work_Id),
               Quality_Manager.Model.Needs_Intervention, Message (Local));
            if Local.Kind /= Success then
               Result := Local;
            end if;
         end if;
      end Queue;
   begin
      Result := Make_Result (Success);
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Work_Item_Record, Values, 100_000, Result);
      if Result.Kind /= Success then
         return;
      end if;
      for Stored of Values loop
         if To_String (Stored.State) in Quality_Manager.Model.Awaiting_Approval'Image |
                                        Quality_Manager.Model.Published'Image |
                                        Quality_Manager.Model.Queued'Image |
                                        Quality_Manager.Model.Executing'Image |
                                        Quality_Manager.Model.Awaiting_Integration'Image
         then
            Quality_Manager.Storage.Decoding.Read_Work
              (Item.Database.all, To_String (Stored.Entity_Key), Work, Local);
            if Local.Kind /= Success then
               Result := Local;
               return;
            end if;
            if Selected
              (Project_Selector, Work.Project.Quality_Project_Id,
               To_String (Work.Project.Canonical_Path))
            then
               if Work.State = Quality_Manager.Model.Awaiting_Approval then
                  Quality_Manager.Storage.Decoding.Find_Approval_For_Work
                    (Item.Database.all, Work, Now, Approval, Local);
                  if Local.Kind = Success then
                     Quality_Manager.Dispatch.Publish_Approved
                       (Item.Database.all, Item.Planner, Work, Approval, Now, Published, Local);
                     if Local.Kind = Success then
                        Work.State := Quality_Manager.Model.Published;
                        Queue (Work);
                        if Result.Kind /= Success then
                           return;
                        end if;
                     else
                        Stop_Work
                          (Work.State, To_String (Work.Work_Id),
                           Quality_Manager.Model.Needs_Intervention, Message (Local));
                        if Local.Kind /= Success then
                           Result := Local;
                           return;
                        end if;
                     end if;
                  elsif Local.Kind not in Not_Found | Authorization_Required then
                     Result := Local;
                     return;
                  end if;
               elsif Work.State in Quality_Manager.Model.Published | Quality_Manager.Model.Queued then
                  Queue (Work);
                  if Result.Kind /= Success then
                     return;
                  end if;
               elsif Work.State in Quality_Manager.Model.Executing |
                                        Quality_Manager.Model.Awaiting_Integration
               then
                  Quality_Manager.Scheduler.Enqueue_Work
                    (Item.Queue.all, To_String (Work.Work_Id),
                     "quality-project:" & To_String (Work.Project.Quality_Database_Id) & ":"
                     & Ada.Strings.Fixed.Trim
                         (Positive'Image (Work.Project.Quality_Project_Id), Ada.Strings.Both),
                     Quality_Manager.Priorities.From_Persisted_Priority (Work.Priority),
                     Stored.Generation,
                     (if Work.State = Quality_Manager.Model.Awaiting_Integration
                      then Quality_Manager.Scheduler.Integration_Resource
                      else Quality_Manager.Scheduler.Agent_Resource));
                  Local := Quality_Manager.Scheduler.Last_Result (Item.Queue.all);
                  if Local.Kind /= Success then
                     Result := Local;
                     return;
                  end if;
               end if;
            end if;
         end if;
      end loop;
      Result := Make_Result (Success);
   end Reconcile_Authorized_Remediations;

   procedure Execute_Queued_Remediations
     (Item   : in out Context;
      Now    : Interfaces.Unsigned_64;
      Result : out Operation_Result) is
      Work_Id  : Unbounded_String;
      Resource : Quality_Manager.Scheduler.Work_Resource;
      Found    : Boolean;
      Snapshot : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Local    : Operation_Result;
      Expires  : Interfaces.Unsigned_64;
   begin
      Result := Make_Result (Success);
      if Interfaces.Unsigned_64 (Item.Maximum_Task_Seconds) + 60
        > Interfaces.Unsigned_64'Last - Now
      then
         Result := Make_Result
           (Integrity_Error, "execution lease expiration is out of range", "qm.maintenance.lease-range");
         return;
      end if;
      Expires := Now + Interfaces.Unsigned_64 (Item.Maximum_Task_Seconds) + 60;
      loop
         Quality_Manager.Scheduler.Take_Next (Item.Queue.all, Work_Id, Resource, Found);
         exit when not Found;
         if Resource not in Quality_Manager.Scheduler.Agent_Resource |
                            Quality_Manager.Scheduler.Integration_Resource
         then
            Quality_Manager.Scheduler.Complete (Item.Queue.all, To_String (Work_Id));
            Result := Make_Result
              (Integrity_Error, "remediation selected a non-agent resource", "qm.maintenance.agent-resource");
            return;
         end if;
         if Resource = Quality_Manager.Scheduler.Agent_Resource then
            Quality_Manager.Dispatch.Execute_Persisted
              (Item.Database.all, Item.Runner, To_String (Work_Id),
               "coordinator:" & Quality_Manager.Storage.Identity (Item.Database.all),
               Now, Expires, Item.Maximum_Task_Seconds, Snapshot, Local);
         else
            Quality_Manager.Dispatch.Integrate_Persisted
              (Item.Database.all, Item.Runner, To_String (Work_Id),
               "coordinator:" & Quality_Manager.Storage.Identity (Item.Database.all),
               Now, Expires, Snapshot, Local);
         end if;
         Quality_Manager.Scheduler.Complete (Item.Queue.all, To_String (Work_Id));
         if Local.Kind not in Success | Not_Ready | Temporarily_Unavailable then
            declare
               Work : Quality_Manager.Storage.Schema.Work_Item;
            begin
               Quality_Manager.Storage.Decoding.Read_Work
                 (Item.Database.all, To_String (Work_Id), Work, Result);
               if Result.Kind /= Success then
                  return;
               elsif Work.State in Quality_Manager.Model.Executing |
                                        Quality_Manager.Model.Awaiting_Integration
               then
                  Stop_Work : declare
                     Target : constant Quality_Manager.Model.Work_State :=
                       (if Local.Kind in Authorization_Required | Integrity_Error | Incompatible_Contract
                        then Quality_Manager.Model.Needs_Intervention
                        else Quality_Manager.Model.Blocked);
                  begin
                     Quality_Manager.Storage.Transition_Work
                       (Item.Database.all, To_String (Work_Id), Work.State, Target,
                        "event:" & To_String (Work_Id) & ":maintenance:execution-stop",
                        "native-execution", Message (Local), Result);
                     if Result.Kind /= Success then
                        return;
                     end if;
                  end Stop_Work;
               end if;
            end;
         end if;
      end loop;
      Result := Make_Result (Success);
   end Execute_Queued_Remediations;

   procedure Verify_Awaiting_Remediations
     (Item             : in out Context;
      Project_Selector : String;
      Result           : out Operation_Result) is
      Values   : Quality_Manager.Storage.Entity_Vectors.Vector;
      Work     : Quality_Manager.Storage.Schema.Work_Item;
      Mapping  : Quality_Manager.Storage.Schema.Dispatch;
      Native   : Quality_Manager.Integrations.Runner.Task_Snapshot;
      Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Plan     : Assessment_Plan;
      Decision : Quality_Manager.Verification.Verification_Decision;
      Request  : Quality_Manager.Verification.Remediation_Request;
      Local    : Operation_Result;
      Execution_Operation : Quality_Manager.Identities.Operation_Id;
   begin
      Result := Make_Result (Success);
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Work_Item_Record, Values, 100_000, Result);
      if Result.Kind /= Success then
         return;
      end if;
      for Stored of Values loop
         if To_String (Stored.State) = Quality_Manager.Model.Awaiting_Assessment'Image then
            Quality_Manager.Storage.Decoding.Read_Work
              (Item.Database.all, To_String (Stored.Entity_Key), Work, Result);
            if Result.Kind /= Success then
               return;
            elsif not Selected
              (Project_Selector, Work.Project.Quality_Project_Id,
               To_String (Work.Project.Canonical_Path))
            then
               null;
            elsif Work.Baseline_Assessment_Run = 0 then
               Quality_Manager.Storage.Transition_Work
                 (Item.Database.all, To_String (Work.Work_Id), Work.State,
                  Quality_Manager.Model.Needs_Intervention,
                  "event:" & To_String (Work.Work_Id) & ":verify:baseline-missing",
                  "verification baseline is unavailable", "", Result);
               if Result.Kind /= Success then
                  return;
               end if;
            else
               Quality_Manager.Storage.Decoding.Read_Active_Dispatch
                 (Item.Database.all, To_String (Work.Global_Remediation), Mapping, Result);
               if Result.Kind /= Success then
                  return;
               end if;
               Execution_Operation := Quality_Manager.Identities.Operation_Identity
                 ("model-runner-execution", To_String (Mapping.Dispatch_Id));
               Quality_Manager.Integrations.Runner.Status
                 (Item.Runner, To_String (Work.Project.Canonical_Path),
                  Quality_Manager.Dispatch.Operation_Name (Execution_Operation), Response);
               Quality_Manager.Integrations.Runner.Decode_Snapshot (Response, Native, Result);
               if Result.Kind /= Success then
                  return;
               elsif Native.Operation_Id /= To_Unbounded_String
                 (Quality_Manager.Dispatch.Operation_Name (Execution_Operation))
                 or else Native.Task_Id /= Mapping.Native_Task_Id
                 or else Native.State /= Quality_Manager.Integrations.Runner.Completed_State
                 or else To_String (Native.Workspace_State) /= "integrated"
                 or else Length (Native.Source_Fingerprint) = 0
               then
                  Result := Make_Result
                    (Integrity_Error, "integrated native evidence is incomplete or mismatched",
                     "qm.maintenance.native-verification");
                  return;
               end if;
               Quality_Manager.Integrations.Quality.Plan_Check
                 (Item.Quality,
                  Ada.Strings.Fixed.Trim
                    (Positive'Image (Work.Project.Quality_Project_Id), Ada.Strings.Both),
                  "", False, Response);
               Decode_Plan (Response, Work.Project, Plan, Result);
               if Result.Kind /= Success then
                  return;
               elsif Plan.Source_Fingerprint /= Native.Source_Fingerprint
                 or else Plan.Policy_Fingerprint /= Work.Effective_Policy_Digest
               then
                  Result := Make_Result
                    (Stale_Evidence, "integrated source or policy changed before verification",
                     "qm.maintenance.verification-drift");
                  return;
               end if;
               Request :=
                 (Work_Id => Work.Work_Id,
                  Project => Work.Project,
                  Project_Selector => To_Unbounded_String
                    (Ada.Strings.Fixed.Trim
                       (Positive'Image (Work.Project.Quality_Project_Id), Ada.Strings.Both)),
                  Profile => Null_Unbounded_String,
                  Candidate_Revision => Native.Source_Fingerprint,
                  Candidate_Source => Native.Source_Fingerprint,
                  Policy_Fingerprint => Plan.Policy_Fingerprint,
                  Toolchain_Fingerprint => Plan.Toolchain_Fingerprint,
                  Baseline_Assessment => Positive (Work.Baseline_Assessment_Run),
                  Improve_Plan_Id => Work.Improve_Plan_Id,
                  Improve_Plan_Revision => Positive (Work.Improve_Revision),
                  Improve_Task_Id => Work.Improve_Task_Id,
                  Contract_Digest => To_Unbounded_String
                    (Quality_Manager.Identities.Canonical_Digest
                       ([Quality_Manager.Identities.Text_Value (To_String (Mapping.Dispatch_Id)),
                         Quality_Manager.Identities.Text_Value (To_String (Native.Source_Fingerprint)),
                         Quality_Manager.Identities.Text_Value (To_String (Plan.Policy_Fingerprint)),
                         Quality_Manager.Identities.Text_Value (To_String (Plan.Toolchain_Fingerprint)),
                         Quality_Manager.Identities.Number_Value
                           (Interfaces.Unsigned_64 (Work.Baseline_Assessment_Run))])),
                  Assessment_Operation => Quality_Manager.Identities.Operation_Identity
                    ("post-remediation-assessment", To_String (Work.Work_Id)),
                  Improve_Operation => Quality_Manager.Identities.Operation_Identity
                    ("post-remediation-verification", To_String (Work.Work_Id)),
                  Attempts_Used => 1,
                  Maximum_Attempts => Item.Maximum_Attempts);
               Quality_Manager.Verification.Verify_Remediation
                 (Item.Database.all, Item.Quality, Item.Planner, Native, Request, Decision, Local);
               if Local.Kind not in Success | Negative_Result then
                  Result := Local;
                  return;
               end if;
            end if;
         end if;
      end loop;
      Result := Make_Result (Success);
   exception
      when Constraint_Error =>
         Result := Make_Result
           (Integrity_Error, "persisted verification identity is out of range",
            "qm.maintenance.verification-range");
   end Verify_Awaiting_Remediations;

   procedure Reconcile_Authorized_Work
     (Item             : in out Context;
      Project_Selector : String;
      Now              : Interfaces.Unsigned_64;
      Result           : out Operation_Result) is
   begin
      if Item.Database = null or else Item.Queue = null then
         Result := Make_Result
           (Not_Ready, "maintenance context is not initialized", "qm.maintenance.not-initialized");
         return;
      end if;
      Reconcile_Authorized_Remediations (Item, Project_Selector, Now, Result);
      if Result.Kind = Success then
         Execute_Queued_Remediations (Item, Now, Result);
      end if;
      if Result.Kind = Success then
         --  A completed agent execution becomes integration work. Rebuild
         --  from durable state so the integration uses its own serialized
         --  scheduler resource and lease.
         Reconcile_Authorized_Remediations (Item, Project_Selector, Now, Result);
      end if;
      if Result.Kind = Success then
         Execute_Queued_Remediations (Item, Now, Result);
      end if;
      if Result.Kind = Success then
         Verify_Awaiting_Remediations (Item, Project_Selector, Result);
      end if;
   end Reconcile_Authorized_Work;

   procedure Run_Cycle
     (Item             : in out Context;
      Project_Selector : String := "";
      Dry_Run          : Boolean := False;
      Result           : out Operation_Result) is
      Identity : Unbounded_String;
      Identity_Result : Operation_Result;
      Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
      Selected_Count : Natural := 0;
   begin
      if Item.Database = null or else Item.Queue = null then
         Result := Make_Result (Not_Ready, "maintenance context is not initialized", "qm.maintenance.context");
         return;
      end if;
      Quality_Manager.Integrations.Quality.Resolve_Database_Identity
        (Item.Quality, Identity, Identity_Result);
      if Identity_Result.Kind /= Success then
         Result := Identity_Result;
         return;
      end if;
      Quality_Manager.Integrations.Quality.List_Projects (Item.Quality, Response);
      if Response.Status.Kind /= Success then
         Result := Response.Status;
         return;
      end if;
      Jsonlib.Parsers.Parse
        (To_String (Response.Document), Document, Error,
         (Max_Depth => 32, Max_Length => 16 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result (Incompatible_Contract, "invalid project inventory JSON", "qm.maintenance.inventory");
         return;
      end if;
      declare
         Root     : constant Jsonlib.Documents.Node := Document.Root;
         Projects : constant Jsonlib.Documents.Node := Document.Member (Root, "projects");
         Version  : Natural;
         Kind     : Unbounded_String;
      begin
         if not Natural_Field (Document, Root, "schema_version", Version)
           or else Version /= 1
           or else not String_Field (Document, Root, "kind", Kind)
           or else To_String (Kind) /= "project-list"
           or else not Jsonlib.Documents.Is_Present (Projects)
           or else Document.Kind (Projects) /= Jsonlib.Documents.Array_Value
         then
            Result := Make_Result
              (Incompatible_Contract, "project inventory contract is incomplete", "qm.maintenance.inventory");
            return;
         end if;
         for Index in 1 .. Document.Length (Projects) loop
            declare
               Node    : constant Jsonlib.Documents.Node := Document.Element (Projects, Index);
               Id      : Natural;
               Path    : Unbounded_String;
               Enabled : Boolean;
               Removed : Boolean;
            begin
               if Document.Kind (Node) /= Jsonlib.Documents.Object_Value
                 or else not Natural_Field (Document, Node, "id", Id)
                 or else Id = 0
                 or else not String_Field (Document, Node, "path", Path)
                 or else Length (Path) = 0
                 or else not Boolean_Field (Document, Node, "enabled", Enabled)
                 or else not Boolean_Field (Document, Node, "removed", Removed)
               then
                  Result := Make_Result
                    (Incompatible_Contract, "invalid project inventory item", "qm.maintenance.project");
                  return;
               end if;
               if not Removed and then Selected (Project_Selector, Positive (Id), To_String (Path)) then
                  Selected_Count := Selected_Count + 1;
                  declare
                     Project : constant Quality_Manager.Identities.Project_Key :=
                       (Identity, Positive (Id), Path);
                     Cycle_Id : constant String := Cycle_Identity
                       (To_String (Identity), Positive (Id), To_String (Path));
                     Work_Id : constant String := Quality_Manager.Identities.Canonical_Digest
                       ([Quality_Manager.Identities.Text_Value ("maintenance-assessment"),
                         Quality_Manager.Identities.Text_Value (Cycle_Id)]);
                     Project_Record : Quality_Manager.Storage.Schema.Project;
                     Cycle : constant Quality_Manager.Storage.Schema.Cycle :=
                       (Cycle_Id => To_Unbounded_String (Cycle_Id),
                        Workflow => Quality_Manager.Model.Maintenance,
                        Trigger => To_Unbounded_String ("manual-or-scheduled"), Project => Project,
                        Policy_Digest => Null_Unbounded_String,
                        State => (if Dry_Run or else not Enabled
                                  then Quality_Manager.Model.Discovered else Quality_Manager.Model.Queued));
                  begin
                     Read_Project_Observation
                       (Item.Database.all, Project, Project_Record, Result);
                     if Result.Kind /= Success then
                        return;
                     end if;
                     Project_Record.Enabled := Enabled;
                     Quality_Manager.Storage.Records.Save (Item.Database.all, Project_Record, Result);
                     if Result.Kind /= Success then
                        return;
                     end if;
                     Quality_Manager.Storage.Records.Save (Item.Database.all, Cycle, Result);
                     if Result.Kind /= Success then
                        return;
                     end if;
                     if not Dry_Run and then Enabled then
                        declare
                           Work : constant Quality_Manager.Storage.Schema.Work_Item :=
                             (Work_Id => To_Unbounded_String (Work_Id),
                              Global_Remediation => To_Unbounded_String ("assessment:" & Cycle_Id),
                              Project => Project, Origin => Quality_Manager.Model.Maintenance,
                              Finding_Identities => To_Unbounded_String ("__assessment__"), Priority => 250,
                              Baseline_Assessment_Run => 0,
                              Improve_Plan_Id => Null_Unbounded_String, Improve_Revision => 0,
                              Improve_Task_Id => Null_Unbounded_String,
                              Improve_Content_SHA256 => Null_Unbounded_String,
                              Planned_Source_Fingerprint => Null_Unbounded_String,
                              Effective_Policy_Digest => Null_Unbounded_String,
                              State => Quality_Manager.Model.Queued,
                              Outcome => Quality_Manager.Model.No_Outcome);
                        begin
                           Quality_Manager.Storage.Records.Save (Item.Database.all, Work, Result);
                           if Result.Kind /= Success then
                              return;
                           end if;
                           Quality_Manager.Scheduler.Enqueue_Work
                             (Item.Queue.all, Work_Id,
                              "quality-project:"
                              & Ada.Strings.Fixed.Trim
                                  (Positive'Image (Positive (Id)), Ada.Strings.Both),
                              Quality_Manager.Priorities.New_Regression,
                              Interfaces.Unsigned_64 (Selected_Count),
                              Quality_Manager.Scheduler.Assessment_Resource);
                           Result := Quality_Manager.Scheduler.Last_Result (Item.Queue.all);
                           if Result.Kind /= Success then
                              return;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end;
      Result :=
        (if Selected_Count = 0
         then Make_Result (Not_Found, "no enabled inventory project matched the selector", "qm.maintenance.selector")
         else Make_Result (Success));
      if Result.Kind = Success and then not Dry_Run then
         Execute_Queued_Assessments (Item, Result);
      end if;
      if Result.Kind = Success and then not Dry_Run then
         declare
            Now : constant Interfaces.Unsigned_64 := Unix_Now;
         begin
            Reconcile_Authorized_Work (Item, Project_Selector, Now, Result);
         end;
      end if;
   exception
      when others =>
         Result := Make_Result (Integrity_Error, "maintenance cycle failed", "qm.maintenance.internal");
   end Run_Cycle;

   procedure Run_Cycle
     (Project_Selector : String := "";
      Dry_Run          : Boolean := False) is
   begin
      Run_Configured_Cycle
        (Project_Selector, Dry_Run, "config/quality-manager.toml", False);
   end Run_Cycle;

   procedure Run_Configured_Cycle
     (Project_Selector : String;
      Dry_Run          : Boolean;
      Config_Path      : String;
      Config_Required  : Boolean) is
      Settings  : Quality_Manager.Config.Settings;
      Store     : aliased Quality_Manager.Storage.Store;
      Scheduler : aliased Quality_Manager.Scheduler.Scheduler_Type;
      Quality   : Quality_Manager.Integrations.Quality.Adapter;
      Planner   : Quality_Manager.Integrations.Improve.Adapter;
      Runner    : Quality_Manager.Integrations.Runner.Adapter;
      Item      : Context;
      Result    : Operation_Result;
      Close_Result : Operation_Result;
   begin
      Quality_Manager.Config.Load (Config_Path, Config_Required, Settings, Result);
      if Result.Kind = Success then
         Quality_Manager.Storage.Open
           (Store, To_String (Settings.Coordinator_Database), True, Result);
      end if;
      if Result.Kind = Success then
         Quality_Manager.Scheduler.Initialize (Scheduler);
         Quality_Manager.Scheduler.Configure
           (Scheduler, Store'Unchecked_Access, Settings.Assessment_Workers, Settings.Agent_Workers);
         Quality_Manager.Integrations.Quality.Initialize
           (Quality, To_String (Settings.Ada_Quality_Executable), To_String (Settings.Quality_Database),
            Policy_Path => To_String (Settings.Quality_Policy));
         Quality_Manager.Integrations.Improve.Initialize
           (Planner, To_String (Settings.Improve_Executable), To_String (Settings.Improve_Config),
            To_String (Settings.Quality_Database), To_String (Settings.Improve_State));
         Quality_Manager.Integrations.Runner.Initialize
           (Runner, To_String (Settings.Model_Runner_Executable));
         Initialize
           (Item, Store'Unchecked_Access, Scheduler'Unchecked_Access, Quality, Planner, Runner,
            Settings.Maximum_Task_Seconds, Settings.Remediation_Attempts);
         Run_Cycle (Item, Project_Selector, Dry_Run or else Settings.Dry_Run, Result);
      end if;
      Quality_Manager.Scheduler.Shutdown (Scheduler);
      Quality_Manager.Storage.Close (Store, Result => Close_Result);
      if Result.Kind = Success and then Close_Result.Kind /= Success then
         Result := Close_Result;
      end if;
      if Result.Kind /= Success then
         raise Maintenance_Error with Message (Result);
      end if;
   end Run_Configured_Cycle;
end Quality_Manager.Maintenance;
