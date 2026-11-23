separate (Quality_Manager.Releases)
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
   Source_Before, Source_After : Unbounded_String;
   First_Build, Second_Build : Unbounded_String;
   Workspace_Base : constant String :=
     "/tmp/quality-manager-release-"
     & Ada.Strings.Fixed.Trim
         (Quality_Manager.Identities.Operation_Id'Image (Operation), Ada.Strings.Both);
   First_Workspace : constant String := Workspace_Base & "-a";
   Second_Workspace : constant String := Workspace_Base & "-b";
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
         Source_Unchanged => JSON_Boolean (Payload, "source_unchanged"),
         Git_Clean => JSON_Boolean (Payload, "git_clean"),
         AUnit_Passed => JSON_Boolean (Payload, "aunit_passed"),
         Proof_Applicable => JSON_Boolean (Payload, "proof_applicable"),
         GNATprove_Passed => JSON_Boolean (Payload, "gnatprove_passed"),
         Coverage_Basis_Points => JSON_Natural (Payload, "coverage_basis_points"),
         Release_Checks_Passed => JSON_Boolean (Payload, "release_checks_passed"));
   end Decode_Stored;

   procedure Run_Alire
     (Arguments : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Directory : String := Project_Path) is
   begin
      Execute_Simple (Alire_Executable, Arguments, Directory, Output, Command_Result);
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

   procedure Validate_Context is
   begin
      if Item.Database = null then
         Result := Make_Result (Not_Ready, "release context is not initialized", "qm.release.context");
      elsif Operation = 0 then
         Result := Make_Result
           (Invalid_Request, "release-check operation identity is required", "qm.release.operation");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Context;

   procedure Prepare_Journal is
   begin
      Quality_Manager.Storage.Prepare_Operation
        (Item.Database.all, Operation, "release-checks",
         "project=" & Project_Path & ASCII.LF & "candidate=" & Candidate_Commit
         & ASCII.LF & "config=" & Release_Config_Digest,
         Key, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Quality_Manager.Storage.Read
        (Item.Database.all,
         "journal:" & Ada.Strings.Fixed.Trim
           (Quality_Manager.Identities.Operation_Id'Image (Operation), Ada.Strings.Both),
         Journal, Result);
      if Result.Kind /= Success then
         return;
      end if;
      begin
         declare
            State : constant Quality_Manager.Journal.Journal_State :=
              Quality_Manager.Journal.Journal_State'Value (To_String (Journal.State));
         begin
            if State = Quality_Manager.Journal.Prepared then
               Quality_Manager.Storage.Advance_Operation
                 (Item.Database.all, Operation, State, Quality_Manager.Journal.Invoking,
                  Key, "starting idempotent local release checks", Result);
            elsif State not in Quality_Manager.Journal.Invoking then
               Result := Make_Result
                 (Not_Ready, "release-check journal cannot be invoked", "qm.release.journal-state");
            end if;
         end;
      exception
         when Constraint_Error =>
            Result := Make_Result
              (Incompatible_Contract, "invalid release-check journal", "qm.release.journal");
      end;
   end Prepare_Journal;

   procedure Capture_Identity is
      Ignored : Natural;
   begin
      Quality_Manager.Reproducibility.Manifest
        (Project_Path, False, Source_Before, Ignored, Command_Result);
      if Command_Result.Kind /= Success then
         Infrastructure_Failure := True;
      end if;
      Args.Append (To_Unbounded_String ("rev-parse"));
      Args.Append (To_Unbounded_String ("HEAD"));
      Execute_Simple (Git_Executable, Args, Project_Path, Commit, Command_Result);
      if Command_Result.Kind not in Success | Negative_Result then
         Infrastructure_Failure := True;
      end if;
      Checks.Candidate_Commit := Commit;
      Checks.Source_Fingerprint := To_Unbounded_String (Source_Fingerprint);
      Checks.Release_Config_Digest := To_Unbounded_String (Release_Config_Digest);
      Checks.Coverage_Basis_Points := Coverage_Basis_Points;
      Checks.Proof_Applicable := Proof_Applicable;
   end Capture_Identity;

   procedure Run_Builds is
      First_Result, Second_Result, Cleanup_Result : Operation_Result;
      First_Count, Second_Count : Natural := 0;
   begin
      Quality_Manager.Reproducibility.Remove_Workspace (First_Workspace, Cleanup_Result);
      if Cleanup_Result.Kind /= Success then
         Infrastructure_Failure := True;
         return;
      end if;
      Quality_Manager.Reproducibility.Remove_Workspace (Second_Workspace, Cleanup_Result);
      if Cleanup_Result.Kind /= Success then
         Infrastructure_Failure := True;
         return;
      end if;
      Quality_Manager.Reproducibility.Prepare_Clean_Workspace
        (Project_Path, First_Workspace, First_Result);
      if First_Result.Kind = Success then
         Quality_Manager.Reproducibility.Prepare_Clean_Workspace
           (Project_Path, Second_Workspace, Second_Result);
      else
         Second_Result := First_Result;
      end if;
      Args.Clear;
      Args.Append (To_Unbounded_String ("build"));
      Args.Append (To_Unbounded_String ("--validation"));
      Args.Append (To_Unbounded_String ("--"));
      Args.Append (To_Unbounded_String ("-f"));
      if First_Result.Kind = Success then
         Run_Alire (Args, First_Workspace);
         First_Result := Command_Result;
      end if;
      if First_Result.Kind = Success then
         Quality_Manager.Reproducibility.Manifest
           (First_Workspace, True, First_Build, First_Count, First_Result);
      end if;
      if Second_Result.Kind = Success then
         Run_Alire (Args, Second_Workspace);
         Second_Result := Command_Result;
      end if;
      if Second_Result.Kind = Success then
         Quality_Manager.Reproducibility.Manifest
           (Second_Workspace, True, Second_Build, Second_Count, Second_Result);
      end if;
      Checks.Clean_Build := First_Result.Kind = Success and then First_Count > 0;
      Checks.Reproducible_Build :=
        Checks.Clean_Build and then Second_Result.Kind = Success and then Second_Count > 0
        and then First_Build = Second_Build;
      Quality_Manager.Reproducibility.Remove_Workspace (First_Workspace, Cleanup_Result);
      if Cleanup_Result.Kind /= Success then
         Infrastructure_Failure := True;
      end if;
      Quality_Manager.Reproducibility.Remove_Workspace (Second_Workspace, Cleanup_Result);
      if Cleanup_Result.Kind /= Success then
         Infrastructure_Failure := True;
      end if;
   end Run_Builds;

   function Proof_Project return String is
      Search : Ada.Directories.Search_Type;
      Item_Entry : Ada.Directories.Directory_Entry_Type;
      Found  : Unbounded_String;
      Count  : Natural := 0;
   begin
      Ada.Directories.Start_Search
        (Search, Project_Path, "*.gpr",
         [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item_Entry);
         Found := To_Unbounded_String (Ada.Directories.Full_Name (Item_Entry));
         Count := Count + 1;
      end loop;
      Ada.Directories.End_Search (Search);
      return (if Count = 1 then To_String (Found) else "");
   exception
      when others =>
         return "";
   end Proof_Project;

   function Valid_Proof_Report return Boolean is
      package IO renames Ada.Streams.Stream_IO;
      use type IO.Count;
      use type Ada.Streams.Stream_Element_Offset;
      Path : constant String := Project_Path & "/obj/gnatprove/gnatprove.out";
      File : IO.File_Type;
   begin
      IO.Open (File, IO.In_File, Path);
      declare
         Length : constant IO.Count := IO.Size (File);
      begin
         if Length = 0 or else Length > 4 * 1_024 * 1_024 then
            IO.Close (File);
            return False;
         end if;
         declare
            Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Length));
            Last : Ada.Streams.Stream_Element_Offset;
            Text : String (1 .. Natural (Length));
         begin
            IO.Read (File, Data, Last);
            IO.Close (File);
            if Last /= Data'Last then
               return False;
            end if;
            for Index in Text'Range loop
               Text (Index) := Character'Val
                 (Data (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
            return Ada.Strings.Fixed.Index (Text, "Summary of SPARK analysis") > 0
              and then Ada.Strings.Fixed.Index (Text, "Analyzed ") > 0
              and then Ada.Strings.Fixed.Index (Text, " and proved") > 0;
         end;
      end;
   exception
      when others =>
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         return False;
   end Valid_Proof_Report;

   procedure Run_Tests_And_Proof is
      Project : constant String := Proof_Project;
      Report  : constant String := Project_Path & "/obj/gnatprove/gnatprove.out";
   begin
      Args.Clear;
      Args.Append (To_Unbounded_String ("test"));
      Run_Alire (Args);
      Checks.AUnit_Passed := Command_Result.Kind = Success;
      if Proof_Applicable then
         if Project = "" then
            Checks.GNATprove_Passed := False;
         else
            if Ada.Directories.Exists (Report) then
               Ada.Directories.Delete_File (Report);
            end if;
            Args.Clear;
            Args.Append (To_Unbounded_String ("exec"));
            Args.Append (To_Unbounded_String ("--"));
            Args.Append (To_Unbounded_String ("gnatprove"));
            Args.Append (To_Unbounded_String ("-P"));
            Args.Append (To_Unbounded_String (Project));
            Args.Append (To_Unbounded_String ("--mode=prove"));
            Args.Append (To_Unbounded_String ("--level=2"));
            Args.Append (To_Unbounded_String ("--checks-as-errors=on"));
            Args.Append (To_Unbounded_String ("--warnings=error"));
            Args.Append (To_Unbounded_String ("--report=all"));
            Run_Alire (Args);
            Checks.GNATprove_Passed := Command_Result.Kind = Success and then Valid_Proof_Report;
         end if;
      else
         Checks.GNATprove_Passed := True;
      end if;
   end Run_Tests_And_Proof;

   procedure Revalidate_Identity is
      Final_Commit, Status : Unbounded_String;
      Ignored : Natural;
   begin
      Quality_Manager.Reproducibility.Manifest
        (Project_Path, False, Source_After, Ignored, Command_Result);
      if Command_Result.Kind /= Success then
         Infrastructure_Failure := True;
      end if;
      Args.Clear;
      Args.Append (To_Unbounded_String ("rev-parse"));
      Args.Append (To_Unbounded_String ("HEAD"));
      Execute_Simple (Git_Executable, Args, Project_Path, Final_Commit, Command_Result);
      if Command_Result.Kind not in Success | Negative_Result then
         Infrastructure_Failure := True;
      end if;
      Args.Clear;
      Args.Append (To_Unbounded_String ("status"));
      Args.Append (To_Unbounded_String ("--porcelain"));
      Args.Append (To_Unbounded_String ("--untracked-files=no"));
      Execute_Simple (Git_Executable, Args, Project_Path, Status, Command_Result);
      if Command_Result.Kind not in Success | Negative_Result then
         Infrastructure_Failure := True;
      end if;
      Checks.Source_Unchanged := Length (Source_Before) > 0 and then Source_Before = Source_After;
      Checks.Git_Clean := Final_Commit = Commit
        and then Final_Commit = To_Unbounded_String (Candidate_Commit)
        and then Length (Status) = 0;
      Checks.Candidate_Commit := Final_Commit;
   end Revalidate_Identity;

   function All_Checks_Pass return Boolean is
   begin
      if Commit /= To_Unbounded_String (Candidate_Commit) then return False;
      elsif not Checks.Clean_Build then return False;
      elsif not Checks.Reproducible_Build then return False;
      elsif not Checks.Source_Unchanged then return False;
      elsif not Checks.Git_Clean then return False;
      elsif not Checks.AUnit_Passed then return False;
      elsif not Checks.GNATprove_Passed then return False;
      else return not Infrastructure_Failure;
      end if;
   end All_Checks_Pass;

   procedure Save_Checks is
   begin
      Checks.Release_Checks_Passed := All_Checks_Pass;
      Stored :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
         Entity_Key => To_Unbounded_String (Key), State => To_Unbounded_String ("OBSERVED"),
         Payload => To_Unbounded_String
           ("{""candidate_commit"":" & Q (To_String (Checks.Candidate_Commit))
            & ",""source_fingerprint"":" & Q (Source_Fingerprint)
            & ",""release_config_digest"":" & Q (Release_Config_Digest)
            & ",""clean_build"":" & B (Checks.Clean_Build)
            & ",""reproducible_build"":" & B (Checks.Reproducible_Build)
            & ",""source_unchanged"":" & B (Checks.Source_Unchanged)
            & ",""git_clean"":" & B (Checks.Git_Clean)
            & ",""aunit_passed"":" & B (Checks.AUnit_Passed)
            & ",""proof_applicable"":" & B (Checks.Proof_Applicable)
            & ",""gnatprove_passed"":" & B (Checks.GNATprove_Passed)
            & ",""coverage_basis_points"":" & N (Checks.Coverage_Basis_Points)
            & ",""release_checks_passed"":" & B (Checks.Release_Checks_Passed) & "}"),
         Terminal => True, Generation => 1);
      Quality_Manager.Storage.Put (Item.Database.all, Stored, Result);
   end Save_Checks;

   procedure Set_Outcome is
   begin
      if Result.Kind = Success and then Infrastructure_Failure then
         Result := Make_Result
           (Execution_Error, "release-check execution failed", "qm.release.check-execution");
      elsif Result.Kind = Success and then not Checks.Release_Checks_Passed then
         Result := Make_Result
           (Negative_Result, Check_Failure_Message (Checks, Candidate_Commit), "qm.release.checks");
      end if;
   end Set_Outcome;
begin
   Checks := (others => <>);
   Validate_Context;
   if Result.Kind /= Success then
      return;
   end if;
   Quality_Manager.Storage.Read (Item.Database.all, Key, Stored, Result);
   if Result.Kind = Success then
      Decode_Stored;
      Finish_Journal;
      Set_Outcome;
      return;
   elsif Result.Kind /= Not_Found then
      return;
   end if;
   Prepare_Journal;
   if Result.Kind /= Success then
      return;
   end if;
   Capture_Identity;
   Run_Builds;
   Run_Tests_And_Proof;
   Revalidate_Identity;
   Save_Checks;
   if Result.Kind = Success then
      Finish_Journal;
   end if;
   Set_Outcome;
end Run_Local_Checks_With_Tools;

