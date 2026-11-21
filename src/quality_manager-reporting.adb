with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Jsonlib.Serializers;

package body Quality_Manager.Reporting is
   use type Quality_Manager.Results.Result_Kind;

   function JSON_String (Item : String) return String is
     ('"' & Jsonlib.Serializers.Escape (Item) & '"');

   function Doctor
     (Item   : Quality_Manager.Config.Settings;
      Format : Quality_Manager.CLI.Output_Format;
      Runner : Quality_Manager.Results.Operation_Result) return String is
      Database : constant String := To_String (Item.Coordinator_Database);
      Dry_Run  : constant String := (if Item.Dry_Run then "true" else "false");
      Runner_OK : constant Boolean := Runner.Kind = Quality_Manager.Results.Success;
      Status    : constant String := (if Runner_OK then "ready" else "blocked");
      Native    : constant String := (if Runner_OK then "available" else "unavailable");
      Detail    : constant String := Quality_Manager.Results.Message (Runner);
   begin
      case Format is
         when Quality_Manager.CLI.Terminal_Output =>
            return
              "Quality Manager doctor: " & Status & ASCII.LF
              & "Configuration: valid" & ASCII.LF
              & "Coordinator database: " & Database & ASCII.LF
              & "Dry run: " & Dry_Run & ASCII.LF
              & "Native model_runner execution: " & Native
              & (if Runner_OK then "" else ASCII.LF & "Diagnostic: " & Detail);
         when Quality_Manager.CLI.JSON_Output =>
            return
              "{" & ASCII.LF
              & "  ""schema_version"": 1," & ASCII.LF
              & "  ""status"": """ & Status & """," & ASCII.LF
              & "  ""configuration"": ""valid""," & ASCII.LF
              & "  ""coordinator_database"": " & JSON_String (Database) & "," & ASCII.LF
              & "  ""dry_run"": " & Dry_Run & "," & ASCII.LF
              & "  ""native_execution"": """ & Native & """," & ASCII.LF
              & "  ""diagnostic"": " & JSON_String (Detail) & ASCII.LF
              & "}";
         when Quality_Manager.CLI.Markdown_Output =>
            return
              "# Quality Manager Doctor" & ASCII.LF & ASCII.LF
              & "- Status: " & Status & ASCII.LF
              & "- Configuration: valid" & ASCII.LF
              & "- Coordinator database: `" & Database & "`" & ASCII.LF
              & "- Dry run: " & Dry_Run & ASCII.LF
              & "- Native model_runner execution: " & Native
              & (if Runner_OK then "" else ASCII.LF & "- Diagnostic: " & Detail);
      end case;
   end Doctor;
end Quality_Manager.Reporting;
