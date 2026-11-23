separate (Quality_Manager_Test_Suite)
procedure Test_Doctor_Output (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Settings : constant Quality_Manager.Config.Settings := Quality_Manager.Config.Defaults;
   Runner   : constant Quality_Manager.Results.Operation_Result :=
     Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success);
   Output   : constant String := Quality_Manager.Reporting.Doctor
     (Settings, Quality_Manager.CLI.JSON_Output, Runner);
   Result   : Quality_Manager.Results.Operation_Result;
begin
   Quality_Manager.Schemas.Validate_Versioned_JSON (Output, 1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "doctor JSON is versioned JSON");
   Assert (Ada.Strings.Fixed.Index (Output, """native_execution"": ""available""") > 0,
           "doctor reports the negotiated native execution contract");
   declare
      Failed : constant Quality_Manager.Results.Operation_Result :=
        Quality_Manager.Results.Make_Result
          (Quality_Manager.Results.Incompatible_Contract,
           "runner contract mismatch", "qm.test.runner");
   begin
      for Format in Quality_Manager.CLI.Output_Format loop
         declare
            Blocked : constant String := Quality_Manager.Reporting.Doctor
              (Settings, Format, Failed);
         begin
            Assert
              (Ada.Strings.Fixed.Index (Blocked, "runner contract mismatch") > 0,
               "every doctor format reports a blocked runner diagnostic");
         end;
      end loop;
      Assert
        (Ada.Strings.Fixed.Index
           (Quality_Manager.Reporting.Doctor
              (Settings, Quality_Manager.CLI.Terminal_Output, Runner), "ready") > 0
         and then Ada.Strings.Fixed.Index
           (Quality_Manager.Reporting.Doctor
              (Settings, Quality_Manager.CLI.Markdown_Output, Runner), "ready") > 0,
         "successful doctor output supports terminal and Markdown formats");
   end;
end Test_Doctor_Output;

