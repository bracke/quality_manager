separate (Quality_Manager.Verification)
procedure Decode_Regression
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Evidence : out Regression_Evidence;
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Status   : Unbounded_String;
      Kind     : Unbounded_String;
      Version  : Natural;

      function Header_Is_Valid
        (Root : Jsonlib.Documents.Node) return Boolean is
        (Natural_Field (Document, Root, "schema_version", Version)
         and then Version = 1
         and then String_Field (Document, Root, "kind", Kind)
         and then To_String (Kind) = "assessment-comparison");

      function Identity_Is_Valid
        (Root : Jsonlib.Documents.Node) return Boolean is
        (Natural_Field (Document, Root, "project_id", Evidence.Project_Id)
         and then Evidence.Project_Id /= 0
         and then String_Field (Document, Root, "status", Status)
         and then Natural_Field (Document, Root, "baseline_id", Evidence.Baseline_Id)
         and then Natural_Field (Document, Root, "current_id", Evidence.Current_Id)
         and then Boolean_Field (Document, Root, "policy_changed", Evidence.Policy_Changed));

      function Change_Is_Valid
        (Item : Jsonlib.Documents.Node) return Boolean is
         Indicator : Unbounded_String;
         Change    : Unbounded_String;
         Before    : Unbounded_String;
         After     : Unbounded_String;
      begin
         return Document.Kind (Item) = Jsonlib.Documents.Object_Value
           and then String_Field (Document, Item, "indicator", Indicator)
           and then String_Field (Document, Item, "change", Change)
           and then String_Field (Document, Item, "before", Before)
           and then String_Field (Document, Item, "after", After)
           and then To_String (Change) in
             "new-violation" | "worsened-metric" | "increased-severity" |
             "failed-gate" | "lost-evidence" | "introduced-finding" |
             "reintroduced-finding" | "policy-induced-change";
      end Change_Is_Valid;
   begin
      Evidence := (others => <>);
      if Response.Status.Kind /= Success then
         Result := Response.Status;
         return;
      end if;
      Parse (To_String (Response.Document), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      declare
         Root    : constant Jsonlib.Documents.Node := Document.Root;
         Changes : constant Jsonlib.Documents.Node := Document.Member (Root, "changes");
      begin
         if not Header_Is_Valid (Root)
           or else not Identity_Is_Valid (Root)
           or else not Jsonlib.Documents.Is_Present (Changes)
           or else Document.Kind (Changes) /= Jsonlib.Documents.Array_Value
         then
            Result := Make_Result
              (Incompatible_Contract, "regression comparison is incomplete", "qm.verification.regression");
            return;
         end if;
         Evidence.Comparable := To_String (Status) = "comparison-available";
         Evidence.Compatibility_Failure := Evidence.Policy_Changed
           or else To_String (Status) in "toolchain-changed" | "no-compatible-baseline";
         Evidence.Regression_Count := Document.Length (Changes);
         for Index in 1 .. Document.Length (Changes) loop
            declare
               Item : constant Jsonlib.Documents.Node := Document.Element (Changes, Index);
            begin
               if not Change_Is_Valid (Item) then
                  Result := Make_Result
                    (Incompatible_Contract,
                     "regression change is malformed",
                     "qm.verification.regression-change");
                  return;
               end if;
            end;
         end loop;
      end;
      Result := Make_Result (Success);
   exception
      when others =>  --  AQ: audited exception boundary
         Evidence := (others => <>);
         Result := Make_Result
           (Incompatible_Contract, "invalid regression comparison", "qm.verification.regression");
   end Decode_Regression;
