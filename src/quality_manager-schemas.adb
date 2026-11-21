with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;

package body Quality_Manager.Schemas is
   use type Jsonlib.Documents.Value_Kind;
   use Quality_Manager.Results;

   procedure Validate_Versioned_JSON
     (Text             : String;
      Expected_Version : Positive;
      Result           : out Operation_Result;
      Discriminator_Name  : String := "";
      Discriminator_Value : String := "") is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
   begin
      Jsonlib.Parsers.Parse
        (Text,
         Document,
         Error,
         (Max_Depth => 64,
          Max_Length => 4 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Invalid_Request,
            "invalid JSON: " & Jsonlib.Errors.Identifier (Error.Code),
            "qm.json.invalid");
         return;
      end if;

      declare
         Root    : constant Jsonlib.Documents.Node := Document.Root;
         Version : Jsonlib.Documents.Node;
      begin
         if Document.Kind (Root) /= Jsonlib.Documents.Object_Value then
            Result := Make_Result
              (Incompatible_Contract, "JSON root must be an object", "qm.schema.root");
            return;
         end if;
         Version := Document.Member (Root, "schema_version");
         if not Jsonlib.Documents.Is_Present (Version)
           or else Document.Kind (Version) /= Jsonlib.Documents.Integer_Value
         then
            Result := Make_Result
              (Incompatible_Contract,
               "schema_version must be an integer",
               "qm.schema.version-missing");
         elsif Document.As_Integer (Version) /= Long_Long_Integer (Expected_Version) then
            Result := Make_Result
              (Incompatible_Contract,
               "unsupported schema_version" & Document.As_Integer (Version)'Image,
               "qm.schema.version-unsupported");
         elsif Discriminator_Name /= "" then
            declare
               Discriminator : constant Jsonlib.Documents.Node :=
                 Document.Member (Root, Discriminator_Name);
            begin
               if not Jsonlib.Documents.Is_Present (Discriminator)
                 or else Document.Kind (Discriminator) /= Jsonlib.Documents.String_Value
               then
                  Result := Make_Result
                    (Incompatible_Contract,
                     Discriminator_Name & " must be a string",
                     "qm.schema.discriminator-missing");
               elsif Document.As_String (Discriminator) /= Discriminator_Value then
                  Result := Make_Result
                    (Incompatible_Contract,
                     "unexpected " & Discriminator_Name & ": " &
                       Document.As_String (Discriminator),
                     "qm.schema.discriminator-mismatch");
               else
                  Result := Make_Result (Success);
               end if;
            end;
         else
            Result := Make_Result (Success);
         end if;
      end;
   exception
      when others =>
         Result := Make_Result
           (Integrity_Error, "JSON contract validation failed unexpectedly", "qm.schema.internal");
   end Validate_Versioned_JSON;
end Quality_Manager.Schemas;
