separate (Quality_Manager.Maintenance)
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
   procedure Load_Inventory is
   begin
      if Item.Database = null or else Item.Queue = null then
         Result := Make_Result
           (Not_Ready, "maintenance context is not initialized", "qm.maintenance.context");
         return;
      end if;
      Renew_Coordinator_Lease (Item, Result);
      if Result.Kind = Success then
         Reconcile_Cycles (Item, Result);
      end if;
      if Result.Kind = Success then
         Quality_Manager.Integrations.Quality.Resolve_Database_Identity
           (Item.Quality, Identity, Identity_Result);
         Result := Identity_Result;
      end if;
      if Result.Kind = Success then
         Quality_Manager.Integrations.Quality.List_Projects (Item.Quality, Response);
         Result := Response.Status;
      end if;
      if Result.Kind = Success then
         Jsonlib.Parsers.Parse
           (To_String (Response.Document), Document, Error,
            (Max_Depth => 32, Max_Length => 16 * 1_024 * 1_024,
             Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
         if Jsonlib.Errors.Failed (Error) then
            Result := Make_Result
              (Incompatible_Contract, "invalid project inventory JSON", "qm.maintenance.inventory");
         end if;
      end if;
   end Load_Inventory;

   procedure Validate_Inventory
     (Root     : Jsonlib.Documents.Node;
      Projects : Jsonlib.Documents.Node) is
      Version : Natural;
      Kind    : Unbounded_String;
      Valid   : Boolean := True;
   begin
      if not Natural_Field (Document, Root, "schema_version", Version) then Valid := False;
      elsif Version /= 1 then Valid := False;
      end if;
      if not String_Field (Document, Root, "kind", Kind) then Valid := False;
      elsif To_String (Kind) /= "project-list" then Valid := False;
      end if;
      if not Jsonlib.Documents.Is_Present (Projects) then Valid := False;
      elsif Document.Kind (Projects) /= Jsonlib.Documents.Array_Value then Valid := False;
      end if;
      Result :=
        (if Valid then Make_Result (Success)
         else Make_Result
           (Incompatible_Contract, "project inventory contract is incomplete",
            "qm.maintenance.inventory"));
   end Validate_Inventory;

   procedure Save_Assessment_Work
     (Project : Quality_Manager.Identities.Project_Key;
      Cycle_Id : String;
      Work_Id  : String;
      Id       : Positive) is
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
         "quality-project:" & Ada.Strings.Fixed.Trim (Positive'Image (Id), Ada.Strings.Both),
         Quality_Manager.Priorities.New_Regression,
         Interfaces.Unsigned_64 (Selected_Count),
         Quality_Manager.Scheduler.Assessment_Resource);
      Result := Quality_Manager.Scheduler.Last_Result (Item.Queue.all);
   end Save_Assessment_Work;

   procedure Save_Project
     (Id      : Positive;
      Path    : Unbounded_String;
      Enabled : Boolean) is
      Project : constant Quality_Manager.Identities.Project_Key := (Identity, Id, Path);
      Cycle_Id : constant String := Cycle_Identity
        (To_String (Identity), Id, To_String (Path));
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
      Read_Project_Observation (Item.Database.all, Project, Project_Record, Result);
      if Result.Kind = Success then
         Project_Record.Enabled := Enabled;
         Quality_Manager.Storage.Records.Save (Item.Database.all, Project_Record, Result);
      end if;
      if Result.Kind = Success then
         Quality_Manager.Storage.Records.Save (Item.Database.all, Cycle, Result);
      end if;
      if Result.Kind = Success and then not Dry_Run and then Enabled then
         Save_Assessment_Work (Project, Cycle_Id, Work_Id, Id);
      end if;
   end Save_Project;

   procedure Process_Project (Node : Jsonlib.Documents.Node) is
      Id      : Natural;
      Path    : Unbounded_String;
      Enabled : Boolean;
      Removed : Boolean;
      Valid   : Boolean := True;
   begin
      if Document.Kind (Node) /= Jsonlib.Documents.Object_Value then Valid := False;
      end if;
      if not Natural_Field (Document, Node, "id", Id) then Valid := False;
      elsif Id = 0 then Valid := False;
      end if;
      if not String_Field (Document, Node, "path", Path) then Valid := False;
      elsif Length (Path) = 0 then Valid := False;
      end if;
      if not Boolean_Field (Document, Node, "enabled", Enabled) then Valid := False;
      end if;
      if not Boolean_Field (Document, Node, "removed", Removed) then Valid := False;
      end if;
      if not Valid then
         Result := Make_Result
           (Incompatible_Contract, "invalid project inventory item", "qm.maintenance.project");
      elsif not Removed and then Selected (Project_Selector, Positive (Id), To_String (Path)) then
         Selected_Count := Selected_Count + 1;
         Save_Project (Positive (Id), Path, Enabled);
      end if;
   end Process_Project;

   procedure Process_Inventory is
      Root     : constant Jsonlib.Documents.Node := Document.Root;
      Projects : constant Jsonlib.Documents.Node := Document.Member (Root, "projects");
   begin
      Validate_Inventory (Root, Projects);
      if Result.Kind /= Success then
         return;
      end if;
      for Index in 1 .. Document.Length (Projects) loop
         Process_Project (Document.Element (Projects, Index));
         if Result.Kind /= Success then
            return;
         end if;
      end loop;
   end Process_Inventory;

   procedure Finish_Cycle is
   begin
      if Selected_Count = 0 then
         Result := Make_Result
           (Not_Found, "no enabled inventory project matched the selector", "qm.maintenance.selector");
         return;
      end if;
      Result := Make_Result (Success);
      if not Dry_Run then
         Execute_Queued_Assessments (Item, Result);
      end if;
      if Result.Kind = Success and then not Dry_Run then
         Reconcile_Authorized_Work (Item, Project_Selector, Unix_Now, Result);
      end if;
      if Result.Kind = Success then
         Reconcile_Cycles (Item, Result);
      end if;
   end Finish_Cycle;
begin
   Load_Inventory;
   if Result.Kind /= Success then
      return;
   end if;
   Process_Inventory;
   if Result.Kind /= Success then
      return;
   end if;
   Finish_Cycle;
exception
   when others =>  --  AQ: audited exception boundary
      Result := Make_Result (Integrity_Error, "maintenance cycle failed", "qm.maintenance.internal");
end Run_Cycle;

