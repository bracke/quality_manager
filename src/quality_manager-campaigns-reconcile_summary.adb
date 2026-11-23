separate (Quality_Manager.Campaigns)
procedure Reconcile_Summary
     (Item        : in out Context;
      Summary     : Quality_Manager.Integrations.Summary.Adapter;
      Campaign_Id : String;
      Result      : out Operation_Result) is
      Campaign : Quality_Manager.Storage.Schema.Campaign;
      Targets  : Quality_Manager.Storage.Entity_Vectors.Vector;

      function Is_Current_Target
        (Target : Quality_Manager.Storage.Stored_Entity) return Boolean is
        (JSON_String (To_String (Target.Payload), "campaign_id") = Campaign_Id
         and then JSON_Natural (To_String (Target.Payload), "definition_revision")
           = Campaign.Definition_Revision);

      procedure Process_Target
        (Target : Quality_Manager.Storage.Stored_Entity;
         Failed : out Boolean) is
         Project_Id   : constant Natural := JSON_Natural
           (To_String (Target.Payload), "quality_project_id");
         Project_Path : constant String := JSON_String
           (To_String (Target.Payload), "canonical_path");
         Indicator    : constant String := JSON_String
           (To_String (Target.Payload), "indicator");
         Response     : Quality_Manager.Integrations.JSON_CLI.Response;
         Document     : Jsonlib.Documents.Document;
         Error        : Jsonlib.Errors.Error_Info;
         Run          : Natural := 0;
         Found        : Boolean := False;
         Outcome      : Unbounded_String;
         Applicability_Valid : Boolean := False;

         function Project_Is_Valid
           (Project : Jsonlib.Documents.Node) return Boolean is
            Report_Project : Natural := 0;
            Report_Path    : Unbounded_String;
         begin
            return Jsonlib.Documents.Is_Present (Project)
              and then Document.Kind (Project) = Jsonlib.Documents.Object_Value
              and then Natural_Field (Document, Project, "project_id", Report_Project)
              and then Report_Project = Project_Id
              and then String_Field (Document, Project, "path", Report_Path)
              and then To_String (Report_Path) = Project_Path;
         end Project_Is_Valid;

         function Assessment_Is_Valid
           (Assessment : Jsonlib.Documents.Node) return Boolean is
           (Jsonlib.Documents.Is_Present (Assessment)
            and then Document.Kind (Assessment) = Jsonlib.Documents.Object_Value
            and then Natural_Field (Document, Assessment, "run_id", Run)
            and then Run > 0);

         function Indicators_Are_Valid
           (Indicators : Jsonlib.Documents.Node) return Boolean is
           (Jsonlib.Documents.Is_Present (Indicators)
            and then Document.Kind (Indicators) = Jsonlib.Documents.Array_Value);

         procedure Read_Indicator
           (Node       : Jsonlib.Documents.Node;
            Is_Matched : out Boolean;
            Is_Invalid : out Boolean) is
            Id         : Unbounded_String;
            Compliance : Unbounded_String;
            Evidence   : Unbounded_String;
            Applicable : Boolean := False;
         begin
            Is_Matched := Document.Kind (Node) = Jsonlib.Documents.Object_Value
              and then String_Field (Document, Node, "id", Id)
              and then To_String (Id) = Indicator;
            Is_Invalid := False;
            if not Is_Matched then
               return;
            end if;
            if not String_Field (Document, Node, "compliance", Compliance)
              or else not Boolean_Field (Document, Node, "applicable", Applicable)
              or else not String_Field (Document, Node, "evidence", Evidence)
              or else To_String (Compliance) not in
                "pass" | "violation" | "unknown" | "not-applicable"
            then
               Is_Invalid := True;
               return;
            end if;
            Outcome := To_Unbounded_String
              ((if To_String (Compliance) = "unknown" then "incomplete"
                else To_String (Compliance)));
            Applicability_Valid :=
              To_String (Compliance) = "not-applicable"
              and then not Applicable
              and then Length (Evidence) > 0;
         end Read_Indicator;

         procedure Read_Report (Failed : out Boolean) is
            Root       : constant Jsonlib.Documents.Node := Document.Root;
            Data       : constant Jsonlib.Documents.Node := Document.Member (Root, "data");
            Project    : constant Jsonlib.Documents.Node := Document.Member (Data, "project");
            Assessment : constant Jsonlib.Documents.Node := Document.Member (Data, "assessment");
            Indicators : constant Jsonlib.Documents.Node := Document.Member (Data, "indicators");
            Matched    : Boolean;
            Invalid    : Boolean;
         begin
            Failed := True;
            if not Jsonlib.Documents.Is_Present (Data)
              or else Document.Kind (Data) /= Jsonlib.Documents.Object_Value
              or else not Project_Is_Valid (Project)
              or else not Assessment_Is_Valid (Assessment)
              or else not Indicators_Are_Valid (Indicators)
            then
               Result := Make_Result
                 (Incompatible_Contract, "Summary project evidence is incomplete or mismatched",
                  "qm.campaign.summary-contract");
               return;
            end if;
            for Index in 1 .. Document.Length (Indicators) loop
               Read_Indicator (Document.Element (Indicators, Index), Matched, Invalid);
               if Invalid then
                  Result := Make_Result
                    (Incompatible_Contract, "Summary indicator evidence is incomplete",
                     "qm.campaign.summary-indicator");
                  return;
               elsif Matched then
                  Found := True;
                  exit;
               end if;
            end loop;
            if not Found then
               Result := Make_Result
                 (Incompatible_Contract, "campaign indicator is absent from current Summary evidence",
                  "qm.campaign.summary-indicator-missing");
               return;
            end if;
            Failed := False;
         end Read_Report;
      begin
         Failed := True;
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
         Read_Report (Failed);
         if Failed then
            return;
         end if;
         Update_Target
           (Item, Campaign_Id, Positive (Project_Id), Indicator, Positive (Run),
            To_String (Outcome), Applicability_Valid, Result);
         Failed := Result.Kind /= Success;
      end Process_Target;

      Failed : Boolean;
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
         if Is_Current_Target (Target) then
            Process_Target (Target, Failed);
            if Failed then
               return;
            end if;
         end if;
      end loop;
      Reconcile (Item, Campaign_Id, Result);
   end Reconcile_Summary;
