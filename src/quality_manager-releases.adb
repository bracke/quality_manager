with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Hostkit;
with Hostkit.Process;
with Jsonlib.Serializers;
with Quality_Manager.Config;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Model;
with Quality_Manager.Journal;
with Quality_Manager.Storage;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Schema;

package body Quality_Manager.Releases is
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
      Result                : out Operation_Result) is
      Key : constant String :=
        "release-checks:"
        & Ada.Strings.Fixed.Trim
            (Quality_Manager.Identities.Operation_Id'Image (Operation), Ada.Strings.Both);
      Stored : Quality_Manager.Storage.Stored_Entity;
      Journal : Quality_Manager.Storage.Stored_Entity;
      Args : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Output, Commit : Unbounded_String;
      Command_Result : Operation_Result;
      Infrastructure_Failure : Boolean := False;

      procedure Decode_Stored is
         Payload : constant String := To_String (Stored.Payload);
      begin
         Checks :=
           (Candidate_Commit => To_Unbounded_String (JSON_String (Payload, "candidate_commit")),
            Source_Fingerprint => To_Unbounded_String (JSON_String (Payload, "source_fingerprint")),
            Release_Config_Digest => To_Unbounded_String
              (JSON_String (Payload, "release_config_digest")),
            Clean_Build => JSON_Boolean (Payload, "clean_build"),
            Reproducible_Build => JSON_Boolean (Payload, "reproducible_build"),
            AUnit_Passed => JSON_Boolean (Payload, "aunit_passed"),
            Proof_Applicable => JSON_Boolean (Payload, "proof_applicable"),
            GNATprove_Passed => JSON_Boolean (Payload, "gnatprove_passed"),
            Coverage_Basis_Points => JSON_Natural (Payload, "coverage_basis_points"),
            Release_Checks_Passed => JSON_Boolean (Payload, "release_checks_passed"));
      end Decode_Stored;

      procedure Run_Alire (Arguments : Quality_Manager.Integrations.Processes.String_Vectors.Vector) is
      begin
         Execute_Simple (Alire_Executable, Arguments, Project_Path, Output, Command_Result);
         if Command_Result.Kind not in Success | Negative_Result then
            Infrastructure_Failure := True;
         end if;
      end Run_Alire;

      procedure Finish_Journal is
         State : Quality_Manager.Journal.Journal_State;
      begin
         Quality_Manager.Storage.Read
           (Item.Database.all,
            "journal:" & Ada.Strings.Fixed.Trim
              (Quality_Manager.Identities.Operation_Id'Image (Operation), Ada.Strings.Both),
            Journal, Result);
         if Result.Kind /= Success then return; end if;
         State := Quality_Manager.Journal.Journal_State'Value (To_String (Journal.State));
         if State = Quality_Manager.Journal.Invoking then
            Quality_Manager.Storage.Advance_Operation
              (Item.Database.all, Operation, State, Quality_Manager.Journal.Reconciling,
               Key, "release checks observed", Result);
            State := Quality_Manager.Journal.Reconciling;
         end if;
         if Result.Kind = Success and then State = Quality_Manager.Journal.Reconciling then
            Quality_Manager.Storage.Advance_Operation
              (Item.Database.all, Operation, State, Quality_Manager.Journal.Committed,
               Key, "release checks committed", Result);
         end if;
      exception
         when Constraint_Error =>
            Result := Make_Result (Incompatible_Contract, "invalid release-check journal", "qm.release.journal");
      end Finish_Journal;
   begin
      Checks := (others => <>);
      if Item.Database = null then
         Result := Make_Result (Not_Ready, "release context is not initialized", "qm.release.context");
         return;
      elsif Operation = 0 then
         Result := Make_Result
           (Invalid_Request, "release-check operation identity is required", "qm.release.operation");
         return;
      end if;
      Quality_Manager.Storage.Read (Item.Database.all, Key, Stored, Result);
      if Result.Kind = Success then
         Decode_Stored;
         Finish_Journal;
         if Result.Kind = Success and then not Checks.Release_Checks_Passed then
            Result := Make_Result
              (Negative_Result, Check_Failure_Message (Checks, Candidate_Commit), "qm.release.checks");
         end if;
         return;
      elsif Result.Kind /= Not_Found then
         return;
      end if;
      Quality_Manager.Storage.Prepare_Operation
        (Item.Database.all, Operation, "release-checks",
         "project=" & Project_Path & ASCII.LF & "candidate=" & Candidate_Commit
         & ASCII.LF & "config=" & Release_Config_Digest,
         Key, Result);
      if Result.Kind /= Success then return; end if;
      Quality_Manager.Storage.Read
        (Item.Database.all,
         "journal:" & Ada.Strings.Fixed.Trim
           (Quality_Manager.Identities.Operation_Id'Image (Operation), Ada.Strings.Both),
         Journal, Result);
      if Result.Kind /= Success then return; end if;
      declare
         State : constant Quality_Manager.Journal.Journal_State :=
           Quality_Manager.Journal.Journal_State'Value (To_String (Journal.State));
      begin
         if State = Quality_Manager.Journal.Prepared then
            Quality_Manager.Storage.Advance_Operation
              (Item.Database.all, Operation, State, Quality_Manager.Journal.Invoking,
               Key, "starting idempotent local release checks", Result);
         elsif State not in Quality_Manager.Journal.Invoking then
            Result := Make_Result (Not_Ready, "release-check journal cannot be invoked", "qm.release.journal-state");
         end if;
      exception
         when Constraint_Error =>
            Result := Make_Result (Incompatible_Contract, "invalid release-check journal", "qm.release.journal");
      end;
      if Result.Kind /= Success then return; end if;

      Args.Append (To_Unbounded_String ("rev-parse"));
      Args.Append (To_Unbounded_String ("HEAD"));
      Execute_Simple (Git_Executable, Args, Project_Path, Commit, Command_Result);
      if Command_Result.Kind not in Success | Negative_Result then Infrastructure_Failure := True; end if;
      Checks.Candidate_Commit := Commit;
      Checks.Source_Fingerprint := To_Unbounded_String (Source_Fingerprint);
      Checks.Release_Config_Digest := To_Unbounded_String (Release_Config_Digest);
      Checks.Coverage_Basis_Points := Coverage_Basis_Points;
      Checks.Proof_Applicable := Proof_Applicable;

      Args.Clear;
      Args.Append (To_Unbounded_String ("build"));
      Args.Append (To_Unbounded_String ("--validation"));
      Args.Append (To_Unbounded_String ("--"));
      Args.Append (To_Unbounded_String ("-f"));
      Run_Alire (Args);
      Checks.Clean_Build := Command_Result.Kind = Success;
      Run_Alire (Args);
      Checks.Reproducible_Build := Checks.Clean_Build and then Command_Result.Kind = Success;

      Args.Clear;
      Args.Append (To_Unbounded_String ("test"));
      Run_Alire (Args);
      Checks.AUnit_Passed := Command_Result.Kind = Success;
      if Proof_Applicable then
         Args.Clear;
         Args.Append (To_Unbounded_String ("exec"));
         Args.Append (To_Unbounded_String ("--"));
         Args.Append (To_Unbounded_String ("gnatprove"));
         Run_Alire (Args);
         Checks.GNATprove_Passed := Command_Result.Kind = Success;
      else
         Checks.GNATprove_Passed := True;
      end if;
      Checks.Release_Checks_Passed :=
        Commit = To_Unbounded_String (Candidate_Commit)
        and then Checks.Clean_Build and then Checks.Reproducible_Build
        and then Checks.AUnit_Passed and then Checks.GNATprove_Passed
        and then not Infrastructure_Failure;
      Stored :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
         Entity_Key => To_Unbounded_String (Key), State => To_Unbounded_String ("OBSERVED"),
         Payload => To_Unbounded_String
           ("{""candidate_commit"":" & Q (To_String (Checks.Candidate_Commit))
            & ",""source_fingerprint"":" & Q (Source_Fingerprint)
            & ",""release_config_digest"":" & Q (Release_Config_Digest)
            & ",""clean_build"":" & B (Checks.Clean_Build)
            & ",""reproducible_build"":" & B (Checks.Reproducible_Build)
            & ",""aunit_passed"":" & B (Checks.AUnit_Passed)
            & ",""proof_applicable"":" & B (Checks.Proof_Applicable)
            & ",""gnatprove_passed"":" & B (Checks.GNATprove_Passed)
            & ",""coverage_basis_points"":" & N (Checks.Coverage_Basis_Points)
            & ",""release_checks_passed"":" & B (Checks.Release_Checks_Passed) & "}"),
         Terminal => True, Generation => 1);
      Quality_Manager.Storage.Put (Item.Database.all, Stored, Result);
      if Result.Kind /= Success then return; end if;
      Finish_Journal;
      if Result.Kind = Success and then Infrastructure_Failure then
         Result := Make_Result (Execution_Error, "release-check execution failed", "qm.release.check-execution");
      elsif Result.Kind = Success and then not Checks.Release_Checks_Passed then
         Result := Make_Result
           (Negative_Result, Check_Failure_Message (Checks, Candidate_Commit), "qm.release.checks");
      end if;
   end Run_Local_Checks_With_Tools;

   procedure Evaluate
     (Item       : in out Context;
      Release_Id : String;
      Assessment : Quality_Manager.Verification.Assessment_Evidence;
      Checks     : Check_Results;
      References : Evidence_References;
      Decision   : out Qualification_Decision;
      Result     : out Operation_Result) is
      Candidate : Quality_Manager.Storage.Schema.Release;
      Gate      : Boolean;
      Bundle    : Unbounded_String;
      Digest    : Unbounded_String;
   begin
      Decision := (others => <>);
      Load_Release (Item, Release_Id, Candidate, Result);
      if Result.Kind /= Success then return; end if;
      Gate :=
        Assessment.Completed and then Assessment.Complete
        and then Assessment.Indicator_Count = 33 and then Assessment.Violations = 0
        and then Assessment.Assessment_Id > 0
        and then Assessment.Project_Id = Candidate.Project.Quality_Project_Id
        and then To_String (Assessment.Project_Path) = To_String (Candidate.Project.Canonical_Path)
        and then To_String (Assessment.Source_Fingerprint) = To_String (Candidate.Source_Digest)
        and then To_String (Assessment.Policy_Fingerprint) = To_String (Candidate.Policy_Digest)
        and then To_String (Assessment.Toolchain_Fingerprint) = To_String (Candidate.Toolchain)
        and then To_String (Checks.Candidate_Commit) = To_String (Candidate.Candidate_Commit)
        and then To_String (Checks.Source_Fingerprint) = To_String (Candidate.Source_Digest)
        and then To_String (Checks.Release_Config_Digest) = To_String (Candidate.Release_Config)
        and then Checks.Clean_Build and then Checks.Reproducible_Build and then Checks.AUnit_Passed
        and then (not Checks.Proof_Applicable or else Checks.GNATprove_Passed)
        and then Checks.Coverage_Basis_Points in 9_000 .. 10_000
        and then Checks.Release_Checks_Passed;
      if not Gate then
         Candidate.State := Quality_Manager.Model.Blocked;
         Quality_Manager.Storage.Records.Save (Item.Database.all, Candidate, Result);
         if Result.Kind = Success then
            Decision.Diagnostic := To_Unbounded_String ("one or more release gates did not pass with current evidence");
            Result := Make_Result (Negative_Result, To_String (Decision.Diagnostic), "qm.release.gate");
         end if;
         return;
      end if;
      Bundle := To_Unbounded_String
        ("{""schema_version"":1,""kind"":""release-evidence"",""release_id"":" & Q (Release_Id)
         & ",""generation"":" & N (Candidate.Generation)
         & ",""project"":" & Project_JSON (Candidate.Project)
         & ",""candidate_commit"":" & Q (To_String (Candidate.Candidate_Commit))
         & ",""source_fingerprint"":" & Q (To_String (Candidate.Source_Digest))
         & ",""policy_digest"":" & Q (To_String (Candidate.Policy_Digest))
         & ",""toolchain_fingerprint"":" & Q (To_String (Candidate.Toolchain))
         & ",""release_config_digest"":" & Q (To_String (Candidate.Release_Config))
         & ",""assessment_id"":" & N (Assessment.Assessment_Id)
         & ",""indicator_count"":" & N (Assessment.Indicator_Count)
         & ",""coverage_basis_points"":" & N (Checks.Coverage_Basis_Points)
         & ",""clean_build"":" & B (Checks.Clean_Build)
         & ",""reproducible_build"":" & B (Checks.Reproducible_Build)
         & ",""aunit_passed"":" & B (Checks.AUnit_Passed)
         & ",""gnatprove_passed"":" & B (not Checks.Proof_Applicable or else Checks.GNATprove_Passed)
         & ",""release_checks_passed"":" & B (Checks.Release_Checks_Passed)
         & ",""improve_audit"":" & Q (To_String (References.Improve_Audit))
         & ",""native_audit"":" & Q (To_String (References.Native_Audit))
         & ",""regression_evidence"":" & Q (To_String (References.Regression_Evidence))
         & ",""authorization_audit"":" & Q (To_String (References.Authorization_Audit))
         & ",""qualification"":""qualified""}");
      Digest := To_Unbounded_String
        (Quality_Manager.Identities.Canonical_Digest
           ([Quality_Manager.Identities.Text_Value (To_String (Bundle))]));
      declare
         Text        : constant String := To_String (Bundle);
         Chunk_Count : constant Positive :=
           Positive ((Text'Length + Evidence_Chunk_Size - 1) / Evidence_Chunk_Size);
         Evidence : constant Quality_Manager.Storage.Stored_Entity :=
           (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
            Entity_Key => To_Unbounded_String (Evidence_Key (Release_Id, Candidate.Generation)),
            State => To_Unbounded_String ("QUALIFIED"),
            Payload => To_Unbounded_String
              ("digest=" & To_String (Digest) & ASCII.LF & "chunks=" & N (Chunk_Count)),
            Terminal => True, Generation => 1);
      begin
         for Chunk in 1 .. Chunk_Count loop
            declare
               First : constant Positive := Text'First + (Chunk - 1) * Evidence_Chunk_Size;
               Last  : constant Positive := Positive'Min (Text'Last, First + Evidence_Chunk_Size - 1);
               Part  : constant Quality_Manager.Storage.Stored_Entity :=
                 (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
                  Entity_Key => To_Unbounded_String
                    (Evidence_Chunk_Key (Release_Id, Candidate.Generation, Chunk)),
                  State => To_Unbounded_String ("CHUNK"),
                  Payload => To_Unbounded_String (Text (First .. Last)),
                  Terminal => True, Generation => 1);
            begin
               Quality_Manager.Storage.Put (Item.Database.all, Part, Result);
               exit when Result.Kind /= Success;
            end;
         end loop;
         if Result.Kind = Success then
            Quality_Manager.Storage.Put (Item.Database.all, Evidence, Result);
         end if;
      end;
      if Result.Kind /= Success then return; end if;
      Candidate.Final_Assessment := Assessment.Assessment_Id;
      Candidate.Coverage_Basis_Points := Checks.Coverage_Basis_Points;
      Candidate.State := Quality_Manager.Model.Verified;
      Quality_Manager.Storage.Records.Save (Item.Database.all, Candidate, Result);
      if Result.Kind = Success then
         Decision.Qualified := True;
         Decision.Diagnostic := To_Unbounded_String ("all release gates passed");
         Decision.Bundle_Digest := Digest;
      end if;
   end Evaluate;

   procedure Qualify_With_Tools
     (Item             : in out Context;
      Quality          : Quality_Manager.Integrations.Quality.Adapter;
      Release_Id       : String;
      Alire_Executable : String;
      Git_Executable   : String;
      Decision         : out Qualification_Decision;
      Result           : out Operation_Result) is
      Candidate  : Quality_Manager.Storage.Schema.Release;
      Assessment : Quality_Manager.Verification.Assessment_Evidence;
      Checks     : Check_Results;
      References : constant Evidence_References :=
        (Improve_Audit => To_Unbounded_String ("not-required:no-remediation"),
         Native_Audit => To_Unbounded_String ("not-required:no-agent-execution"),
         Regression_Evidence => To_Unbounded_String ("full-release-assessment"),
         Authorization_Audit => To_Unbounded_String ("not-required:measurement-only"));
   begin
      Decision := (others => <>);
      Load_Release (Item, Release_Id, Candidate, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Quality_Manager.Verification.Establish_Assessment
        (Item.Database.all, Quality,
         (Operation => Qualification_Operation
            (Release_Id, Candidate.Generation, "assessment"),
          Work_Id => To_Unbounded_String ("release:" & Release_Id),
          Project => Candidate.Project,
          Project_Selector => To_Unbounded_String
            (Ada.Strings.Fixed.Trim
               (Positive'Image (Candidate.Project.Quality_Project_Id), Ada.Strings.Both)),
          Profile => To_Unbounded_String ("release"),
          Candidate_Source => Candidate.Source_Digest,
          Policy_Fingerprint => Candidate.Policy_Digest,
          Toolchain_Fingerprint => Candidate.Toolchain),
         Assessment, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Run_Local_Checks_With_Tools
        (Item, Qualification_Operation (Release_Id, Candidate.Generation, "local-checks"),
         To_String (Candidate.Project.Canonical_Path),
         To_String (Candidate.Candidate_Commit), To_String (Candidate.Source_Digest),
         To_String (Candidate.Release_Config), Assessment.Coverage_Basis_Points,
         Assessment.Proof_Applicable, Alire_Executable, Git_Executable, Checks, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Evaluate (Item, Release_Id, Assessment, Checks, References, Decision, Result);
   end Qualify_With_Tools;

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
      when others =>
         if IO.Is_Open (File) then IO.Close (File); end if;
         Result := Make_Result (Execution_Error, "cannot write release evidence", "qm.release.export");
   end Write_File;

   procedure Export_Evidence
     (Item        : in out Context;
      Release_Id  : String;
      Output_Path : String;
      Result      : out Operation_Result) is
      Candidate : Quality_Manager.Storage.Schema.Release;
      Evidence  : Quality_Manager.Storage.Stored_Entity;
   begin
      Load_Release (Item, Release_Id, Candidate, Result);
      if Result.Kind /= Success then return; end if;
      if Candidate.State /= Quality_Manager.Model.Verified then
         Result := Make_Result (Not_Ready, "release candidate is not qualified", "qm.release.not-qualified");
         return;
      end if;
      Quality_Manager.Storage.Read
        (Item.Database.all, Evidence_Key (Release_Id, Candidate.Generation), Evidence, Result);
      if Result.Kind /= Success then return; end if;
      declare
         Payload : constant String := To_String (Evidence.Payload);
         Break   : constant Natural := Ada.Strings.Fixed.Index (Payload, ASCII.LF & "");
         Prefix  : constant String := "digest=";
         Chunks_Prefix : constant String := "chunks=";
      begin
         if Break = 0 or else Payload'Length <= Prefix'Length
           or else Payload (Payload'First .. Payload'First + Prefix'Length - 1) /= Prefix
         then
            Result := Make_Result (Integrity_Error, "release evidence envelope is corrupt", "qm.release.evidence");
            return;
         end if;
         declare
            Digest : constant String := Payload (Payload'First + Prefix'Length .. Break - 1);
            Chunk_Declaration : constant String := Payload (Break + 1 .. Payload'Last);
            Chunk_Count : Natural := 0;
            Bundle : Unbounded_String;
         begin
            if Chunk_Declaration'Length <= Chunks_Prefix'Length
              or else Chunk_Declaration
                (Chunk_Declaration'First .. Chunk_Declaration'First + Chunks_Prefix'Length - 1)
                  /= Chunks_Prefix
            then
               Result := Make_Result
                 (Integrity_Error, "release evidence chunk declaration is corrupt", "qm.release.evidence");
               return;
            end if;
            begin
               Chunk_Count := Natural'Value
                 (Chunk_Declaration
                    (Chunk_Declaration'First + Chunks_Prefix'Length .. Chunk_Declaration'Last));
            exception
               when Constraint_Error =>
                  Result := Make_Result
                    (Integrity_Error, "release evidence chunk count is invalid", "qm.release.evidence");
                  return;
            end;
            if Chunk_Count = 0 then
               Result := Make_Result
                 (Integrity_Error, "release evidence has no chunks", "qm.release.evidence");
               return;
            end if;
            for Chunk in 1 .. Chunk_Count loop
               declare
                  Part : Quality_Manager.Storage.Stored_Entity;
               begin
                  Quality_Manager.Storage.Read
                    (Item.Database.all, Evidence_Chunk_Key (Release_Id, Candidate.Generation, Chunk),
                     Part, Result);
                  if Result.Kind /= Success then
                     Result := Make_Result
                       (Integrity_Error, "release evidence chunk is missing", "qm.release.evidence-chunk");
                     return;
                  elsif Part.Kind /= Quality_Manager.Storage.Release_Record
                    or else To_String (Part.State) /= "CHUNK" or else not Part.Terminal
                  then
                     Result := Make_Result
                       (Integrity_Error, "release evidence chunk is invalid", "qm.release.evidence-chunk");
                     return;
                  end if;
                  Append (Bundle, Part.Payload);
               end;
            end loop;
            declare
               Text   : constant String := To_String (Bundle);
               Actual : constant String := Quality_Manager.Identities.Canonical_Digest
                 ([Quality_Manager.Identities.Text_Value (Text)]);
            begin
               if Digest /= Actual then
                  Result := Make_Result
                    (Integrity_Error, "release evidence digest mismatch", "qm.release.digest");
                  return;
               end if;
               Write_File (Output_Path, Text, Result);
            end;
         end;
      end;
   end Export_Evidence;

   procedure Create (Project_Selector : String; Profile : String) is
   begin
      Create_Configured
        (Project_Selector, Profile, "config/quality-manager.toml", False);
   end Create;

   procedure Create_Configured
     (Project_Selector : String;
      Profile          : String;
      Config_Path      : String;
      Config_Required  : Boolean) is
      Settings : Quality_Manager.Config.Settings;
      Store : aliased Quality_Manager.Storage.Store;
      Item : Context;
      Result, Close_Result : Operation_Result;
      Projects : Quality_Manager.Storage.Entity_Vectors.Vector;
      Project : Quality_Manager.Identities.Project_Key;
      Source, Policy, Toolchain : Unbounded_String;
      Found   : Boolean := False;
      Commit : Unbounded_String;
      Args : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Release_Id : Unbounded_String;
      Quality : Quality_Manager.Integrations.Quality.Adapter;
      Plan    : Quality_Manager.Integrations.JSON_CLI.Response;
   begin
      if Profile /= "release" then
         Result := Make_Result
           (Invalid_Request, "the initial release qualifier requires the release profile",
            "qm.release.profile");
      else
         Quality_Manager.Config.Load (Config_Path, Config_Required, Settings, Result);
      end if;
      if Result.Kind = Success and then Length (Settings.Quality_Database) = 0 then
         Result := Make_Result
           (Invalid_Request, "release creation requires an Ada Quality database",
            "qm.release.quality-database");
      end if;
      if Result.Kind = Success then
         Quality_Manager.Storage.Open (Store, To_String (Settings.Coordinator_Database), True, Result);
      end if;
      if Result.Kind = Success then
         Quality_Manager.Storage.List
           (Store, Quality_Manager.Storage.Project_Record, Projects, 100_000, Result);
      end if;
      if Result.Kind = Success then
         for Entity of Projects loop
            declare
               Payload : constant String := To_String (Entity.Payload);
               Id      : constant Natural := JSON_Natural (Payload, "quality_project_id");
               Path    : constant String := JSON_String (Payload, "canonical_path");
            begin
               if To_String (Entity.State) = "ENABLED" and then Id > 0
                 and then
                   (Project_Selector = Path
                    or else Project_Selector = Ada.Strings.Fixed.Trim (Natural'Image (Id), Ada.Strings.Both))
               then
                  if Found then
                     Result := Make_Result
                       (Invalid_Request, "release selector matches multiple projects", "qm.release.selector");
                     exit;
                  end if;
                  Found := True;
                  Project :=
                    (To_Unbounded_String (JSON_String (Payload, "quality_database_id")),
                     Positive (Id), To_Unbounded_String (Path));
               end if;
            end;
         end loop;
         if Result.Kind = Success and then not Found then
            Result := Make_Result (Not_Found, "release project not found", "qm.release.selector");
         end if;
      end if;
      if Result.Kind = Success then
         Quality_Manager.Integrations.Quality.Initialize
           (Quality, To_String (Settings.Ada_Quality_Executable),
            To_String (Settings.Quality_Database));
         Quality_Manager.Integrations.Quality.Plan_Check
           (Quality,
            Ada.Strings.Fixed.Trim
              (Positive'Image (Project.Quality_Project_Id), Ada.Strings.Both),
            Profile, False, Plan);
         Result := Plan.Status;
      end if;
      if Result.Kind = Success then
         declare
            Document : constant String := To_String (Plan.Document);
         begin
            Source := To_Unbounded_String (JSON_String (Document, "source_fingerprint"));
            Policy := To_Unbounded_String (JSON_String (Document, "policy_fingerprint"));
            Toolchain := To_Unbounded_String (JSON_String (Document, "toolchain_fingerprint"));
            if JSON_Natural (Document, "project_id") /= Project.Quality_Project_Id
              or else JSON_String (Document, "path") /= To_String (Project.Canonical_Path)
              or else Length (Source) = 0
              or else Length (Policy) = 0
              or else Length (Toolchain) = 0
            then
               Result := Make_Result
                 (Incompatible_Contract, "release assessment plan identity is incomplete or mismatched",
                  "qm.release.plan");
            end if;
         end;
      end if;
      if Result.Kind = Success then
         Args.Append (To_Unbounded_String ("rev-parse"));
         Args.Append (To_Unbounded_String ("HEAD"));
         Execute_Simple ("git", Args, To_String (Project.Canonical_Path), Commit, Result);
      end if;
      if Result.Kind = Success then
         Initialize (Item, Store'Unchecked_Access);
         Create
           (Item, Project, To_String (Commit), To_String (Source),
            To_String (Policy), To_String (Toolchain),
            Quality_Manager.Identities.Canonical_Digest
              ([Quality_Manager.Identities.Text_Value ("release-config"),
                Quality_Manager.Identities.Text_Value (Profile)]),
            Release_Id, Result);
      end if;
      Quality_Manager.Storage.Close (Store, Close_Result);
      if Result.Kind = Success and then Close_Result.Kind /= Success then
         Result := Close_Result;
      end if;
      if Result.Kind /= Success then
         raise Release_Error with Message (Result);
      end if;
   end Create_Configured;

   procedure Qualify (Release_Id : String) is
   begin
      Qualify_Configured
        (Release_Id, "config/quality-manager.toml", False);
   end Qualify;

   procedure Qualify_Configured
     (Release_Id      : String;
      Config_Path     : String;
      Config_Required : Boolean) is
      Settings : Quality_Manager.Config.Settings;
      Store    : aliased Quality_Manager.Storage.Store;
      Item     : Context;
      Quality  : Quality_Manager.Integrations.Quality.Adapter;
      Decision   : Qualification_Decision;
      Result, Close_Result : Operation_Result;
   begin
      if Release_Id = "" then
         Result := Make_Result (Invalid_Request, "release identity is required", "qm.release.identity");
      else
         Quality_Manager.Config.Load (Config_Path, Config_Required, Settings, Result);
      end if;
      if Result.Kind = Success and then Length (Settings.Quality_Database) = 0 then
         Result := Make_Result
           (Invalid_Request, "release qualification requires an Ada Quality database",
            "qm.release.quality-database");
      end if;
      if Result.Kind = Success then
         Quality_Manager.Storage.Open
           (Store, To_String (Settings.Coordinator_Database), True, Result);
      end if;
      if Result.Kind = Success then
         Initialize (Item, Store'Unchecked_Access);
         Quality_Manager.Integrations.Quality.Initialize
           (Quality, To_String (Settings.Ada_Quality_Executable),
            To_String (Settings.Quality_Database));
         Qualify_With_Tools (Item, Quality, Release_Id, "alr", "git", Decision, Result);
      end if;
      if Quality_Manager.Storage.Is_Open (Store) then
         Quality_Manager.Storage.Close (Store, Close_Result);
         if Result.Kind = Success and then Close_Result.Kind /= Success then
            Result := Close_Result;
         end if;
      end if;
      if Result.Kind /= Success then
         raise Release_Error with Message (Result);
      end if;
   end Qualify_Configured;

   procedure Export_Evidence (Release_Id : String; Output_Path : String) is
   begin
      Export_Evidence_Configured
        (Release_Id, Output_Path, "config/quality-manager.toml", False);
   end Export_Evidence;

   procedure Export_Evidence_Configured
     (Release_Id      : String;
      Output_Path     : String;
      Config_Path     : String;
      Config_Required : Boolean) is
      Settings : Quality_Manager.Config.Settings;
      Store : aliased Quality_Manager.Storage.Store;
      Item : Context;
      Result, Close_Result : Operation_Result;
   begin
      Quality_Manager.Config.Load (Config_Path, Config_Required, Settings, Result);
      if Result.Kind = Success then
         Quality_Manager.Storage.Open (Store, To_String (Settings.Coordinator_Database), True, Result);
      end if;
      if Result.Kind = Success then
         Initialize (Item, Store'Unchecked_Access);
         Export_Evidence (Item, Release_Id, Output_Path, Result);
      end if;
      Quality_Manager.Storage.Close (Store, Close_Result);
      if Result.Kind = Success and then Close_Result.Kind /= Success then Result := Close_Result; end if;
      if Result.Kind /= Success then raise Release_Error with Message (Result); end if;
   end Export_Evidence_Configured;
end Quality_Manager.Releases;
