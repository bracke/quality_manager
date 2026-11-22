with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Quality_Manager.Config;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Model;
with Quality_Manager.Priorities;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Schema;
with Quality_Manager.Verification;

package body Quality_Manager.Maintenance is
   use type Jsonlib.Documents.Value_Kind;
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
      Quality   : Quality_Manager.Integrations.Quality.Adapter) is
   begin
      Item.Database := Store;
      Item.Queue := Scheduler_Access (Scheduler);
      Item.Quality := Quality;
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
                              Improve_Plan_Id => Null_Unbounded_String, Improve_Revision => 0,
                              Improve_Task_Id => Null_Unbounded_String, State => Quality_Manager.Model.Queued,
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
         Initialize (Item, Store'Unchecked_Access, Scheduler'Unchecked_Access, Quality);
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
