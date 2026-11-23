separate (Quality_Manager_Test_Suite)
procedure Test_Operational_Control (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path       : constant String := "/tmp/quality-manager-operations.database";
   Definition : constant String := "/tmp/quality-manager-approval.json";
   Store      : Quality_Manager.Storage.Store;
   Result     : Quality_Manager.Results.Operation_Result;
   Output     : Unbounded_String;
   Loaded     : Quality_Manager.Storage.Stored_Entity;

   procedure Cleanup is
   begin
      if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
      if Ada.Directories.Exists (Definition) then Ada.Directories.Delete_File (Definition); end if;
   end Cleanup;

   procedure Write_Approval (Decision : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Definition);
      Ada.Text_IO.Put
        (File,
         "{""schema_version"":1,""decision"":""" & Decision & """," &
         """approval_id"":""approval-operator-1""," &
         """quality_database_id"":""database-a""," &
         """quality_project_id"":7,""canonical_path"":""/project""," &
         """plan_id"":""PLAN-001"",""plan_revision"":2," &
         """content_sha256"":""content-digest""," &
         """authorized_action"":""publish""," &
         """policy_sha256"":""policy-digest"",""approver"":""operator""," &
         """created_at"":10,""expires_at"":100}");
      Ada.Text_IO.Close (File);
   end Write_Approval;

   procedure Write_Raw (Text : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Definition);
      Ada.Text_IO.Put (File, Text);
      Ada.Text_IO.Close (File);
   end Write_Raw;
begin
   Cleanup;
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "operations store opened");
   Output := To_Unbounded_String
     (Quality_Manager.Reporting.Operational
        (Store, Quality_Manager.Reporting.Overall_Status,
         Quality_Manager.CLI.JSON_Output, Result));
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Ada.Strings.Fixed.Index (To_String (Output), """count"":0") > 0,
      "empty operational status is valid structured output");
   Quality_Manager.Schemas.Validate_Versioned_JSON (To_String (Output), 1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "operational JSON is versioned");

   Quality_Manager.Approvals.Apply_Decision
     (Store, "/tmp/no-such-approval.json", True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing approval record is rejected");
   Write_Raw ("{");
   Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "malformed approval JSON is rejected");
   Write_Raw ("{""schema_version"":1}");
   Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "incomplete approval record is rejected");
   Write_Raw
     ("{""schema_version"":1,""decision"":""approve""," &
      """approval_id"":""approval-negative"",""quality_database_id"":""database-a""," &
      """quality_project_id"":7,""canonical_path"":""/project""," &
      """plan_id"":""PLAN-001"",""plan_revision"":2," &
      """content_sha256"":""content-digest"",""authorized_action"":""publish""," &
      """policy_sha256"":""policy-digest"",""approver"":""operator""," &
      """created_at"":-1,""expires_at"":100}");
   Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "negative approval timestamp rejected");
   Write_Approval ("reject");
   Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Invalid_Request,
      "administrative command cannot contradict signed decision content");
   Write_Approval ("approve");
   Quality_Manager.Approvals.Apply_Decision (Store, Definition, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "exact approval record imported");
   Quality_Manager.Storage.Read (Store, "approval:approval-operator-1", Loaded, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Ada.Strings.Fixed.Index (To_String (Loaded.Payload), """expires_at"":100") > 0,
      "persisted approval retains its audit lifetime");
   Output := To_Unbounded_String
     (Quality_Manager.Reporting.Operational
        (Store, Quality_Manager.Reporting.Approval_Status,
         Quality_Manager.CLI.JSON_Output, Result));
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Ada.Strings.Fixed.Index (To_String (Output), "approval:approval-operator-1") > 0,
      "approval status exposes the durable decision");
   Quality_Manager.Storage.Prepare_Operation
     (Store, 999, "operator-recovery", "intent", "external-999", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "recoverable operation prepared");
   Quality_Manager.Storage.Put
     (Store,
      (Internal_Id => 1,
       Kind => Quality_Manager.Storage.Event_Record,
       Entity_Key => To_Unbounded_String ("event:operator-test"),
       State => To_Unbounded_String ("QUEUED->BLOCKED"),
       Payload => To_Unbounded_String
         ("cause=missing | authorization" & ASCII.LF & "evidence=approval:required"),
       Terminal => True,
       Generation => 1),
      Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "diagnostic event persisted");
   for View in Quality_Manager.Reporting.Operational_View loop
      for Format in Quality_Manager.CLI.Output_Format loop
         Output := To_Unbounded_String
           (Quality_Manager.Reporting.Operational (Store, View, Format, Result));
         Assert
           (Result.Kind = Quality_Manager.Results.Success and then Length (Output) > 0,
            "every operational view supports every output format");
         if Format = Quality_Manager.CLI.JSON_Output then
            Quality_Manager.Schemas.Validate_Versioned_JSON (To_String (Output), 1, Result);
            Assert
              (Result.Kind = Quality_Manager.Results.Success,
               "operational JSON output remains versioned");
            if View = Quality_Manager.Reporting.Recovery_Status then
               Assert
                 (Ada.Strings.Fixed.Index
                    (To_String (Output), "INVOKE_AFTER_REVALIDATION") > 0,
                  "recovery view reports the safe next action");
            elsif View = Quality_Manager.Reporting.Event_Stream then
               Assert
                 (Ada.Strings.Fixed.Index
                    (To_String (Output), """cause"":""missing | authorization""") > 0
                  and then Ada.Strings.Fixed.Index
                    (To_String (Output), """evidence"":""approval:required""") > 0,
                  "JSON event stream exports its persisted cause and evidence");
            end if;
         elsif View = Quality_Manager.Reporting.Event_Stream then
            Assert
              (Ada.Strings.Fixed.Index (To_String (Output), "missing") > 0
               and then Ada.Strings.Fixed.Index (To_String (Output), "approval:required") > 0,
               "human event views export their persisted cause and evidence");
            if Format = Quality_Manager.CLI.Markdown_Output then
               Assert
                 (Ada.Strings.Fixed.Index (To_String (Output), "missing \| authorization") > 0,
                  "Markdown event cells escape table delimiters");
            end if;
         end if;
      end loop;
   end loop;
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Operational_Control;

