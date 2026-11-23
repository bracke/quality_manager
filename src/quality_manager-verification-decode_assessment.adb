separate (Quality_Manager.Verification)
procedure Decode_Assessment
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Assessment_Evidence;
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Status   : Unbounded_String;
      Version  : Natural;
      type Indicator_Array is array (Positive range 1 .. 33) of Unbounded_String;
      Indicators : Indicator_Array := [others => Null_Unbounded_String];

      function Valid_Indicator (Value : String) return Boolean is
        (Value'Length = 6
         and then (for all Index in Value'First .. Value'First + 2 => Value (Index) in 'A' .. 'Z')
         and then Value (Value'First + 3) = '-'
         and then (for all Index in Value'First + 4 .. Value'Last => Value (Index) in '0' .. '9'));

      procedure Validate_Header
        (Root       : Jsonlib.Documents.Node;
         Results    : Jsonlib.Documents.Node;
         Executions : Jsonlib.Documents.Node;
         Valid      : in out Boolean) is
      begin
         if not Natural_Field (Document, Root, "schema_version", Version) then Valid := False;
         elsif Version /= 1 then Valid := False;
         end if;
         if not Natural_Field (Document, Root, "assessment_id", Evidence.Assessment_Id) then Valid := False;
         end if;
         if not Natural_Field (Document, Root, "project_id", Evidence.Project_Id) then Valid := False;
         end if;
         if not String_Field (Document, Root, "project_path", Evidence.Project_Path) then Valid := False;
         end if;
         if not String_Field (Document, Root, "source_fingerprint", Evidence.Source_Fingerprint) then Valid := False;
         end if;
         if not String_Field (Document, Root, "policy_fingerprint", Evidence.Policy_Fingerprint) then Valid := False;
         end if;
         if not String_Field
           (Document, Root, "toolchain_fingerprint", Evidence.Toolchain_Fingerprint)
         then
            Valid := False;
         end if;
         if not String_Field (Document, Root, "status", Status) then Valid := False;
         end if;
         if not Jsonlib.Documents.Is_Present (Results) then Valid := False;
         elsif Document.Kind (Results) /= Jsonlib.Documents.Array_Value then Valid := False;
         elsif Document.Length (Results) /= 33 then Valid := False;
         end if;
         if not Jsonlib.Documents.Is_Present (Executions) then Valid := False;
         elsif Document.Kind (Executions) /= Jsonlib.Documents.Array_Value then Valid := False;
         end if;
      end Validate_Header;

      procedure Validate_Indicator_Structure
        (Index       : Positive;
         Indicator   : Unbounded_String;
         Measurement : Jsonlib.Documents.Node;
         Findings    : Jsonlib.Documents.Node) is
      begin
         if not Valid_Indicator (To_String (Indicator)) then
            Evidence.Complete := False;
         elsif (for some Prior in 1 .. Index - 1 => Indicators (Prior) = Indicator) then
            Evidence.Complete := False;
         elsif not Jsonlib.Documents.Is_Present (Measurement) then
            Evidence.Complete := False;
         elsif Document.Kind (Measurement) /= Jsonlib.Documents.Object_Value then
            Evidence.Complete := False;
         elsif not Jsonlib.Documents.Is_Present (Findings) then
            Evidence.Complete := False;
         elsif Document.Kind (Findings) /= Jsonlib.Documents.Array_Value then
            Evidence.Complete := False;
         end if;
         Indicators (Index) := Indicator;
      end Validate_Indicator_Structure;

      procedure Apply_Compliance (Compliance : String) is
      begin
         if Compliance = "violation" then
            Evidence.Violations := Evidence.Violations + 1;
         elsif Compliance not in "pass" | "not-applicable" then
            Evidence.Complete := False;
         end if;
      end Apply_Compliance;

      procedure Apply_Special_Indicator
        (Indicator   : String;
         Compliance  : String;
         Applicable  : Boolean;
         Measurement : Jsonlib.Documents.Node) is
      begin
         if Indicator = "TST-03" then
            if Jsonlib.Documents.Is_Present (Measurement)
              and then Document.Kind (Measurement) = Jsonlib.Documents.Object_Value
            then
               if not Natural_Field
                 (Document, Measurement, "basis_points", Evidence.Coverage_Basis_Points)
               then
                  Evidence.Complete := False;
               end if;
            end if;
         elsif Indicator = "PRF-01" then
            Evidence.Proof_Applicable := Applicable;
            Evidence.Proof_Passed := not Applicable or else Compliance = "pass";
         end if;
      end Apply_Special_Indicator;

      procedure Apply_Applicability
        (Applicable : Boolean;
         Execution  : String;
         Compliance : String) is
      begin
         if Applicable then
            if Execution /= "succeeded" then
               Evidence.Complete := False;
            elsif Compliance = "not-applicable" then
               Evidence.Complete := False;
            end if;
         elsif Compliance /= "not-applicable" then
            Evidence.Complete := False;
         end if;
      end Apply_Applicability;

      procedure Process_Indicator
        (Index : Positive;
         Item  : Jsonlib.Documents.Node) is
         Indicator    : Unbounded_String;
         Compliance   : Unbounded_String;
         Execution    : Unbounded_String;
         Summary      : Unbounded_String;
         Evidence_Text : Unbounded_String;
         Applicable   : Boolean;
         Measurement  : Jsonlib.Documents.Node;
         Findings     : Jsonlib.Documents.Node;
         Valid        : Boolean := True;
      begin
         if Document.Kind (Item) /= Jsonlib.Documents.Object_Value then Valid := False;
         end if;
         if not String_Field (Document, Item, "indicator", Indicator) then Valid := False;
         end if;
         if not String_Field (Document, Item, "compliance", Compliance) then Valid := False;
         end if;
         if not String_Field (Document, Item, "execution", Execution) then Valid := False;
         end if;
         if not Boolean_Field (Document, Item, "applicable", Applicable) then Valid := False;
         end if;
         if not String_Field (Document, Item, "summary", Summary) then Valid := False;
         end if;
         if not String_Field (Document, Item, "evidence", Evidence_Text) then Valid := False;
         end if;
         if not Valid then
            Evidence.Complete := False;
            return;
         end if;
         Measurement := Document.Member (Item, "measurement");
         Findings := Document.Member (Item, "findings");
         Validate_Indicator_Structure (Index, Indicator, Measurement, Findings);
         Apply_Compliance (To_String (Compliance));
         Apply_Special_Indicator
           (To_String (Indicator), To_String (Compliance), Applicable, Measurement);
         Apply_Applicability (Applicable, To_String (Execution), To_String (Compliance));
      end Process_Indicator;
   begin
      Evidence := (others => <>);
      if Response.Status.Kind not in Success | Negative_Result | Stale_Evidence then
         Result := Response.Status;
         return;
      end if;
      Parse (To_String (Response.Document), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      declare
         Root       : constant Jsonlib.Documents.Node := Document.Root;
         Results    : constant Jsonlib.Documents.Node := Document.Member (Root, "results");
         Executions : constant Jsonlib.Documents.Node := Document.Member (Root, "executions");
         Valid      : Boolean := True;
      begin
         Validate_Header (Root, Results, Executions, Valid);
         if not Valid then
            Result := Make_Result
              (Incompatible_Contract, "assessment evidence is incomplete",
               "qm.verification.assessment");
            return;
         end if;
         Evidence.Completed := To_String (Status) in "ASSESSMENT_COMPLETED" | "completed";
         Evidence.Indicator_Count := Document.Length (Results);
         Evidence.Complete := Evidence.Completed;
         for Index in 1 .. Document.Length (Results) loop
            Process_Indicator (Index, Document.Element (Results, Index));
         end loop;
      end;
      Result := Make_Result (Success);
   exception
      when others =>  --  AQ: audited exception boundary
         Evidence := (others => <>);
         Result := Make_Result
           (Incompatible_Contract, "invalid assessment evidence", "qm.verification.assessment");
   end Decode_Assessment;
