with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Jsonlib.Serializers;
with Quality_Manager.Journal;
with Quality_Manager.Recovery;

package body Quality_Manager.Reporting is
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Storage.Record_Kind;

   Cause_Prefix    : constant String := "cause=";
   Evidence_Marker : constant String := ASCII.LF & "evidence=";

   function JSON_String (Item : String) return String is
     ('"' & Jsonlib.Serializers.Escape (Item) & '"');

   function Image (Item : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Item), Ada.Strings.Both));

   function Event_Cause (Item : Quality_Manager.Storage.Stored_Entity) return String is
      Payload  : constant String := To_String (Item.Payload);
      Boundary : constant Natural := Ada.Strings.Fixed.Index (Payload, Evidence_Marker);
      First    : constant Natural := Payload'First + Cause_Prefix'Length;
   begin
      if Item.Kind /= Quality_Manager.Storage.Event_Record
        or else Payload'Length < Cause_Prefix'Length
        or else Payload (Payload'First .. Payload'First + Cause_Prefix'Length - 1) /= Cause_Prefix
        or else Boundary = 0
      then
         return "";
      end if;
      return (if First >= Boundary then "" else Payload (First .. Boundary - 1));
   end Event_Cause;

   function Event_Evidence (Item : Quality_Manager.Storage.Stored_Entity) return String is
      Payload  : constant String := To_String (Item.Payload);
      Boundary : constant Natural := Ada.Strings.Fixed.Index (Payload, Evidence_Marker);
      First    : constant Natural := Boundary + Evidence_Marker'Length;
   begin
      if Item.Kind /= Quality_Manager.Storage.Event_Record or else Boundary = 0 or else First > Payload'Last then
         return "";
      end if;
      return Payload (First .. Payload'Last);
   end Event_Evidence;

   function Markdown_Cell (Value : String) return String is
      Text : Unbounded_String;
   begin
      for Character of Value loop
         case Character is
            when '|' => Append (Text, "\|");
            when ASCII.LF => Append (Text, "<br>");
            when ASCII.CR => null;
            when others => Append (Text, Character);
         end case;
      end loop;
      return To_String (Text);
   end Markdown_Cell;

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
      Recovery_Work : Quality_Manager.Recovery.Recovery_Vectors.Vector;

      procedure Add (Kind : Quality_Manager.Storage.Record_Kind) is
      begin
         if Result.Kind = Quality_Manager.Results.Success then
            Append_Kind (Store, Kind, Values, Result);
         end if;
      end Add;

      function Kind_Name (Kind : Quality_Manager.Storage.Record_Kind) return String is
        (Ada.Strings.Fixed.Trim
           (Quality_Manager.Storage.Record_Kind'Image (Kind), Ada.Strings.Both));

      procedure Select_Values is
      begin
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
               Quality_Manager.Recovery.Reconstruct
                 (Store, 100_000, Recovery_Work, Result);
               if Result.Kind = Quality_Manager.Results.Success then
                  for Item of Recovery_Work loop
                     Values.Append
                       (Quality_Manager.Storage.Stored_Entity'
                          (Internal_Id => 1,
                           Kind        => Quality_Manager.Storage.Journal_Record,
                           Entity_Key  => Item.Operation_Key,
                           State       => To_Unbounded_String
                             (Quality_Manager.Journal.Journal_State'Image (Item.State)),
                           Payload     => To_Unbounded_String
                             (Quality_Manager.Journal.Recovery_Action'Image (Item.Action)),
                           Terminal    => False,
                           Generation  => 1));
                  end loop;
               end if;
         end case;
      end Select_Values;

      function Render_JSON return String is
         Output : Unbounded_String;
         Is_First : Boolean := True;
      begin
         Append
           (Output,
            "{""schema_version"":1,""kind"":" & JSON_String (View_Name (View))
            & ",""database_identity"":" & JSON_String (Quality_Manager.Storage.Identity (Store))
            & ",""count"":" & Image (Natural (Values.Length)) & ",""items"":[");
         for Item of Values loop
            if not Is_First then
               Append (Output, ",");
            end if;
            Is_First := False;
            Append
              (Output,
               "{""record_kind"":" & JSON_String (Kind_Name (Item.Kind))
               & ",""key"":" & JSON_String (To_String (Item.Entity_Key))
               & ",""state"":" & JSON_String (To_String (Item.State))
               & ",""terminal"":" & (if Item.Terminal then "true" else "false")
               & ",""generation"":" & Image (Natural (Item.Generation))
               & (if View = Event_Stream
                  then ",""cause"":" & JSON_String (Event_Cause (Item))
                    & ",""evidence"":" & JSON_String (Event_Evidence (Item))
                  else "")
               & (if View = Recovery_Status
                  then ",""recovery_action"":" & JSON_String (To_String (Item.Payload))
                  else "") & "}");
         end loop;
         Append (Output, "]}");
         return To_String (Output);
      end Render_JSON;

      function Render_Terminal return String is
         Output : Unbounded_String;
      begin
         Append
           (Output, "Quality Manager " & View_Name (View) & ": "
            & Image (Natural (Values.Length)) & " record(s)");
         for Item of Values loop
            Append
              (Output, ASCII.LF & Kind_Name (Item.Kind) & "  "
               & To_String (Item.Entity_Key) & "  " & To_String (Item.State)
               & (if View = Event_Stream then "  cause=" & Event_Cause (Item)
                  & (if Event_Evidence (Item) = "" then ""
                     else "  evidence=" & Event_Evidence (Item))
                  elsif View = Recovery_Status then "  " & To_String (Item.Payload)
                  elsif Item.Terminal then "  terminal" else ""));
         end loop;
         return To_String (Output);
      end Render_Terminal;

      function Render_Markdown return String is
         Output : Unbounded_String;
      begin
         Append
           (Output, "# Quality Manager " & View_Name (View) & ASCII.LF & ASCII.LF
            & "Database identity: `" & Quality_Manager.Storage.Identity (Store) & "`"
            & ASCII.LF & ASCII.LF
            & "| Kind | Key | State | Terminal"
            & (if View = Event_Stream then " | Cause | Evidence" else "") & " |" & ASCII.LF
            & "|---|---|---|---"
            & (if View = Event_Stream then "|---|---" else "") & "|");
         for Item of Values loop
            Append
              (Output, ASCII.LF & "| " & Kind_Name (Item.Kind) & " | `"
               & To_String (Item.Entity_Key) & "` | " & To_String (Item.State)
               & " | " & (if Item.Terminal then "yes" else "no")
               & (if View = Event_Stream
                  then " | " & Markdown_Cell (Event_Cause (Item))
                    & " | " & Markdown_Cell (Event_Evidence (Item))
                  else "") & " |");
         end loop;
         return To_String (Output);
      end Render_Markdown;
   begin
      Result := Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success);
      Select_Values;
      if Result.Kind /= Quality_Manager.Results.Success then
         return "";
      end if;

      case Format is
         when Quality_Manager.CLI.JSON_Output =>
            return Render_JSON;
         when Quality_Manager.CLI.Terminal_Output =>
            return Render_Terminal;
         when Quality_Manager.CLI.Markdown_Output =>
            return Render_Markdown;
      end case;
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
