with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Jsonlib.Serializers;

package body Quality_Manager.Reporting is
   use type Quality_Manager.Results.Result_Kind;

   function JSON_String (Item : String) return String is
     ('"' & Jsonlib.Serializers.Escape (Item) & '"');

   function Image (Item : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Item), Ada.Strings.Both));

   function View_Name (View : Operational_View) return String is
     (case View is
         when Overall_Status  => "status",
         when Queue_Status    => "queue",
         when Approval_Status => "approvals",
         when Workflow_History => "history",
         when Event_Stream    => "events",
         when Recovery_Status => "recovery");

   procedure Append_Kind
     (Store  : in out Quality_Manager.Storage.Store;
      Kind   : Quality_Manager.Storage.Record_Kind;
      Values : in out Quality_Manager.Storage.Entity_Vectors.Vector;
      Result : out Quality_Manager.Results.Operation_Result) is
      Found : Quality_Manager.Storage.Entity_Vectors.Vector;
   begin
      Quality_Manager.Storage.List (Store, Kind, Found, 100_000, Result);
      if Result.Kind = Quality_Manager.Results.Success then
         for Item of Found loop
            Values.Append (Item);
         end loop;
      end if;
   end Append_Kind;

   function Operational
     (Store  : in out Quality_Manager.Storage.Store;
      View   : Operational_View;
      Format : Quality_Manager.CLI.Output_Format;
      Result : out Quality_Manager.Results.Operation_Result) return String is
      Values : Quality_Manager.Storage.Entity_Vectors.Vector;
      Text   : Unbounded_String;
      First  : Boolean := True;

      procedure Add (Kind : Quality_Manager.Storage.Record_Kind) is
      begin
         if Result.Kind = Quality_Manager.Results.Success then
            Append_Kind (Store, Kind, Values, Result);
         end if;
      end Add;

      function Kind_Name (Kind : Quality_Manager.Storage.Record_Kind) return String is
        (Ada.Strings.Fixed.Trim
           (Quality_Manager.Storage.Record_Kind'Image (Kind), Ada.Strings.Both));
   begin
      Result := Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success);
      case View is
         when Overall_Status =>
            Add (Quality_Manager.Storage.Project_Record);
            Add (Quality_Manager.Storage.Cycle_Record);
            Add (Quality_Manager.Storage.Work_Item_Record);
            Add (Quality_Manager.Storage.Dispatch_Record);
            Add (Quality_Manager.Storage.Campaign_Record);
            Add (Quality_Manager.Storage.Release_Record);
         when Queue_Status =>
            Add (Quality_Manager.Storage.Work_Item_Record);
            Add (Quality_Manager.Storage.Dispatch_Record);
            Add (Quality_Manager.Storage.Attempt_Record);
         when Approval_Status =>
            Add (Quality_Manager.Storage.Approval_Record);
         when Workflow_History =>
            Add (Quality_Manager.Storage.Cycle_Record);
            Add (Quality_Manager.Storage.Campaign_Record);
            Add (Quality_Manager.Storage.Release_Record);
            Add (Quality_Manager.Storage.Verification_Record);
         when Event_Stream =>
            Add (Quality_Manager.Storage.Event_Record);
         when Recovery_Status =>
            Add (Quality_Manager.Storage.Journal_Record);
      end case;
      if Result.Kind /= Quality_Manager.Results.Success then
         return "";
      end if;

      case Format is
         when Quality_Manager.CLI.JSON_Output =>
            Append
              (Text,
               "{""schema_version"":1,""kind"":" & JSON_String (View_Name (View))
               & ",""database_identity"":" & JSON_String (Quality_Manager.Storage.Identity (Store))
               & ",""count"":" & Image (Natural (Values.Length)) & ",""items"":[");
            for Item of Values loop
               if not First then
                  Append (Text, ",");
               end if;
               First := False;
               Append
                 (Text,
                  "{""record_kind"":" & JSON_String (Kind_Name (Item.Kind))
                  & ",""key"":" & JSON_String (To_String (Item.Entity_Key))
                  & ",""state"":" & JSON_String (To_String (Item.State))
                  & ",""terminal"":" & (if Item.Terminal then "true" else "false")
                  & ",""generation"":" & Image (Natural (Item.Generation)) & "}");
            end loop;
            Append (Text, "]}");
         when Quality_Manager.CLI.Terminal_Output =>
            Append
              (Text, "Quality Manager " & View_Name (View) & ": "
               & Image (Natural (Values.Length)) & " record(s)");
            for Item of Values loop
               Append
                 (Text, ASCII.LF & Kind_Name (Item.Kind) & "  "
                  & To_String (Item.Entity_Key) & "  " & To_String (Item.State)
                  & (if Item.Terminal then "  terminal" else ""));
            end loop;
         when Quality_Manager.CLI.Markdown_Output =>
            Append
              (Text, "# Quality Manager " & View_Name (View) & ASCII.LF & ASCII.LF
               & "Database identity: `" & Quality_Manager.Storage.Identity (Store) & "`"
               & ASCII.LF & ASCII.LF
               & "| Kind | Key | State | Terminal |" & ASCII.LF
               & "|---|---|---|---|");
            for Item of Values loop
               Append
                 (Text, ASCII.LF & "| " & Kind_Name (Item.Kind) & " | `"
                  & To_String (Item.Entity_Key) & "` | " & To_String (Item.State)
                  & " | " & (if Item.Terminal then "yes" else "no") & " |");
            end loop;
      end case;
      return To_String (Text);
   exception
      when Constraint_Error =>
         Result := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Integrity_Error,
            "operational report contains an invalid generation", "qm.reporting.generation");
         return "";
   end Operational;

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
