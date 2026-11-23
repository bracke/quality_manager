separate (Quality_Manager.Campaigns)
procedure Create
     (Item            : in out Context;
      Definition_Path : String;
      Result          : out Operation_Result) is
      Read_Ok         : Boolean;
      Document        : Jsonlib.Documents.Document;
      Campaign_Id     : Unbounded_String;
      Target          : Unbounded_String;
      Priority_Rule   : Unbounded_String;
      Autonomy_Policy : Unbounded_String;
      Version         : Natural;
      Revision        : Natural;
      Budget          : Natural;
      Projects        : Project_Vectors.Vector;
      Indicators      : Text_Vectors.Vector;

      function Metadata_Is_Valid
        (Root : Jsonlib.Documents.Node) return Boolean is
        (Natural_Field (Document, Root, "schema_version", Version)
         and then Version = 1
         and then String_Field (Document, Root, "campaign_id", Campaign_Id)
         and then Length (Campaign_Id) > 0
         and then Natural_Field (Document, Root, "definition_revision", Revision)
         and then Revision > 0
         and then Natural_Field (Document, Root, "work_budget", Budget));

      function Policy_Is_Valid
        (Root : Jsonlib.Documents.Node) return Boolean is
        (String_Field (Document, Root, "target", Target)
         and then To_String (Target) in "pass" | "pass-or-not-applicable"
         and then String_Field (Document, Root, "priority_rule", Priority_Rule)
         and then Length (Priority_Rule) > 0
         and then String_Field (Document, Root, "autonomy_policy_digest", Autonomy_Policy)
         and then Length (Autonomy_Policy) > 0);

      function Collection_Is_Valid
        (Node : Jsonlib.Documents.Node) return Boolean is
        (Jsonlib.Documents.Is_Present (Node)
         and then Document.Kind (Node) = Jsonlib.Documents.Array_Value
         and then Document.Length (Node) > 0);

      function Read_Project
        (Node        : Jsonlib.Documents.Node;
         Database_Id : out Unbounded_String;
         Path        : out Unbounded_String;
         Project_Id  : out Natural;
         Baseline    : out Natural) return Boolean is
        (Document.Kind (Node) = Jsonlib.Documents.Object_Value
         and then String_Field (Document, Node, "quality_database_id", Database_Id)
         and then Length (Database_Id) > 0
         and then Natural_Field (Document, Node, "project_id", Project_Id)
         and then Project_Id > 0
         and then String_Field (Document, Node, "path", Path)
         and then Length (Path) > 0
         and then Natural_Field (Document, Node, "baseline_assessment", Baseline)
         and then Baseline > 0);

      function Duplicate_Project
        (Database_Id : Unbounded_String;
         Project_Id  : Positive) return Boolean is
      begin
         for Existing of Projects loop
            if Existing.Key.Quality_Database_Id = Database_Id
              and then Existing.Key.Quality_Project_Id = Project_Id
            then
               return True;
            end if;
         end loop;
         return False;
      end Duplicate_Project;

      procedure Load_Project
        (Node   : Jsonlib.Documents.Node;
         Failed : out Boolean) is
         Database_Id : Unbounded_String;
         Path        : Unbounded_String;
         Project_Id  : Natural;
         Baseline    : Natural;
      begin
         Failed := True;
         if not Read_Project (Node, Database_Id, Path, Project_Id, Baseline) then
            Result := Make_Result
              (Incompatible_Contract, "invalid campaign project", "qm.campaign.project");
            return;
         elsif Duplicate_Project (Database_Id, Positive (Project_Id)) then
            Result := Make_Result
              (Invalid_Request, "duplicate campaign project", "qm.campaign.duplicate-project");
            return;
         end if;
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
            Projects.Append
              (Project_Definition'
                 (Key => Key, Baseline_Assessment => Positive (Baseline)));
         end;
         Failed := False;
      end Load_Project;

      procedure Load_Projects
        (Nodes  : Jsonlib.Documents.Node;
         Failed : out Boolean) is
      begin
         Failed := False;
         for Index in 1 .. Document.Length (Nodes) loop
            Load_Project (Document.Element (Nodes, Index), Failed);
            if Failed then
               return;
            end if;
         end loop;
      end Load_Projects;

      procedure Load_Indicators
        (Nodes  : Jsonlib.Documents.Node;
         Failed : out Boolean) is
      begin
         Failed := False;
         for Index in 1 .. Document.Length (Nodes) loop
            declare
               Node      : constant Jsonlib.Documents.Node := Document.Element (Nodes, Index);
               Indicator : Unbounded_String;
            begin
               if Document.Kind (Node) /= Jsonlib.Documents.String_Value then
                  Result := Make_Result
                    (Incompatible_Contract, "invalid campaign indicator", "qm.campaign.indicator");
                  Failed := True;
                  return;
               end if;
               Indicator := To_Unbounded_String (Document.As_String (Node));
               if Length (Indicator) = 0
                 or else (for some Existing of Indicators => Existing = Indicator)
               then
                  Result := Make_Result
                    (Invalid_Request, "empty or duplicate campaign indicator",
                     "qm.campaign.duplicate-indicator");
                  Failed := True;
                  return;
               end if;
               Indicators.Append (Indicator);
            end;
         end loop;
      end Load_Indicators;

      procedure Parse_Definition
        (Text   : String;
         Failed : out Boolean) is
         Error           : Jsonlib.Errors.Error_Info;
         Root            : Jsonlib.Documents.Node;
         Project_Nodes   : Jsonlib.Documents.Node;
         Indicator_Nodes : Jsonlib.Documents.Node;
      begin
         Failed := True;
         Jsonlib.Parsers.Parse
           (Text, Document, Error,
            (Max_Depth => 32, Max_Length => 4 * 1_024 * 1_024,
             Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
         if Jsonlib.Errors.Failed (Error) then
            Result := Make_Result
              (Invalid_Request, "campaign definition is invalid JSON", "qm.campaign.json");
            return;
         end if;
         Root := Document.Root;
         Project_Nodes := Document.Member (Root, "projects");
         Indicator_Nodes := Document.Member (Root, "indicators");
         if not Metadata_Is_Valid (Root)
           or else not Policy_Is_Valid (Root)
           or else not Collection_Is_Valid (Project_Nodes)
           or else not Collection_Is_Valid (Indicator_Nodes)
         then
            Result := Make_Result
              (Incompatible_Contract, "campaign definition contract is incomplete",
               "qm.campaign.contract");
            return;
         end if;
         Load_Projects (Project_Nodes, Failed);
         if Failed then
            return;
         end if;
         Load_Indicators (Indicator_Nodes, Failed);
      end Parse_Definition;

      procedure Check_Revision
        (Digest : String;
         Stop   : out Boolean) is
         Existing        : Quality_Manager.Storage.Schema.Campaign;
         Existing_Result : Operation_Result;
      begin
         Stop := False;
         Load_Campaign (Item, To_String (Campaign_Id), Existing, Existing_Result);
         if Existing_Result.Kind = Success then
            if Revision < Existing.Definition_Revision
              or else (Revision = Existing.Definition_Revision
                       and then Digest /= To_String (Existing.Definition_Digest))
            then
               Result := Make_Result
                 (Invalid_Request, "campaign definition revision is stale or conflicting",
                  "qm.campaign.revision-conflict");
               Stop := True;
            elsif Revision = Existing.Definition_Revision then
               Result := Make_Result (Success);
               Stop := True;
            end if;
         elsif Existing_Result.Kind /= Not_Found then
            Result := Existing_Result;
            Stop := True;
         end if;
      end Check_Revision;

      procedure Save_Targets is
      begin
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
                    (Composite_Key => To_Unbounded_String (Composite),
                     Campaign_Id => Campaign_Id,
                     Definition_Revision => Positive (Revision),
                     Project => Project.Key,
                     Indicator => Indicator,
                     Baseline => To_Unbounded_String
                       (Ada.Strings.Fixed.Trim
                          (Positive'Image (Project.Baseline_Assessment), Ada.Strings.Both)),
                     Target => Target,
                     Latest_Result => To_Unbounded_String ("unknown"));
               begin
                  Quality_Manager.Storage.Records.Save
                    (Item.Database.all, Campaign_Target, Result);
                  exit when Result.Kind /= Success;
               end;
            end loop;
            exit when Result.Kind /= Success;
         end loop;
      end Save_Targets;

      procedure Persist_Definition
        (Text : String;
         Stop : out Boolean) is
         Digest : constant String := Quality_Manager.Identities.Canonical_Digest
           ([Quality_Manager.Identities.Text_Value (Text)]);
         Definition_Key : constant String :=
           "campaign-definition:" & To_String (Campaign_Id) & ":"
           & Ada.Strings.Fixed.Trim (Natural'Image (Revision), Ada.Strings.Both);
         Definition : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1,
            Kind => Quality_Manager.Storage.Campaign_Record,
            Entity_Key => To_Unbounded_String (Definition_Key),
            State => To_Unbounded_String (Digest),
            Payload => To_Unbounded_String (Text),
            Terminal => True,
            Generation => 1);
         Campaign : constant Quality_Manager.Storage.Schema.Campaign :=
           (Campaign_Id => Campaign_Id,
            Definition_Revision => Positive (Revision),
            Definition_Digest => To_Unbounded_String (Digest),
            Scope => To_Unbounded_String
              ("projects="
               & Ada.Strings.Fixed.Trim (Natural'Image (Natural (Projects.Length)), Ada.Strings.Both)
               & ";indicators="
               & Ada.Strings.Fixed.Trim (Natural'Image (Natural (Indicators.Length)), Ada.Strings.Both)
               & ";target=" & To_String (Target)
               & ";priority=" & To_String (Priority_Rule)
               & ";autonomy=" & To_String (Autonomy_Policy)),
            Baseline => To_Unbounded_String
              (Quality_Manager.Identities.Canonical_Digest
                 ([Quality_Manager.Identities.Text_Value ("campaign-baseline"),
                   Quality_Manager.Identities.Text_Value (Text)])),
            State => Quality_Manager.Model.Discovered,
            Budget => Budget,
            Used => 0);
      begin
         Check_Revision (Digest, Stop);
         if Stop then
            return;
         end if;
         Quality_Manager.Storage.Put (Item.Database.all, Definition, Result);
         if Result.Kind /= Success then
            Stop := True;
            return;
         end if;
         Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign, Result);
         if Result.Kind /= Success then
            Stop := True;
            return;
         end if;
         Save_Targets;
         Stop := Result.Kind /= Success;
      end Persist_Definition;

      Failed : Boolean;
   begin
      if Item.Database = null then
         Result := Make_Result
           (Not_Ready, "campaign context is not initialized", "qm.campaign.context");
         return;
      elsif not Ada.Directories.Exists (Definition_Path) then
         Result := Make_Result
           (Not_Found, "campaign definition not found", "qm.campaign.definition");
         return;
      end if;
      declare
         Text : constant String := Read_File (Definition_Path, Read_Ok);
      begin
         if not Read_Ok or else Text'Length = 0 then
            Result := Make_Result
              (Invalid_Request, "campaign definition is empty", "qm.campaign.definition");
            return;
         end if;
         Parse_Definition (Text, Failed);
         if Failed then
            return;
         end if;
         Persist_Definition (Text, Failed);
         if Failed then
            return;
         end if;
      end;
      Result := Make_Result (Success);
   end Create;
