with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Jsonlib.Serializers;

package body Quality_Manager.Reporting is
   function JSON_String (Item : String) return String is
     ('"' & Jsonlib.Serializers.Escape (Item) & '"');

   function Doctor
     (Item   : Quality_Manager.Config.Settings;
      Format : Quality_Manager.CLI.Output_Format) return String is
      Database : constant String := To_String (Item.Coordinator_Database);
      Dry_Run  : constant String := (if Item.Dry_Run then "true" else "false");
   begin
      case Format is
         when Quality_Manager.CLI.Terminal_Output =>
            return
              "Quality Manager doctor: ready" & ASCII.LF
              & "Configuration: valid" & ASCII.LF
              & "Coordinator database: " & Database & ASCII.LF
              & "Dry run: " & Dry_Run & ASCII.LF
              & "Write coordination: disabled (Phase 0 contracts pending)";
         when Quality_Manager.CLI.JSON_Output =>
            return
              "{" & ASCII.LF
              & "  ""schema_version"": 1," & ASCII.LF
              & "  ""status"": ""ready""," & ASCII.LF
              & "  ""configuration"": ""valid""," & ASCII.LF
              & "  ""coordinator_database"": " & JSON_String (Database) & "," & ASCII.LF
              & "  ""dry_run"": " & Dry_Run & "," & ASCII.LF
              & "  ""write_coordination"": ""disabled""" & ASCII.LF
              & "}";
         when Quality_Manager.CLI.Markdown_Output =>
            return
              "# Quality Manager Doctor" & ASCII.LF & ASCII.LF
              & "- Status: ready" & ASCII.LF
              & "- Configuration: valid" & ASCII.LF
              & "- Coordinator database: `" & Database & "`" & ASCII.LF
              & "- Dry run: " & Dry_Run & ASCII.LF
              & "- Write coordination: disabled (Phase 0 contracts pending)";
      end case;
   end Doctor;
end Quality_Manager.Reporting;
