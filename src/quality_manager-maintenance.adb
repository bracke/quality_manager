with Ada.Calendar;
with Ada.Calendar.Conversions;
with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Database.UUIDs;
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

   function Unix_Now return Interfaces.Unsigned_64;

   procedure Renew_Coordinator_Lease
     (Item   : in out Context;
      Result : out Operation_Result);

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

   function JSON_String (Document, Name : String) return String is
      Quote  : constant Character := Character'Val (34);
      Prefix : constant String := Quote & Name & Quote & ":" & Quote;
      First  : Natural := Ada.Strings.Fixed.Index (Document, Prefix);
      Last   : Natural;
   begin
      if First = 0 then
         return "";
      end if;
      First := First + Prefix'Length;
      Last := First;
      while Last <= Document'Last and then Document (Last) /= Quote loop
         Last := Last + 1;
      end loop;
      return (if Last > Document'Last then "" else Document (First .. Last - 1));
   end JSON_String;

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

      procedure Validate_Header
        (Root     : Jsonlib.Documents.Node;
         Projects : Jsonlib.Documents.Node;
         Valid    : in out Boolean) is
      begin
         if not Natural_Field (Document, Root, "schema_version", Version) then Valid := False;
         elsif Version /= 1 then Valid := False;
         end if;
         if not String_Field (Document, Root, "kind", Kind) then Valid := False;
         elsif To_String (Kind) /= "check-plan" then Valid := False;
         end if;
         if not Jsonlib.Documents.Is_Present (Projects) then Valid := False;
         elsif Document.Kind (Projects) /= Jsonlib.Documents.Array_Value then Valid := False;
         elsif Document.Length (Projects) /= 1 then Valid := False;
         end if;
      end Validate_Header;

      procedure Validate_Project
        (Node  : Jsonlib.Documents.Node;
         Valid : in out Boolean) is
      begin
         if Document.Kind (Node) /= Jsonlib.Documents.Object_Value then Valid := False;
         end if;
         if not Natural_Field (Document, Node, "project_id", Id) then Valid := False;
         elsif Id /= Project.Quality_Project_Id then Valid := False;
         end if;
         if not String_Field (Document, Node, "path", Path) then Valid := False;
         elsif Path /= Project.Canonical_Path then Valid := False;
         end if;
         if not String_Field (Document, Node, "action", Action) then Valid := False;
         elsif To_String (Action) not in "assess" | "reuse" then Valid := False;
         end if;
      end Validate_Project;

      procedure Validate_Fingerprints
        (Node  : Jsonlib.Documents.Node;
         Valid : in out Boolean) is
      begin
         if not String_Field (Document, Node, "source_fingerprint", Plan.Source_Fingerprint) then
            Valid := False;
         elsif Length (Plan.Source_Fingerprint) = 0 then
            Valid := False;
         end if;
         if not String_Field (Document, Node, "policy_fingerprint", Plan.Policy_Fingerprint) then
            Valid := False;
         elsif Length (Plan.Policy_Fingerprint) = 0 then
            Valid := False;
         end if;
         if not String_Field (Document, Node, "toolchain_fingerprint", Plan.Toolchain_Fingerprint) then
            Valid := False;
         elsif Length (Plan.Toolchain_Fingerprint) = 0 then
            Valid := False;
         end if;
      end Validate_Fingerprints;
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
         Valid    : Boolean := True;
      begin
         Validate_Header (Root, Projects, Valid);
         if not Valid then
            Result := Make_Result
              (Incompatible_Contract, "assessment plan contract is incomplete", "qm.maintenance.plan");
            return;
         end if;
         declare
            Node : constant Jsonlib.Documents.Node := Document.Element (Projects, 1);
         begin
            Validate_Project (Node, Valid);
            Validate_Fingerprints (Node, Valid);
            if not Valid then
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
      when others =>  --  AQ: audited exception boundary
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
      when others =>  --  AQ: audited exception boundary
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
      when others =>  --  AQ: audited exception boundary
         Result := Make_Result
           (Integrity_Error, "persisted project observation is malformed", "qm.maintenance.project-observation");
   end Read_Project_Observation;

   procedure Execute_Assessment
     (Item    : in out Context;
      Work_Id : String;
      Result  : out Operation_Result) is separate;

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

   procedure Renew_Coordinator_Lease
     (Item   : in out Context;
      Result : out Operation_Result) is
      Now      : constant Interfaces.Unsigned_64 := Unix_Now;
      Duration : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Item.Lease_Seconds);
   begin
      if Length (Item.Lease_Owner) = 0 then
         Result := Make_Result (Success);
      elsif Duration > Interfaces.Unsigned_64'Last - Now then
         Result := Make_Result
           (Integrity_Error, "coordinator lease expiration is out of range", "qm.maintenance.coordinator-lease");
      else
         Quality_Manager.Storage.Acquire_Exclusive_Lease
           (Item.Database.all, "active-coordinator", To_String (Item.Lease_Owner),
            Now, Now + Duration, Item.Lease_Generation, Result);
      end if;
   end Renew_Coordinator_Lease;

   procedure Reconcile_Authorized_Remediations
     (Item             : in out Context;
      Project_Selector : String;
      Now              : Interfaces.Unsigned_64;
      Result           : out Operation_Result) is separate;

   procedure Execute_Queued_Remediations
     (Item   : in out Context;
      Now    : Interfaces.Unsigned_64;
      Result : out Operation_Result) is separate;

   procedure Verify_Awaiting_Remediations
     (Item             : in out Context;
      Project_Selector : String;
      Result           : out Operation_Result) is separate;

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

   procedure Reconcile_Cycles
     (Item   : in out Context;
      Result : out Operation_Result) is separate;

   procedure Run_Cycle
     (Item             : in out Context;
      Project_Selector : String := "";
      Dry_Run          : Boolean := False;
      Result           : out Operation_Result) is separate;

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
      Config_Required  : Boolean) is separate;
end Quality_Manager.Maintenance;
