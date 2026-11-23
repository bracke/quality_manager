with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Calendar;
with Ada.Calendar.Conversions;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Database.UUIDs;
with Interfaces;
with Hostkit;
with Hostkit.Process;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Serializers;
with Quality_Manager.Config;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Integrations.Runner;
with Quality_Manager.Model;
with Quality_Manager.Reproducibility;
with Quality_Manager.Journal;
with Quality_Manager.Storage;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Schema;

package body Quality_Manager.Releases is
   use type Jsonlib.Documents.Value_Kind;
   use type Interfaces.Unsigned_64;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Identities.Operation_Id;
   use type Quality_Manager.Journal.Journal_State;
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Scheduler.Store_Access;
   use type Quality_Manager.Storage.Record_Kind;
   use Quality_Manager.Results;

   function Q (Value : String) return String is
     ('"' & Jsonlib.Serializers.Escape (Value) & '"');

   function N (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function B (Value : Boolean) return String is (if Value then "true" else "false");

   Evidence_Chunk_Size : constant Positive := 400;

   function Evidence_Key (Release_Id : String; Generation : Positive) return String is
     ("release-evidence:" & Release_Id & ":" & N (Generation));

   function Evidence_Chunk_Key
     (Release_Id : String;
      Generation : Positive;
      Chunk      : Positive) return String is
     ("release-evidence-chunk:" & Release_Id & ":" & N (Generation) & ":" & N (Chunk));

   function Check_Failure_Message
     (Checks          : Check_Results;
      Expected_Commit : String) return String is
   begin
      return
        "local release checks failed: commit="
        & Boolean'Image (To_String (Checks.Candidate_Commit) = Expected_Commit)
        & " (observed=" & Q (To_String (Checks.Candidate_Commit))
        & ", expected=" & Q (Expected_Commit) & ")"
        & ", build=" & Boolean'Image (Checks.Clean_Build)
        & ", reproducible=" & Boolean'Image (Checks.Reproducible_Build)
        & ", source=" & Boolean'Image (Checks.Source_Unchanged)
        & ", clean=" & Boolean'Image (Checks.Git_Clean)
        & ", tests=" & Boolean'Image (Checks.AUnit_Passed)
        & ", proof=" & Boolean'Image (not Checks.Proof_Applicable or else Checks.GNATprove_Passed);
   end Check_Failure_Message;

   function Qualification_Operation
     (Release_Id : String;
      Generation : Positive;
      Purpose    : String) return Quality_Manager.Identities.Operation_Id is
      Digest : constant String := Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value ("release-qualification-v1"),
          Quality_Manager.Identities.Text_Value (Purpose),
          Quality_Manager.Identities.Text_Value (Release_Id),
          Quality_Manager.Identities.Number_Value (Interfaces.Unsigned_64 (Generation))]);
      Value : Interfaces.Unsigned_64 := 0;
   begin
      for Element of Digest (Digest'First .. Digest'First + 15) loop
         Value := Value * 16
           + Interfaces.Unsigned_64
             (if Element in '0' .. '9'
              then Character'Pos (Element) - Character'Pos ('0')
              else Character'Pos (Element) - Character'Pos ('a') + 10);
      end loop;
      return Quality_Manager.Identities.Operation_Id
        ((if Value = 0 then 1 else Value));
   end Qualification_Operation;

   function Trim_Output (Value : String) return String is
      First : Natural := Value'First;
      Last  : Natural := Value'Last;
   begin
      while First <= Last
        and then Value (First) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
      loop
         First := First + 1;
      end loop;
      while Last >= First
        and then Value (Last) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
      loop
         Last := Last - 1;
      end loop;
      return (if First > Last then "" else Value (First .. Last));
   end Trim_Output;

   function JSON_Boolean (Document, Name : String) return Boolean is
      Prefix : constant String := Character'Val (34) & Name & Character'Val (34) & ":true";
   begin
      return Ada.Strings.Fixed.Index (Document, Prefix) > 0;
   end JSON_Boolean;

   procedure Execute_Simple
     (Executable : String;
      Arguments  : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Directory  : String;
      Output     : out Unbounded_String;
      Result     : out Operation_Result) is
      Request : Quality_Manager.Integrations.Processes.Request;
      Process : Quality_Manager.Integrations.Processes.Execution_Result;
      Path    : Hostkit.UString;
      Home    : Hostkit.UString;
   begin
      Output := Null_Unbounded_String;
      Request.Executable := To_Unbounded_String (Executable);
      Request.Arguments := Arguments;
      Request.Working_Directory := To_Unbounded_String (Directory);
      Request.Timeout_Seconds := 3_600;
      Request.Output_Limit := 4 * 1_024 * 1_024;
      if Hostkit.Process.Environment_Value ("PATH", Path) then
         Request.Environment.Append (To_Unbounded_String ("PATH=" & To_String (Path)));
      end if;
      if Hostkit.Process.Environment_Value ("HOME", Home) then
         Request.Environment.Append (To_Unbounded_String ("HOME=" & To_String (Home)));
      end if;
      Quality_Manager.Integrations.Processes.Execute (Request, Process);
      if not Process.Started then
         Result := Make_Result (Execution_Error, "release command did not start", "qm.release.process-start");
      elsif Process.Timed_Out then
         Result := Make_Result (Temporarily_Unavailable, "release command timed out", "qm.release.process-timeout");
      elsif Process.Output_Exceeded then
         Result := Make_Result (Execution_Error, "release command output limit exceeded", "qm.release.process-output");
      elsif Process.Exit_Status /= 0 then
         Result := Make_Result (Negative_Result, "release command failed", "qm.release.process-exit");
      else
         Output := To_Unbounded_String (Trim_Output (To_String (Process.Standard_Output)));
         Result := Make_Result (Success);
      end if;
   end Execute_Simple;

   function JSON_Natural (Document, Name : String) return Natural is
      Prefix : constant String := Character'Val (34) & Name & Character'Val (34) & ":";
      First  : Natural := Ada.Strings.Fixed.Index (Document, Prefix);
      Last   : Natural;
   begin
      if First = 0 then return 0; end if;
      First := First + Prefix'Length;
      Last := First;
      while Last <= Document'Last and then Document (Last) in '0' .. '9' loop
         Last := Last + 1;
      end loop;
      return Natural'Value (Document (First .. Last - 1));
   exception
      when Constraint_Error => return 0;
   end JSON_Natural;

   function JSON_String (Document, Name : String) return String is
      Quote  : constant Character := Character'Val (34);
      Prefix : constant String := Quote & Name & Quote & ":" & Quote;
      First  : Natural := Ada.Strings.Fixed.Index (Document, Prefix);
      Last   : Natural;
   begin
      if First = 0 then return ""; end if;
      First := First + Prefix'Length;
      Last := First;
      while Last <= Document'Last and then Document (Last) /= Quote loop
         Last := Last + 1;
      end loop;
      return (if Last > Document'Last then "" else Document (First .. Last - 1));
   end JSON_String;

   function Natural_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Natural) return Boolean is
      Node   : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
      Number : Long_Long_Integer;
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.Integer_Value
      then
         Value := 0;
         return False;
      end if;
      Number := Document.As_Integer (Node);
      if Number not in 0 .. Long_Long_Integer (Natural'Last) then
         Value := 0;
         return False;
      end if;
      Value := Natural (Number);
      return True;
   end Natural_Field;

   function String_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Unbounded_String) return Boolean is
      Node : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.String_Value
      then
         Value := Null_Unbounded_String;
         return False;
      end if;
      Value := To_Unbounded_String (Document.As_String (Node));
      return True;
   end String_Field;

   procedure Initialize
     (Item  : out Context;
      Store : Quality_Manager.Scheduler.Store_Access) is
   begin
      Item.Database := Store;
   end Initialize;

   procedure Load_Release
     (Item       : in out Context;
      Release_Id : String;
      Value      : out Quality_Manager.Storage.Schema.Release;
      Result     : out Operation_Result) is
      Entity : Quality_Manager.Storage.Stored_Entity;
      Payload : Unbounded_String;
      Project_Id, Generation : Natural;
   begin
      Value :=
        (Release_Id => Null_Unbounded_String,
         Project => (Null_Unbounded_String, 1, Null_Unbounded_String),
         Candidate_Commit => Null_Unbounded_String,
         Source_Digest => Null_Unbounded_String,
         Policy_Digest => Null_Unbounded_String,
         Toolchain => Null_Unbounded_String,
         Release_Config => Null_Unbounded_String,
         Generation => 1, Final_Assessment => 0, Coverage_Basis_Points => 0,
         State => Quality_Manager.Model.Discovered);
      if Item.Database = null then
         Result := Make_Result (Not_Ready, "release context is not initialized", "qm.release.context");
         return;
      end if;
      Quality_Manager.Storage.Read (Item.Database.all, "release:" & Release_Id, Entity, Result);
      if Result.Kind /= Success then return; end if;
      if Entity.Kind /= Quality_Manager.Storage.Release_Record then
         Result := Make_Result (Integrity_Error, "release record kind mismatch", "qm.release.record");
         return;
      end if;
      Payload := Entity.Payload;
      Project_Id := JSON_Natural (To_String (Payload), "quality_project_id");
      Generation := JSON_Natural (To_String (Payload), "generation");
      if Project_Id = 0 or else Generation = 0 then
         Result := Make_Result (Integrity_Error, "release identity is incomplete", "qm.release.identity");
         return;
      end if;
      begin
         Value.State := Quality_Manager.Model.Work_State'Value (To_String (Entity.State));
      exception
         when Constraint_Error =>
            Result := Make_Result (Incompatible_Contract, "unknown release state", "qm.release.state");
            return;
      end;
      Value.Release_Id := To_Unbounded_String (Release_Id);
      Value.Project :=
        (To_Unbounded_String (JSON_String (To_String (Payload), "quality_database_id")),
         Positive (Project_Id),
         To_Unbounded_String (JSON_String (To_String (Payload), "canonical_path")));
      Value.Candidate_Commit := To_Unbounded_String (JSON_String (To_String (Payload), "candidate_commit"));
      Value.Source_Digest := To_Unbounded_String (JSON_String (To_String (Payload), "source_digest"));
      Value.Policy_Digest := To_Unbounded_String (JSON_String (To_String (Payload), "policy_digest"));
      Value.Toolchain := To_Unbounded_String (JSON_String (To_String (Payload), "toolchain"));
      Value.Release_Config := To_Unbounded_String (JSON_String (To_String (Payload), "release_config"));
      Value.Generation := Generation;
      Value.Final_Assessment := JSON_Natural (To_String (Payload), "final_assessment");
      Value.Coverage_Basis_Points := JSON_Natural (To_String (Payload), "coverage_basis_points");
      Result := Make_Result (Success);
   end Load_Release;

   procedure Create
     (Item                  : in out Context;
      Project               : Quality_Manager.Identities.Project_Key;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Policy_Digest         : String;
      Toolchain_Fingerprint : String;
      Release_Config_Digest : String;
      Release_Id            : out Unbounded_String;
      Result                : out Operation_Result) is
   begin
      Release_Id := Null_Unbounded_String;
      if Item.Database = null then
         Result := Make_Result (Not_Ready, "release context is not initialized", "qm.release.context");
         return;
      elsif Candidate_Commit'Length = 0 or else Source_Fingerprint'Length = 0
        or else Policy_Digest'Length = 0 or else Toolchain_Fingerprint'Length = 0
        or else Release_Config_Digest'Length = 0
      then
         Result := Make_Result (Invalid_Request, "release candidate identity is incomplete", "qm.release.identity");
         return;
      end if;
      Release_Id := To_Unbounded_String
        (Quality_Manager.Identities.Canonical_Digest
           ([Quality_Manager.Identities.Text_Value (To_String (Project.Quality_Database_Id)),
             Quality_Manager.Identities.Number_Value
               (Interfaces.Unsigned_64 (Project.Quality_Project_Id)),
             Quality_Manager.Identities.Text_Value (To_String (Project.Canonical_Path)),
             Quality_Manager.Identities.Text_Value (Candidate_Commit),
             Quality_Manager.Identities.Text_Value (Source_Fingerprint),
             Quality_Manager.Identities.Text_Value (Policy_Digest),
             Quality_Manager.Identities.Text_Value (Toolchain_Fingerprint),
             Quality_Manager.Identities.Text_Value (Release_Config_Digest)]));
      declare
         Candidate : constant Quality_Manager.Storage.Schema.Release :=
           (Release_Id => Release_Id, Project => Project,
            Candidate_Commit => To_Unbounded_String (Candidate_Commit),
            Source_Digest => To_Unbounded_String (Source_Fingerprint),
            Policy_Digest => To_Unbounded_String (Policy_Digest),
            Toolchain => To_Unbounded_String (Toolchain_Fingerprint),
            Release_Config => To_Unbounded_String (Release_Config_Digest),
            Generation => 1, Final_Assessment => 0, Coverage_Basis_Points => 0,
            State => Quality_Manager.Model.Discovered);
      begin
         Quality_Manager.Storage.Records.Save (Item.Database.all, Candidate, Result);
      end;
   end Create;

   procedure New_Generation
     (Item                  : in out Context;
      Release_Id            : String;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Policy_Digest         : String;
      Toolchain_Fingerprint : String;
      Release_Config_Digest : String;
      Result                : out Operation_Result) is
      Candidate : Quality_Manager.Storage.Schema.Release;
   begin
      Load_Release (Item, Release_Id, Candidate, Result);
      if Result.Kind /= Success then return; end if;
      if Candidate_Commit'Length = 0 or else Source_Fingerprint'Length = 0
        or else Candidate_Commit = To_String (Candidate.Candidate_Commit)
        or else Source_Fingerprint = To_String (Candidate.Source_Digest)
      then
         Result := Make_Result
           (Invalid_Request, "new candidate generation requires a new exact source", "qm.release.generation");
         return;
      end if;
      Candidate.Generation := Candidate.Generation + 1;
      Candidate.Candidate_Commit := To_Unbounded_String (Candidate_Commit);
      Candidate.Source_Digest := To_Unbounded_String (Source_Fingerprint);
      Candidate.Policy_Digest := To_Unbounded_String (Policy_Digest);
      Candidate.Toolchain := To_Unbounded_String (Toolchain_Fingerprint);
      Candidate.Release_Config := To_Unbounded_String (Release_Config_Digest);
      Candidate.Final_Assessment := 0;
      Candidate.Coverage_Basis_Points := 0;
      Candidate.State := Quality_Manager.Model.Discovered;
      Quality_Manager.Storage.Records.Save (Item.Database.all, Candidate, Result);
   exception
      when Constraint_Error =>
         Result := Make_Result (Integrity_Error, "release generation exhausted", "qm.release.generation");
   end New_Generation;

   function Project_JSON (Project : Quality_Manager.Identities.Project_Key) return String is
     ("{""quality_database_id"":" & Q (To_String (Project.Quality_Database_Id))
      & ",""quality_project_id"":" & N (Project.Quality_Project_Id)
      & ",""canonical_path"":" & Q (To_String (Project.Canonical_Path)) & "}");

   procedure Run_Local_Checks
     (Item                  : in out Context;
      Operation             : Quality_Manager.Identities.Operation_Id;
      Project_Path          : String;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Release_Config_Digest : String;
      Coverage_Basis_Points : Natural;
      Proof_Applicable      : Boolean;
      Checks                : out Check_Results;
      Result                : out Operation_Result) is
   begin
      Run_Local_Checks_With_Tools
        (Item, Operation, Project_Path, Candidate_Commit, Source_Fingerprint,
         Release_Config_Digest, Coverage_Basis_Points, Proof_Applicable,
         "alr", "git", Checks, Result);
   end Run_Local_Checks;

   procedure Run_Local_Checks_With_Tools
     (Item                  : in out Context;
      Operation             : Quality_Manager.Identities.Operation_Id;
      Project_Path          : String;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Release_Config_Digest : String;
      Coverage_Basis_Points : Natural;
      Proof_Applicable      : Boolean;
      Alire_Executable      : String;
      Git_Executable        : String;
      Checks                : out Check_Results;
      Result                : out Operation_Result) is separate;

   procedure Evaluate
     (Item       : in out Context;
      Release_Id : String;
      Assessment : Quality_Manager.Verification.Assessment_Evidence;
      Checks     : Check_Results;
      References : Evidence_References;
      Decision   : out Qualification_Decision;
      Result     : out Operation_Result) is separate;

   procedure Qualify_With_Tools
     (Item             : in out Context;
      Quality          : Quality_Manager.Integrations.Quality.Adapter;
      Release_Id       : String;
      Alire_Executable : String;
      Git_Executable   : String;
      Decision         : out Qualification_Decision;
      Result           : out Operation_Result) is separate;

   procedure Qualify_With_Remediation
     (Item                : in out Context;
      Maintenance_Context : in out Quality_Manager.Maintenance.Context;
      Quality             : Quality_Manager.Integrations.Quality.Adapter;
      Release_Id          : String;
      Alire_Executable    : String;
      Git_Executable      : String;
      Maximum_Cycles      : Positive;
      Decision            : out Qualification_Decision;
      Result              : out Operation_Result) is separate;

   procedure Invalidate_If_Changed
     (Item                 : in out Context;
      Release_Id           : String;
      Current_Commit       : String;
      Current_Source       : String;
      Invalidated          : out Boolean;
      Result               : out Operation_Result) is
      Candidate : Quality_Manager.Storage.Schema.Release;
   begin
      Invalidated := False;
      Load_Release (Item, Release_Id, Candidate, Result);
      if Result.Kind /= Success then return; end if;
      if Current_Commit /= To_String (Candidate.Candidate_Commit)
        or else Current_Source /= To_String (Candidate.Source_Digest)
      then
         Candidate.State := Quality_Manager.Model.Superseded;
         Quality_Manager.Storage.Records.Save (Item.Database.all, Candidate, Result);
         Invalidated := Result.Kind = Success;
      end if;
   end Invalidate_If_Changed;

   procedure Write_File (Path, Text : String; Result : out Operation_Result) is
      package IO renames Ada.Streams.Stream_IO;
      File : IO.File_Type;
      Data : Ada.Streams.Stream_Element_Array (1 .. Text'Length);
   begin
      for Index in Text'Range loop
         Data (Ada.Streams.Stream_Element_Offset (Index - Text'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Text (Index)));
      end loop;
      IO.Create (File, IO.Out_File, Path);
      IO.Write (File, Data);
      IO.Close (File);
      Result := Make_Result (Success);
   exception
      when others =>  --  AQ: audited exception boundary
         if IO.Is_Open (File) then IO.Close (File); end if;
         Result := Make_Result (Execution_Error, "cannot write release evidence", "qm.release.export");
   end Write_File;

   procedure Export_Evidence
     (Item        : in out Context;
      Release_Id  : String;
      Output_Path : String;
      Result      : out Operation_Result) is separate;

   procedure Create (Project_Selector : String; Profile : String) is
   begin
      Create_Configured
        (Project_Selector, Profile, "config/quality-manager.toml", False);
   end Create;

   procedure Create_Configured
     (Project_Selector : String;
      Profile          : String;
      Config_Path      : String;
      Config_Required  : Boolean) is separate;

   procedure Qualify (Release_Id : String) is
   begin
      Qualify_Configured
        (Release_Id, "config/quality-manager.toml", False);
   end Qualify;

   procedure Qualify_Configured
     (Release_Id      : String;
      Config_Path     : String;
      Config_Required : Boolean) is separate;

   procedure Export_Evidence (Release_Id : String; Output_Path : String) is
   begin
      Export_Evidence_Configured
        (Release_Id, Output_Path, "config/quality-manager.toml", False);
   end Export_Evidence;

   procedure Export_Evidence_Configured
     (Release_Id      : String;
      Output_Path     : String;
      Config_Path     : String;
      Config_Required : Boolean) is separate;
end Quality_Manager.Releases;
