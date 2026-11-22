with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Serializers;
with Quality_Manager.Config;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Model;
with Quality_Manager.Storage;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Schema;

package body Quality_Manager.Campaigns is
   use type Jsonlib.Documents.Value_Kind;
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Scheduler.Store_Access;
   use type Quality_Manager.Storage.Record_Kind;
   use Quality_Manager.Results;

   type Project_Definition is record
      Key                 : Quality_Manager.Identities.Project_Key;
      Baseline_Assessment : Positive;
   end record;

   package Project_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Project_Definition);
   package Text_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String);

   procedure Initialize
     (Item  : out Context;
      Store : Quality_Manager.Scheduler.Store_Access) is
   begin
      Item.Database := Store;
   end Initialize;

   function Read_File (Path : String; Ok : out Boolean) return String is
      package IO renames Ada.Streams.Stream_IO;
      use type IO.Count;
      use type Ada.Streams.Stream_Element_Offset;
      File : IO.File_Type;
   begin
      IO.Open (File, IO.In_File, Path);
      declare
         Length : constant IO.Count := IO.Size (File);
      begin
         if Length = 0 then
            IO.Close (File);
            Ok := True;
            return "";
         end if;
         declare
            Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Length));
            Last : Ada.Streams.Stream_Element_Offset;
            Text : String (1 .. Natural (Length));
         begin
            IO.Read (File, Data, Last);
            IO.Close (File);
            if Last /= Data'Last then
               Ok := False;
               return "";
            end if;
            for Index in Text'Range loop
               Text (Index) := Character'Val (Data (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
            Ok := True;
            return Text;
         end;
      end;
   exception
      when others =>
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         Ok := False;
         return "";
   end Read_File;

   function String_Field
     (Document : Jsonlib.Documents.Document; Parent : Jsonlib.Documents.Node;
      Name : String; Value : out Unbounded_String) return Boolean is
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
     (Document : Jsonlib.Documents.Document; Parent : Jsonlib.Documents.Node;
      Name : String; Value : out Natural) return Boolean is
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
     (Document : Jsonlib.Documents.Document; Parent : Jsonlib.Documents.Node;
      Name : String; Value : out Boolean) return Boolean is
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

   function JSON_Natural (Document, Name : String) return Natural is
      Prefix : constant String := Character'Val (34) & Name & Character'Val (34) & ":";
      First  : Natural := Ada.Strings.Fixed.Index (Document, Prefix);
      Last   : Natural;
   begin
      if First = 0 then return 0; end if;
      First := First + Prefix'Length;
      Last := First;
      while Last <= Document'Last and then Document (Last) in '0' .. '9' loop
         Last := Last + 1;
      end loop;
      return Natural'Value (Document (First .. Last - 1));
   exception
      when Constraint_Error => return 0;
   end JSON_Natural;

   function JSON_String (Document, Name : String) return String is
      Quote  : constant Character := Character'Val (34);
      Prefix : constant String := Quote & Name & Quote & ":" & Quote;
      First  : Natural := Ada.Strings.Fixed.Index (Document, Prefix);
      Last   : Natural;
   begin
      if First = 0 then return ""; end if;
      First := First + Prefix'Length;
      Last := First;
      while Last <= Document'Last and then Document (Last) /= Quote loop
         Last := Last + 1;
      end loop;
      return (if Last > Document'Last then "" else Document (First .. Last - 1));
   end JSON_String;

   function Registered_Project
     (Item : in out Context; Key : Quality_Manager.Identities.Project_Key;
      Result : out Operation_Result) return Boolean is
      Projects : Quality_Manager.Storage.Entity_Vectors.Vector;
   begin
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Project_Record, Projects, 100_000, Result);
      if Result.Kind /= Success then
         return False;
      end if;
      for Entity of Projects loop
         if To_String (Entity.State) = "ENABLED"
           and then JSON_String (To_String (Entity.Payload), "quality_database_id")
             = To_String (Key.Quality_Database_Id)
           and then JSON_Natural (To_String (Entity.Payload), "quality_project_id")
             = Key.Quality_Project_Id
           and then JSON_String (To_String (Entity.Payload), "canonical_path")
             = To_String (Key.Canonical_Path)
         then
            return True;
         end if;
      end loop;
      return False;
   end Registered_Project;

   procedure Load_Campaign
     (Item        : in out Context;
      Campaign_Id : String;
      Value       : out Quality_Manager.Storage.Schema.Campaign;
      Result      : out Operation_Result) is
      Entity : Quality_Manager.Storage.Stored_Entity;
      Revision : Natural;
   begin
      Value := (others => <>);
      if Item.Database = null then
         Result := Make_Result (Not_Ready, "campaign context is not initialized", "qm.campaign.context");
         return;
      end if;
      Quality_Manager.Storage.Read (Item.Database.all, "campaign:" & Campaign_Id, Entity, Result);
      if Result.Kind /= Success then return; end if;
      if Entity.Kind /= Quality_Manager.Storage.Campaign_Record then
         Result := Make_Result (Integrity_Error, "campaign record kind mismatch", "qm.campaign.record");
         return;
      end if;
      Revision := JSON_Natural (To_String (Entity.Payload), "revision");
      if Revision = 0 then
         Result := Make_Result (Integrity_Error, "campaign revision is invalid", "qm.campaign.revision");
         return;
      end if;
      begin
         Value.State := Quality_Manager.Model.Work_State'Value (To_String (Entity.State));
      exception
         when Constraint_Error =>
            Result := Make_Result (Incompatible_Contract, "unknown campaign state", "qm.campaign.state");
            return;
      end;
      Value.Campaign_Id := To_Unbounded_String (Campaign_Id);
      Value.Definition_Revision := Positive (Revision);
      Value.Definition_Digest := To_Unbounded_String (JSON_String (To_String (Entity.Payload), "definition_digest"));
      Value.Scope := To_Unbounded_String (JSON_String (To_String (Entity.Payload), "scope"));
      Value.Baseline := To_Unbounded_String (JSON_String (To_String (Entity.Payload), "baseline"));
      Value.Budget := JSON_Natural (To_String (Entity.Payload), "budget");
      Value.Used := JSON_Natural (To_String (Entity.Payload), "used");
      Result := Make_Result (Success);
   end Load_Campaign;

   procedure Create
     (Item            : in out Context;
      Definition_Path : String;
      Result          : out Operation_Result) is
      Read_Ok  : Boolean;
   begin
      if Item.Database = null then
         Result := Make_Result (Not_Ready, "campaign context is not initialized", "qm.campaign.context");
         return;
      elsif not Ada.Directories.Exists (Definition_Path) then
         Result := Make_Result (Not_Found, "campaign definition not found", "qm.campaign.definition");
         return;
      end if;
      declare
         Text : constant String := Read_File (Definition_Path, Read_Ok);
         Document : Jsonlib.Documents.Document;
         Error : Jsonlib.Errors.Error_Info;
         Campaign_Id, Target, Priority_Rule, Autonomy_Policy : Unbounded_String;
         Version, Revision, Budget : Natural;
         Projects : Project_Vectors.Vector;
         Indicators : Text_Vectors.Vector;
      begin
         if not Read_Ok or else Text'Length = 0 then
            Result := Make_Result (Invalid_Request, "campaign definition is empty", "qm.campaign.definition");
            return;
         end if;
         Jsonlib.Parsers.Parse
           (Text, Document, Error,
            (Max_Depth => 32, Max_Length => 4 * 1_024 * 1_024,
             Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
         if Jsonlib.Errors.Failed (Error) then
            Result := Make_Result (Invalid_Request, "campaign definition is invalid JSON", "qm.campaign.json");
            return;
         end if;
         declare
            Root : constant Jsonlib.Documents.Node := Document.Root;
            Project_Nodes : constant Jsonlib.Documents.Node := Document.Member (Root, "projects");
            Indicator_Nodes : constant Jsonlib.Documents.Node := Document.Member (Root, "indicators");
         begin
            if not Natural_Field (Document, Root, "schema_version", Version) or else Version /= 1
              or else not String_Field (Document, Root, "campaign_id", Campaign_Id)
              or else Length (Campaign_Id) = 0
              or else not Natural_Field (Document, Root, "definition_revision", Revision) or else Revision = 0
              or else not Natural_Field (Document, Root, "work_budget", Budget)
              or else not String_Field (Document, Root, "target", Target)
              or else To_String (Target) not in "pass" | "pass-or-not-applicable"
              or else not String_Field (Document, Root, "priority_rule", Priority_Rule)
              or else Length (Priority_Rule) = 0
              or else not String_Field (Document, Root, "autonomy_policy_digest", Autonomy_Policy)
              or else Length (Autonomy_Policy) = 0
              or else not Jsonlib.Documents.Is_Present (Project_Nodes)
              or else Document.Kind (Project_Nodes) /= Jsonlib.Documents.Array_Value
              or else Document.Length (Project_Nodes) = 0
              or else not Jsonlib.Documents.Is_Present (Indicator_Nodes)
              or else Document.Kind (Indicator_Nodes) /= Jsonlib.Documents.Array_Value
              or else Document.Length (Indicator_Nodes) = 0
            then
               Result := Make_Result
                 (Incompatible_Contract, "campaign definition contract is incomplete", "qm.campaign.contract");
               return;
            end if;
            for Index in 1 .. Document.Length (Project_Nodes) loop
               declare
                  Node : constant Jsonlib.Documents.Node := Document.Element (Project_Nodes, Index);
                  Database_Id, Path : Unbounded_String;
                  Project_Id, Baseline : Natural;
               begin
                  if Document.Kind (Node) /= Jsonlib.Documents.Object_Value
                    or else not String_Field (Document, Node, "quality_database_id", Database_Id)
                    or else Length (Database_Id) = 0
                    or else not Natural_Field (Document, Node, "project_id", Project_Id) or else Project_Id = 0
                    or else not String_Field (Document, Node, "path", Path) or else Length (Path) = 0
                    or else not Natural_Field (Document, Node, "baseline_assessment", Baseline) or else Baseline = 0
                  then
                     Result := Make_Result
                       (Incompatible_Contract, "invalid campaign project", "qm.campaign.project");
                     return;
                  end if;
                  for Existing of Projects loop
                     if Existing.Key.Quality_Database_Id = Database_Id
                       and then Existing.Key.Quality_Project_Id = Positive (Project_Id)
                     then
                        Result := Make_Result
                          (Invalid_Request, "duplicate campaign project", "qm.campaign.duplicate-project");
                        return;
                     end if;
                  end loop;
                  declare
                     Key : constant Quality_Manager.Identities.Project_Key :=
                       (Database_Id, Positive (Project_Id), Path);
                  begin
                     if not Registered_Project (Item, Key, Result) then
                        if Result.Kind = Success then
                           Result := Make_Result
                             (Not_Found, "campaign project is not enabled in synchronized inventory",
                              "qm.campaign.project-inventory");
                        end if;
                        return;
                     end if;
                  end;
                  Projects.Append
                    (Project_Definition'
                       (Key => (Database_Id, Positive (Project_Id), Path),
                        Baseline_Assessment => Positive (Baseline)));
               end;
            end loop;
            for Index in 1 .. Document.Length (Indicator_Nodes) loop
               declare
                  Node : constant Jsonlib.Documents.Node := Document.Element (Indicator_Nodes, Index);
                  Indicator : Unbounded_String;
               begin
                  if Document.Kind (Node) /= Jsonlib.Documents.String_Value then
                     Result := Make_Result
                       (Incompatible_Contract, "invalid campaign indicator", "qm.campaign.indicator");
                     return;
                  end if;
                  Indicator := To_Unbounded_String (Document.As_String (Node));
                  if Length (Indicator) = 0 or else (for some Existing of Indicators => Existing = Indicator) then
                     Result := Make_Result
                       (Invalid_Request, "empty or duplicate campaign indicator", "qm.campaign.duplicate-indicator");
                     return;
                  end if;
                  Indicators.Append (Indicator);
               end;
            end loop;
         end;
         declare
            Digest : constant String := Quality_Manager.Identities.Canonical_Digest
              ([Quality_Manager.Identities.Text_Value (Text)]);
            Existing : Quality_Manager.Storage.Schema.Campaign;
            Existing_Result : Operation_Result;
            Definition_Key : constant String :=
              "campaign-definition:" & To_String (Campaign_Id) & ":"
              & Ada.Strings.Fixed.Trim (Natural'Image (Revision), Ada.Strings.Both);
            Definition : constant Quality_Manager.Storage.Stored_Entity :=
              (Internal_Id => 1, Kind => Quality_Manager.Storage.Campaign_Record,
               Entity_Key => To_Unbounded_String (Definition_Key), State => To_Unbounded_String (Digest),
               Payload => To_Unbounded_String (Text), Terminal => True, Generation => 1);
         begin
            Load_Campaign (Item, To_String (Campaign_Id), Existing, Existing_Result);
            if Existing_Result.Kind = Success then
               if Revision < Existing.Definition_Revision
                 or else (Revision = Existing.Definition_Revision
                          and then Digest /= To_String (Existing.Definition_Digest))
               then
                  Result := Make_Result
                    (Invalid_Request, "campaign definition revision is stale or conflicting",
                     "qm.campaign.revision-conflict");
                  return;
               elsif Revision = Existing.Definition_Revision then
                  Result := Make_Result (Success);
                  return;
               end if;
            elsif Existing_Result.Kind /= Not_Found then
               Result := Existing_Result;
               return;
            end if;
            Quality_Manager.Storage.Put (Item.Database.all, Definition, Result);
            if Result.Kind /= Success then return; end if;
            declare
               Campaign : constant Quality_Manager.Storage.Schema.Campaign :=
                 (Campaign_Id => Campaign_Id, Definition_Revision => Positive (Revision),
                  Definition_Digest => To_Unbounded_String (Digest),
                  Scope => To_Unbounded_String
                    ("projects=" & Ada.Strings.Fixed.Trim (Natural'Image (Natural (Projects.Length)), Ada.Strings.Both)
                     & ";indicators="
                     & Ada.Strings.Fixed.Trim (Natural'Image (Natural (Indicators.Length)), Ada.Strings.Both)
                     & ";target=" & To_String (Target)
                     & ";priority=" & To_String (Priority_Rule)
                     & ";autonomy=" & To_String (Autonomy_Policy)),
                  Baseline => To_Unbounded_String
                    (Quality_Manager.Identities.Canonical_Digest
                       ([Quality_Manager.Identities.Text_Value ("campaign-baseline"),
                         Quality_Manager.Identities.Text_Value (Text)])),
                  State => Quality_Manager.Model.Discovered, Budget => Budget, Used => 0);
            begin
               Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign, Result);
            end;
            if Result.Kind /= Success then return; end if;
            for Project of Projects loop
               for Indicator of Indicators loop
                  declare
                     Composite : constant String := Quality_Manager.Identities.Canonical_Digest
                       ([Quality_Manager.Identities.Text_Value (To_String (Campaign_Id)),
                         Quality_Manager.Identities.Number_Value (Interfaces.Unsigned_64 (Revision)),
                         Quality_Manager.Identities.Text_Value
                           (To_String (Project.Key.Quality_Database_Id)),
                         Quality_Manager.Identities.Number_Value
                           (Interfaces.Unsigned_64 (Project.Key.Quality_Project_Id)),
                         Quality_Manager.Identities.Text_Value (To_String (Indicator))]);
                     Campaign_Target : constant Quality_Manager.Storage.Schema.Campaign_Target :=
                       (Composite_Key => To_Unbounded_String (Composite), Campaign_Id => Campaign_Id,
                        Definition_Revision => Positive (Revision), Project => Project.Key,
                        Indicator => Indicator,
                        Baseline => To_Unbounded_String
                          (Ada.Strings.Fixed.Trim
                             (Positive'Image (Project.Baseline_Assessment), Ada.Strings.Both)),
                        Target => Target, Latest_Result => To_Unbounded_String ("unknown"));
                  begin
                     Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign_Target, Result);
                     if Result.Kind /= Success then return; end if;
                  end;
               end loop;
            end loop;
         end;
      end;
      Result := Make_Result (Success);
   end Create;

   procedure Change_State
     (Item : in out Context; Campaign_Id : String;
      Expected_One, Expected_Two, New_State : Quality_Manager.Model.Work_State;
      Result : out Operation_Result) is
      Campaign : Quality_Manager.Storage.Schema.Campaign;
   begin
      Load_Campaign (Item, Campaign_Id, Campaign, Result);
      if Result.Kind /= Success then return; end if;
      if Campaign.State not in Expected_One | Expected_Two then
         Result := Make_Result (Not_Ready, "campaign state precondition failed", "qm.campaign.state");
         return;
      end if;
      Campaign.State := New_State;
      Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign, Result);
   end Change_State;

   procedure Start
     (Item : in out Context; Campaign_Id : String; Result : out Operation_Result) is
   begin
      Change_State
        (Item, Campaign_Id, Quality_Manager.Model.Discovered, Quality_Manager.Model.Blocked,
         Quality_Manager.Model.Queued, Result);
   end Start;

   procedure Pause
     (Item : in out Context; Campaign_Id : String; Result : out Operation_Result) is
   begin
      Change_State
        (Item, Campaign_Id, Quality_Manager.Model.Queued, Quality_Manager.Model.Planning,
         Quality_Manager.Model.Blocked, Result);
   end Pause;

   procedure Resume
     (Item : in out Context; Campaign_Id : String; Result : out Operation_Result) is
   begin
      Change_State
        (Item, Campaign_Id, Quality_Manager.Model.Blocked, Quality_Manager.Model.Inconclusive,
         Quality_Manager.Model.Queued, Result);
   end Resume;

   procedure Cancel
     (Item : in out Context; Campaign_Id : String; Result : out Operation_Result) is
      Campaign : Quality_Manager.Storage.Schema.Campaign;
   begin
      Load_Campaign (Item, Campaign_Id, Campaign, Result);
      if Result.Kind /= Success then return; end if;
      if Campaign.State in Quality_Manager.Model.Verified | Quality_Manager.Model.Cancelled then
         Result := Make_Result (Not_Ready, "campaign is already terminal", "qm.campaign.terminal");
         return;
      end if;
      Campaign.State := Quality_Manager.Model.Cancelled;
      Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign, Result);
   end Cancel;

   procedure Reconcile
     (Item : in out Context; Campaign_Id : String; Result : out Operation_Result) is
      Campaign : Quality_Manager.Storage.Schema.Campaign;
      Targets  : Quality_Manager.Storage.Entity_Vectors.Vector;
      Required : Natural := 0;
      Satisfied : Natural := 0;
   begin
      Load_Campaign (Item, Campaign_Id, Campaign, Result);
      if Result.Kind /= Success then return; end if;
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Campaign_Target_Record, Targets, 100_000, Result);
      if Result.Kind /= Success then return; end if;
      for Target of Targets loop
         if JSON_String (To_String (Target.Payload), "campaign_id") = Campaign_Id
           and then JSON_Natural (To_String (Target.Payload), "definition_revision")
             = Campaign.Definition_Revision
         then
            Required := Required + 1;
            if Ada.Strings.Fixed.Index (To_String (Target.State), "satisfied@") = 1 then
               Satisfied := Satisfied + 1;
            end if;
         end if;
      end loop;
      if Required = 0 then
         Result := Make_Result (Integrity_Error, "campaign has no current targets", "qm.campaign.targets");
         return;
      elsif Satisfied = Required then
         Campaign.State := Quality_Manager.Model.Verified;
      elsif Campaign.Budget > 0 and then Campaign.Used >= Campaign.Budget then
         Campaign.State := Quality_Manager.Model.Blocked;
      elsif Campaign.State /= Quality_Manager.Model.Blocked then
         Campaign.State := Quality_Manager.Model.Queued;
      end if;
      Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign, Result);
   end Reconcile;

   procedure Reconcile
     (Item        : in out Context;
      Summary     : Quality_Manager.Integrations.Summary.Adapter;
      Campaign_Id : String;
      Result      : out Operation_Result) is
      Campaign : Quality_Manager.Storage.Schema.Campaign;
      Targets  : Quality_Manager.Storage.Entity_Vectors.Vector;
   begin
      Load_Campaign (Item, Campaign_Id, Campaign, Result);
      if Result.Kind /= Success then
         return;
      elsif Campaign.State in Quality_Manager.Model.Cancelled | Quality_Manager.Model.Superseded
        | Quality_Manager.Model.Failed
      then
         Result := Make_Result
           (Not_Ready, "campaign is terminal", "qm.campaign.terminal");
         return;
      end if;
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Campaign_Target_Record, Targets, 100_000, Result);
      if Result.Kind /= Success then
         return;
      end if;
      for Target of Targets loop
         if JSON_String (To_String (Target.Payload), "campaign_id") = Campaign_Id
           and then JSON_Natural (To_String (Target.Payload), "definition_revision")
             = Campaign.Definition_Revision
         then
            declare
               Project_Id : constant Natural := JSON_Natural
                 (To_String (Target.Payload), "quality_project_id");
               Project_Path : constant String := JSON_String
                 (To_String (Target.Payload), "canonical_path");
               Indicator : constant String := JSON_String (To_String (Target.Payload), "indicator");
               Response  : Quality_Manager.Integrations.JSON_CLI.Response;
               Document  : Jsonlib.Documents.Document;
               Error     : Jsonlib.Errors.Error_Info;
               Run       : Natural := 0;
               Found     : Boolean := False;
               Outcome   : Unbounded_String;
               Applicability_Valid : Boolean := False;
            begin
               if Project_Id = 0 or else Project_Path'Length = 0 or else Indicator'Length = 0 then
                  Result := Make_Result
                    (Integrity_Error, "campaign target identity is incomplete", "qm.campaign.target-identity");
                  return;
               end if;
               Quality_Manager.Integrations.Summary.Read_Project_Status
                 (Summary, Ada.Strings.Fixed.Trim (Natural'Image (Project_Id), Ada.Strings.Both), Response);
               if Response.Status.Kind /= Success then
                  Result := Response.Status;
                  return;
               end if;
               Jsonlib.Parsers.Parse
                 (To_String (Response.Document), Document, Error,
                  (Max_Depth => 64, Max_Length => 16 * 1_024 * 1_024,
                   Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
               if Jsonlib.Errors.Failed (Error) then
                  Result := Make_Result
                    (Incompatible_Contract, "Summary project evidence is invalid JSON",
                     "qm.campaign.summary-json");
                  return;
               end if;
               declare
                  Root       : constant Jsonlib.Documents.Node := Document.Root;
                  Data       : constant Jsonlib.Documents.Node := Document.Member (Root, "data");
                  Project    : constant Jsonlib.Documents.Node := Document.Member (Data, "project");
                  Assessment : constant Jsonlib.Documents.Node := Document.Member (Data, "assessment");
                  Indicators : constant Jsonlib.Documents.Node := Document.Member (Data, "indicators");
                  Report_Project : Natural := 0;
                  Report_Path    : Unbounded_String;
               begin
                  if not Jsonlib.Documents.Is_Present (Data)
                    or else Document.Kind (Data) /= Jsonlib.Documents.Object_Value
                    or else not Jsonlib.Documents.Is_Present (Project)
                    or else Document.Kind (Project) /= Jsonlib.Documents.Object_Value
                    or else not Natural_Field (Document, Project, "project_id", Report_Project)
                    or else Report_Project /= Project_Id
                    or else not String_Field (Document, Project, "path", Report_Path)
                    or else To_String (Report_Path) /= Project_Path
                    or else not Jsonlib.Documents.Is_Present (Assessment)
                    or else Document.Kind (Assessment) /= Jsonlib.Documents.Object_Value
                    or else not Natural_Field (Document, Assessment, "run_id", Run)
                    or else Run = 0
                    or else not Jsonlib.Documents.Is_Present (Indicators)
                    or else Document.Kind (Indicators) /= Jsonlib.Documents.Array_Value
                  then
                     Result := Make_Result
                       (Incompatible_Contract, "Summary project evidence is incomplete or mismatched",
                        "qm.campaign.summary-contract");
                     return;
                  end if;
                  for Index in 1 .. Document.Length (Indicators) loop
                     declare
                        Node       : constant Jsonlib.Documents.Node := Document.Element (Indicators, Index);
                        Id         : Unbounded_String;
                        Compliance : Unbounded_String;
                        Evidence   : Unbounded_String;
                        Applicable : Boolean := False;
                     begin
                        if Document.Kind (Node) = Jsonlib.Documents.Object_Value
                          and then String_Field (Document, Node, "id", Id)
                          and then To_String (Id) = Indicator
                        then
                           if not String_Field (Document, Node, "compliance", Compliance)
                             or else not Boolean_Field (Document, Node, "applicable", Applicable)
                             or else not String_Field (Document, Node, "evidence", Evidence)
                             or else To_String (Compliance) not in
                               "pass" | "violation" | "unknown" | "not-applicable"
                           then
                              Result := Make_Result
                                (Incompatible_Contract, "Summary indicator evidence is incomplete",
                                 "qm.campaign.summary-indicator");
                              return;
                           end if;
                           Outcome := To_Unbounded_String
                             ((if To_String (Compliance) = "unknown" then "incomplete"
                               else To_String (Compliance)));
                           Applicability_Valid :=
                             To_String (Compliance) = "not-applicable"
                             and then not Applicable and then Length (Evidence) > 0;
                           Found := True;
                           exit;
                        end if;
                     end;
                  end loop;
               end;
               if not Found then
                  Result := Make_Result
                    (Incompatible_Contract, "campaign indicator is absent from current Summary evidence",
                     "qm.campaign.summary-indicator-missing");
                  return;
               end if;
               Update_Target
                 (Item, Campaign_Id, Positive (Project_Id), Indicator, Positive (Run),
                  To_String (Outcome), Applicability_Valid, Result);
               if Result.Kind /= Success then
                  return;
               end if;
            end;
         end if;
      end loop;
      Reconcile (Item, Campaign_Id, Result);
   end Reconcile;

   procedure Update_Target
     (Item          : in out Context;
      Campaign_Id   : String;
      Project_Id    : Positive;
      Indicator     : String;
      Assessment_Id : Positive;
      Outcome       : String;
      Result        : out Operation_Result) is
   begin
      Update_Target
        (Item, Campaign_Id, Project_Id, Indicator, Assessment_Id, Outcome, False, Result);
   end Update_Target;

   procedure Update_Target
     (Item                 : in out Context;
      Campaign_Id          : String;
      Project_Id           : Positive;
      Indicator            : String;
      Assessment_Id        : Positive;
      Outcome              : String;
      Applicability_Valid  : Boolean;
      Result               : out Operation_Result) is
      Campaign : Quality_Manager.Storage.Schema.Campaign;
      Targets  : Quality_Manager.Storage.Entity_Vectors.Vector;
   begin
      if Outcome not in "pass" | "violation" | "incomplete" | "not-applicable" then
         Result := Make_Result (Invalid_Request, "unknown campaign target outcome", "qm.campaign.outcome");
         return;
      end if;
      Load_Campaign (Item, Campaign_Id, Campaign, Result);
      if Result.Kind /= Success then return; end if;
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Campaign_Target_Record, Targets, 100_000, Result);
      if Result.Kind /= Success then return; end if;
      for Entity of Targets loop
         if JSON_String (To_String (Entity.Payload), "campaign_id") = Campaign_Id
           and then JSON_Natural (To_String (Entity.Payload), "definition_revision")
             = Campaign.Definition_Revision
           and then JSON_Natural (To_String (Entity.Payload), "quality_project_id") = Project_Id
           and then JSON_String (To_String (Entity.Payload), "indicator") = Indicator
         then
            declare
               Target : Quality_Manager.Storage.Schema.Campaign_Target :=
                 (Composite_Key => To_Unbounded_String
                    (To_String (Entity.Entity_Key) (To_String (Entity.Entity_Key)'First + 16
                       .. To_String (Entity.Entity_Key)'Last)),
                  Campaign_Id => To_Unbounded_String (Campaign_Id),
                  Definition_Revision => Campaign.Definition_Revision,
                  Project =>
                    (To_Unbounded_String (JSON_String (To_String (Entity.Payload), "quality_database_id")),
                     Project_Id,
                     To_Unbounded_String (JSON_String (To_String (Entity.Payload), "canonical_path"))),
                  Indicator => To_Unbounded_String (Indicator),
                  Baseline => To_Unbounded_String (JSON_String (To_String (Entity.Payload), "baseline")),
                  Target => To_Unbounded_String (JSON_String (To_String (Entity.Payload), "target")),
                  Latest_Result => Null_Unbounded_String);
               Allowed_NA : constant Boolean := To_String (Target.Target) = "pass-or-not-applicable";
               Baseline_Run : Natural;
            begin
               begin
                  Baseline_Run := Natural'Value (To_String (Target.Baseline));
               exception
                  when Constraint_Error =>
                     Result := Make_Result
                       (Integrity_Error, "campaign target baseline is invalid", "qm.campaign.baseline");
                     return;
               end;
               if Assessment_Id <= Baseline_Run then
                  Result := Make_Result
                    (Stale_Evidence, "campaign target evidence is not newer than its frozen baseline",
                     "qm.campaign.stale-evidence");
                  return;
               end if;
               Target.Latest_Result := To_Unbounded_String
                 ((if Outcome = "pass"
                    or else
                      (Outcome = "not-applicable" and then Allowed_NA and then Applicability_Valid)
                   then "satisfied@" else Outcome & "@")
                  & Ada.Strings.Fixed.Trim (Positive'Image (Assessment_Id), Ada.Strings.Both));
               Quality_Manager.Storage.Records.Save (Item.Database.all, Target, Result);
               return;
            end;
         end if;
      end loop;
      Result := Make_Result (Not_Found, "campaign target not found", "qm.campaign.target");
   end Update_Target;

   procedure Record_Execution
     (Item : in out Context; Campaign_Id : String; Result : out Operation_Result) is
      Campaign : Quality_Manager.Storage.Schema.Campaign;
   begin
      Load_Campaign (Item, Campaign_Id, Campaign, Result);
      if Result.Kind /= Success then return; end if;
      if Campaign.Budget > 0 and then Campaign.Used >= Campaign.Budget then
         Campaign.State := Quality_Manager.Model.Blocked;
         Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign, Result);
         if Result.Kind = Success then
            Result := Make_Result (Authorization_Required, "campaign work budget exhausted", "qm.campaign.budget");
         end if;
         return;
      end if;
      Campaign.Used := Campaign.Used + 1;
      Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign, Result);
   end Record_Execution;

   function Progress
     (Item        : in out Context;
      Campaign_Id : String;
      Result      : out Operation_Result) return String is
      Campaign  : Quality_Manager.Storage.Schema.Campaign;
      Targets   : Quality_Manager.Storage.Entity_Vectors.Vector;
      Required  : Natural := 0;
      Satisfied : Natural := 0;

      function N (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));
      function Q (Value : String) return String is
        ('"' & Jsonlib.Serializers.Escape (Value) & '"');
   begin
      Load_Campaign (Item, Campaign_Id, Campaign, Result);
      if Result.Kind /= Success then return ""; end if;
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Campaign_Target_Record, Targets, 100_000, Result);
      if Result.Kind /= Success then return ""; end if;
      for Target of Targets loop
         if JSON_String (To_String (Target.Payload), "campaign_id") = Campaign_Id
           and then JSON_Natural (To_String (Target.Payload), "definition_revision")
             = Campaign.Definition_Revision
         then
            Required := Required + 1;
            if Ada.Strings.Fixed.Index (To_String (Target.State), "satisfied@") = 1 then
               Satisfied := Satisfied + 1;
            end if;
         end if;
      end loop;
      Result := Make_Result (Success);
      return
        "{""schema_version"":1,""kind"":""campaign-progress"",""campaign_id"":"
        & Q (Campaign_Id) & ",""definition_revision"":" & N (Campaign.Definition_Revision)
        & ",""state"":" & Q (Quality_Manager.Model.Work_State'Image (Campaign.State))
        & ",""required_targets"":" & N (Required)
        & ",""satisfied_targets"":" & N (Satisfied)
        & ",""work_budget"":" & N (Campaign.Budget)
        & ",""work_used"":" & N (Campaign.Used) & "}";
   end Progress;

   procedure Find_Shared_Work
     (Item               : in out Context;
      Global_Remediation : String;
      Work_Id            : out Unbounded_String;
      Found              : out Boolean;
      Result             : out Operation_Result) is
      Work : Quality_Manager.Storage.Entity_Vectors.Vector;
   begin
      Work_Id := Null_Unbounded_String;
      Found := False;
      if Item.Database = null then
         Result := Make_Result (Not_Ready, "campaign context is not initialized", "qm.campaign.context");
         return;
      end if;
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Work_Item_Record, Work, 100_000, Result);
      if Result.Kind /= Success then return; end if;
      for Entity of Work loop
         if JSON_String (To_String (Entity.Payload), "global_remediation") = Global_Remediation
           and then not Entity.Terminal
         then
            Work_Id := Entity.Entity_Key;
            Found := True;
            return;
         end if;
      end loop;
      Result := Make_Result (Success);
   end Find_Shared_Work;

   type Default_Action is (Create_Action, Start_Action, Pause_Action, Resume_Action, Reconcile_Action);

   procedure Run_Default (Action : Default_Action; Value : String) is
      Settings : Quality_Manager.Config.Settings;
      Store : aliased Quality_Manager.Storage.Store;
      Item : Context;
      Summary : Quality_Manager.Integrations.Summary.Adapter;
      Result, Close_Result : Operation_Result;
   begin
      Quality_Manager.Config.Load ("config/quality-manager.toml", False, Settings, Result);
      if Result.Kind = Success then
         Quality_Manager.Storage.Open (Store, To_String (Settings.Coordinator_Database), True, Result);
      end if;
      if Result.Kind = Success then
         Initialize (Item, Store'Unchecked_Access);
         Quality_Manager.Integrations.Summary.Initialize
           (Summary, To_String (Settings.Ada_Quality_Summary_Executable),
            To_String (Settings.Quality_Database));
         case Action is
            when Create_Action => Create (Item, Value, Result);
            when Start_Action => Start (Item, Value, Result);
            when Pause_Action => Pause (Item, Value, Result);
            when Resume_Action => Resume (Item, Value, Result);
            when Reconcile_Action => Reconcile (Item, Summary, Value, Result);
         end case;
      end if;
      Quality_Manager.Storage.Close (Store, Close_Result);
      if Result.Kind = Success and then Close_Result.Kind /= Success then Result := Close_Result; end if;
      if Result.Kind /= Success then raise Campaign_Error with Message (Result); end if;
   end Run_Default;

   procedure Create (Definition_Path : String) is begin Run_Default (Create_Action, Definition_Path); end Create;
   procedure Start (Campaign_Id : String) is begin Run_Default (Start_Action, Campaign_Id); end Start;
   procedure Pause (Campaign_Id : String) is begin Run_Default (Pause_Action, Campaign_Id); end Pause;
   procedure Resume (Campaign_Id : String) is begin Run_Default (Resume_Action, Campaign_Id); end Resume;
   procedure Reconcile (Campaign_Id : String) is begin Run_Default (Reconcile_Action, Campaign_Id); end Reconcile;
end Quality_Manager.Campaigns;
