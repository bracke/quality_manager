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

package body Quality_Manager.Maintenance is
   use type Jsonlib.Documents.Value_Kind;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Scheduler.Store_Access;
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
                     Project_Record : constant Quality_Manager.Storage.Schema.Project :=
                       (Key => Project, Enabled => Enabled, Last_Assessment_Run => 0,
                        Last_Source_Fingerprint => Null_Unbounded_String);
                     Cycle : constant Quality_Manager.Storage.Schema.Cycle :=
                       (Cycle_Id => To_Unbounded_String (Cycle_Id),
                        Workflow => Quality_Manager.Model.Maintenance,
                        Trigger => To_Unbounded_String ("manual-or-scheduled"), Project => Project,
                        Policy_Digest => Null_Unbounded_String,
                        State => (if Dry_Run or else not Enabled
                                  then Quality_Manager.Model.Discovered else Quality_Manager.Model.Queued));
                  begin
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
           (Quality, To_String (Settings.Ada_Quality_Executable), To_String (Settings.Quality_Database));
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
