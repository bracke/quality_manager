separate (Quality_Manager_Test_Suite)
procedure Test_JSON_Contract (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Result : Quality_Manager.Results.Operation_Result;
begin
   Quality_Manager.Schemas.Validate_Versioned_JSON
     ("{""schema_version"":1}", 1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "matching schema accepted");

   Quality_Manager.Schemas.Validate_Versioned_JSON
     ("{""schema_version"":2}", 1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract, "unknown schema rejected");

   Quality_Manager.Schemas.Validate_Versioned_JSON ("[]", 1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract, "non-object JSON root rejected");

   Quality_Manager.Schemas.Validate_Versioned_JSON
     ("{""schema_version"":1,""schema_version"":1}", 1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate JSON member rejected");

   Quality_Manager.Schemas.Validate_Versioned_JSON
     ("{""schema_version"":1,""kind"":""project-list""}", 1, Result,
      "kind", "project-list");
   Assert (Result.Kind = Quality_Manager.Results.Success, "matching discriminator accepted");

   Quality_Manager.Schemas.Validate_Versioned_JSON
     ("{""schema_version"":1,""kind"":""findings""}", 1, Result,
      "kind", "project-list");
   Assert
     (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
      "mismatched document kind rejected");

   declare
      Long_Text : constant String (1 .. Quality_Manager.Results.Maximum_Diagnostic_Length + 1) :=
        [others => 'x'];
      Bounded : constant Quality_Manager.Results.Operation_Result :=
        Quality_Manager.Results.Make_Result
          (Quality_Manager.Results.Execution_Error, Long_Text, Long_Text);
   begin
      Assert
        (Quality_Manager.Results.Message (Bounded)'Length =
           Quality_Manager.Results.Maximum_Diagnostic_Length,
         "result diagnostics are bounded deterministically");
   end;
end Test_JSON_Contract;

