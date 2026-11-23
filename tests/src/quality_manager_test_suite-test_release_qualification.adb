separate (Quality_Manager_Test_Suite)
procedure Test_Release_Qualification (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path        : constant String := "/tmp/quality-manager-release.database";
   Export_Path : constant String := "/tmp/quality-manager-release-evidence.json";
   Store       : aliased Quality_Manager.Storage.Store;
   Context     : Quality_Manager.Releases.Context;
   Result      : Quality_Manager.Results.Operation_Result;
   Release_Id  : Unbounded_String;
   Decision    : Quality_Manager.Releases.Qualification_Decision;
   Invalidated : Boolean;
   Project     : constant Quality_Manager.Identities.Project_Key :=
     (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
   Assessment  : constant Quality_Manager.Verification.Assessment_Evidence :=
     (Assessment_Id => 5, Project_Id => 7, Project_Path => To_Unbounded_String ("/project"),
      Source_Fingerprint => To_Unbounded_String ("source-1"),
      Policy_Fingerprint => To_Unbounded_String ("policy-1"),
      Toolchain_Fingerprint => To_Unbounded_String ("toolchain-1"),
      Completed => True, Complete => True, Indicator_Count => 33, Violations => 0,
      Coverage_Basis_Points => 9_000, Proof_Applicable => True, Proof_Passed => True);
   Checks : Quality_Manager.Releases.Check_Results :=
     (Candidate_Commit => To_Unbounded_String ("commit-1"),
      Source_Fingerprint => To_Unbounded_String ("source-1"),
      Release_Config_Digest => To_Unbounded_String ("release-config-1"),
      Clean_Build => True, Reproducible_Build => True,
      Source_Unchanged => True, Git_Clean => True, AUnit_Passed => True,
      Proof_Applicable => True, GNATprove_Passed => True,
      Coverage_Basis_Points => 8_999, Release_Checks_Passed => True);
   References : constant Quality_Manager.Releases.Evidence_References :=
     (Improve_Audit => To_Unbounded_String ("improve-audit-1"),
      Native_Audit => To_Unbounded_String ("native-audit-1"),
      Regression_Evidence => To_Unbounded_String ("comparison-1"),
      Authorization_Audit => To_Unbounded_String ("approval-1"));
   Recovered_Checks : Quality_Manager.Releases.Check_Results;
   Actual_Checks    : Quality_Manager.Releases.Check_Results;
   Journal_Record   : Quality_Manager.Storage.Stored_Entity;
   Release_Fixture  : constant String :=
     (if Ada.Directories.Exists (Ada.Directories.Current_Directory & "/fixtures/release_project")
      then Ada.Directories.Current_Directory & "/fixtures/release_project"
      else Ada.Directories.Current_Directory & "/tests/fixtures/release_project");
   Tool_Fixture     : constant String :=
     (if Ada.Directories.Exists (Ada.Directories.Current_Directory & "/bin/qm_adapter_fixture")
      then Ada.Directories.Current_Directory & "/bin/qm_adapter_fixture"
      else Ada.Directories.Current_Directory & "/tests/bin/qm_adapter_fixture");
   Nondeterministic_Marker : constant String := Release_Fixture & "/qm_nondeterministic.fixture";
   Mutation_Marker : constant String := Release_Fixture & "/qm_mutate_source.fixture";
   Proof_Marker : constant String := Release_Fixture & "/qm_proof_invalid.fixture";
   Empty_Proof_Marker : constant String := Release_Fixture & "/qm_proof_empty.fixture";
   Extra_Project : constant String := Release_Fixture & "/review-extra.gpr";
   Mutation_Source : constant String :=
     Release_Fixture & "/src/quality_manager-review-mutation.adb";
   Integrated_Marker : constant String := "/tmp/qm-adapter-project-integrated";

   procedure Touch (Path : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "fixture");
      Ada.Text_IO.Close (File);
   end Touch;

   procedure Delete_If_Present (Target : String) is
   begin
      if Ada.Directories.Exists (Target) then
         Ada.Directories.Delete_File (Target);
      end if;
   end Delete_If_Present;

   procedure Check_Corrupt_Evidence (Commit, Payload : String) is
      Corrupt_Id : Unbounded_String;
      Candidate  : Quality_Manager.Storage.Schema.Release;
      Evidence   : Quality_Manager.Storage.Stored_Entity;
   begin
      Quality_Manager.Releases.Create
        (Context, Project, Commit, "source-corrupt", "policy-1", "toolchain-1",
         "release-config-1", Corrupt_Id, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "corrupt evidence fixture created");
      Candidate :=
        (Release_Id => Corrupt_Id, Project => Project,
         Candidate_Commit => To_Unbounded_String (Commit),
         Source_Digest => To_Unbounded_String ("source-corrupt"),
         Policy_Digest => To_Unbounded_String ("policy-1"),
         Toolchain => To_Unbounded_String ("toolchain-1"),
         Release_Config => To_Unbounded_String ("release-config-1"),
         Generation => 1, Final_Assessment => 1, Coverage_Basis_Points => 9_000,
         State => Quality_Manager.Model.Verified);
      Quality_Manager.Storage.Records.Save (Store, Candidate, Result);
      Evidence :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
         Entity_Key => To_Unbounded_String
           ("release-evidence:" & To_String (Corrupt_Id) & ":1"),
         State => To_Unbounded_String ("QUALIFIED"),
         Payload => To_Unbounded_String (Payload), Terminal => True, Generation => 1);
      Quality_Manager.Storage.Put (Store, Evidence, Result);
      Quality_Manager.Releases.Export_Evidence
        (Context, To_String (Corrupt_Id), Export_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "corrupt release evidence is rejected before export");
   end Check_Corrupt_Evidence;

   procedure Check_Corrupt_Chunk_Digest is
      Corrupt_Id : Unbounded_String;
      Candidate  : Quality_Manager.Storage.Schema.Release;
      Evidence   : Quality_Manager.Storage.Stored_Entity;
   begin
      Quality_Manager.Releases.Create
        (Context, Project, "commit-corrupt-chunk", "source-corrupt", "policy-1", "toolchain-1",
         "release-config-1", Corrupt_Id, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success, "chunk digest fixture created");
      Candidate :=
        (Release_Id => Corrupt_Id, Project => Project,
         Candidate_Commit => To_Unbounded_String ("commit-corrupt-chunk"),
         Source_Digest => To_Unbounded_String ("source-corrupt"),
         Policy_Digest => To_Unbounded_String ("policy-1"),
         Toolchain => To_Unbounded_String ("toolchain-1"),
         Release_Config => To_Unbounded_String ("release-config-1"),
         Generation => 1, Final_Assessment => 1, Coverage_Basis_Points => 9_000,
         State => Quality_Manager.Model.Verified);
      Quality_Manager.Storage.Records.Save (Store, Candidate, Result);
      Evidence :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
         Entity_Key => To_Unbounded_String
           ("release-evidence-chunk:" & To_String (Corrupt_Id) & ":1:1"),
         State => To_Unbounded_String ("CHUNK"),
         Payload => To_Unbounded_String ("{""schema_version"":1}"),
         Terminal => True, Generation => 1);
      Quality_Manager.Storage.Put (Store, Evidence, Result);
      Evidence.Entity_Key := To_Unbounded_String
        ("release-evidence:" & To_String (Corrupt_Id) & ":1");
      Evidence.State := To_Unbounded_String ("QUALIFIED");
      Evidence.Payload := To_Unbounded_String ("digest=wrong" & ASCII.LF & "chunks=1");
      Quality_Manager.Storage.Put (Store, Evidence, Result);
      Quality_Manager.Releases.Export_Evidence
        (Context, To_String (Corrupt_Id), Export_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "chunked release evidence is rejected when its bundle digest differs");
   end Check_Corrupt_Chunk_Digest;

   procedure Cleanup is
   begin
      if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
      if Ada.Directories.Exists (Export_Path) then Ada.Directories.Delete_File (Export_Path); end if;
      Delete_If_Present (Nondeterministic_Marker);
      Delete_If_Present (Mutation_Marker);
      Delete_If_Present (Proof_Marker);
      Delete_If_Present (Empty_Proof_Marker);
      Delete_If_Present (Extra_Project);
      Delete_If_Present (Mutation_Source);
      Delete_If_Present (Integrated_Marker);
   end Cleanup;
begin
   Cleanup;
   begin
      Quality_Manager.Releases.Qualify_Configured ("", "/tmp/no-such-release-config", False);
      Assert (False, "empty configured release qualification must fail");
   exception
      when Quality_Manager.Releases.Release_Error => null;
   end;
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "release store opened");
   Quality_Manager.Releases.Create
     (Context, Project, "commit", "source", "policy", "toolchain", "config",
      Release_Id, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
           "uninitialized release context fails closed");
   Quality_Manager.Releases.Export_Evidence
     (Context, "missing", Export_Path, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
           "uninitialized release evidence lookup fails closed");
   Quality_Manager.Releases.Run_Local_Checks
     (Context, 1, "/project", "commit", "source", "config", 9_000,
      False, Recovered_Checks, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
           "uninitialized release checks fail closed");
   Quality_Manager.Releases.Initialize (Context, Store'Unchecked_Access);
   declare
      Workspace : constant String := "/tmp/quality-manager-release-repro-test";
      Special_Source : constant String := "/tmp/quality-manager-release-special-source";
      Special_Workspace : constant String := "/tmp/quality-manager-release-special-target";
      Digest : Unbounded_String;
      Count  : Natural;
      Local  : Quality_Manager.Results.Operation_Result;
      Created : Boolean;
   begin
      Quality_Manager.Reproducibility.Remove_Workspace (Workspace, Local);
      Assert (Local.Kind = Quality_Manager.Results.Success,
              "stale clean release workspace is absent");
      Quality_Manager.Reproducibility.Prepare_Clean_Workspace
        (Release_Fixture, Workspace, Local);
      Assert
        (Local.Kind = Quality_Manager.Results.Success,
         "clean release workspace is independently prepared: " & Quality_Manager.Results.Message (Local));
      Quality_Manager.Reproducibility.Prepare_Clean_Workspace
        (Release_Fixture, Workspace, Local);
      Assert (Local.Kind = Quality_Manager.Results.Not_Ready,
              "an existing clean workspace is never reused implicitly");
      Quality_Manager.Reproducibility.Manifest (Workspace, False, Digest, Count, Local);
      Assert
        (Local.Kind = Quality_Manager.Results.Success and then Length (Digest) = 64,
         "clean release source has a deterministic manifest: " & Quality_Manager.Results.Message (Local));
      Quality_Manager.Reproducibility.Remove_Workspace (Workspace, Local);
      Assert (Local.Kind = Quality_Manager.Results.Success, "clean release workspace is removed");
      Quality_Manager.Reproducibility.Prepare_Clean_Workspace
        ("/tmp/no-such-release-source", Workspace, Local);
      Assert (Local.Kind = Quality_Manager.Results.Not_Found,
              "a missing release source cannot create a clean workspace");
      Quality_Manager.Reproducibility.Manifest
        ("/tmp/no-such-release-source", False, Digest, Count, Local);
      Assert (Local.Kind = Quality_Manager.Results.Integrity_Error,
              "a missing release source cannot produce a manifest");
      Quality_Manager.Reproducibility.Remove_Workspace ("/tmp/not-a-release-workspace", Local);
      Assert (Local.Kind = Quality_Manager.Results.Invalid_Request,
              "workspace cleanup rejects paths outside its exact namespace");
      if Ada.Directories.Exists (Special_Workspace) then
         Ada.Directories.Delete_Tree (Special_Workspace);
      end if;
      if Ada.Directories.Exists (Special_Source) then
         Created := Hostkit.FS.Delete_File (Special_Source & "/unsupported");
         Created := Hostkit.FS.Delete_File (Special_Source & "/nested/unsupported") or else Created;
         Created := Hostkit.FS.Delete_Link (Special_Source & "/unsupported-link") or else Created;
         Created := Hostkit.FS.Delete_Empty_Directory (Special_Source & "/nested") or else Created;
         Created := Hostkit.FS.Delete_Empty_Directory (Special_Source) or else Created;
      end if;
      Ada.Directories.Create_Directory (Special_Source);
      Ada.Directories.Create_Directory (Special_Source & "/nested");
      Created := Hostkit.FS.Create_FIFO (Special_Source & "/nested/unsupported", 8#600#);
      Assert (Created, "special-file release fixture is created");
      Quality_Manager.Reproducibility.Prepare_Clean_Workspace
        (Special_Source, Special_Workspace, Local);
      Assert (Local.Kind = Quality_Manager.Results.Invalid_Request,
              "clean workspace creation rejects special source files");
      Quality_Manager.Reproducibility.Manifest
        (Special_Source, False, Digest, Count, Local);
      Assert (Local.Kind = Quality_Manager.Results.Integrity_Error,
              "source manifests reject special source files");
      Created := Hostkit.FS.Delete_File (Special_Source & "/nested/unsupported");
      Created := Hostkit.FS.Delete_Empty_Directory (Special_Source & "/nested") or else Created;
      if Ada.Directories.Exists (Special_Source) then
         Created := Hostkit.FS.Delete_Empty_Directory (Special_Source) or else Created;
      end if;
      if Ada.Directories.Exists (Special_Workspace) then
         Ada.Directories.Delete_Tree (Special_Workspace);
      end if;
      Ada.Directories.Create_Directory (Special_Source);
      Created := Hostkit.FS.Create_Link
        (Release_Fixture & "/alire.toml", Special_Source & "/unsupported-link");
      Assert (Created, "symbolic-link release fixture is created");
      Quality_Manager.Reproducibility.Prepare_Clean_Workspace
        (Special_Source, Special_Workspace, Local);
      Assert (Local.Kind = Quality_Manager.Results.Invalid_Request,
              "clean workspace creation rejects symbolic links");
      Quality_Manager.Reproducibility.Manifest
        (Special_Source, False, Digest, Count, Local);
      Assert (Local.Kind = Quality_Manager.Results.Integrity_Error,
              "source manifests reject symbolic links");
      Created := Hostkit.FS.Delete_Link (Special_Source & "/unsupported-link");
      Created := Hostkit.FS.Delete_Empty_Directory (Special_Source) or else Created;
      Assert (Created, "symbolic-link release fixture is removed");
      if Ada.Directories.Exists (Special_Workspace) then
         Ada.Directories.Delete_Tree (Special_Workspace);
      end if;
   end;
   declare
      Wrong_Kind : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Project_Record,
         Entity_Key => To_Unbounded_String ("release:wrong-kind"),
         State => To_Unbounded_String ("DISCOVERED"), Payload => To_Unbounded_String ("{}"),
         Terminal => False, Generation => 1);
      Incomplete : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
         Entity_Key => To_Unbounded_String ("release:incomplete"),
         State => To_Unbounded_String ("DISCOVERED"), Payload => To_Unbounded_String ("{}"),
         Terminal => False, Generation => 1);
      Unknown_State : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
         Entity_Key => To_Unbounded_String ("release:unknown-state"),
         State => To_Unbounded_String ("UNKNOWN_STATE"),
         Payload => To_Unbounded_String
           ("{""quality_project_id"":7,""generation"":1}"),
         Terminal => False, Generation => 1);
   begin
      Quality_Manager.Storage.Put (Store, Wrong_Kind, Result);
      Quality_Manager.Releases.Export_Evidence (Context, "wrong-kind", Export_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "release identity cannot alias another record kind");
      Quality_Manager.Storage.Put (Store, Incomplete, Result);
      Quality_Manager.Releases.Export_Evidence (Context, "incomplete", Export_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "incomplete durable release identity is rejected");
      Quality_Manager.Storage.Put (Store, Unknown_State, Result);
      Quality_Manager.Releases.Export_Evidence (Context, "unknown-state", Export_Path, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "unknown durable release state is a compatibility error");
   end;
   Quality_Manager.Releases.Create
     (Context, Project, "", "source", "policy", "toolchain", "config",
      Release_Id, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "incomplete release candidate identity is rejected");
   Quality_Manager.Releases.Create
     (Context, Project, "commit-1", "source-1", "policy-1", "toolchain-1",
      "release-config-1", Release_Id, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
           "immutable release candidate identity created");
   Assert (Length (Release_Id) = 64,
           "immutable release candidate identity created");
   Quality_Manager.Releases.Evaluate
     (Context, To_String (Release_Id), Assessment, Checks, References, Decision, Result);
Assert (Result.Kind = Quality_Manager.Results.Negative_Result,
      "coverage below 90 percent blocks qualification");
   Assert (not Decision.Qualified,
      "coverage below 90 percent blocks qualification");
   Quality_Manager.Releases.Export_Evidence
     (Context, To_String (Release_Id), Export_Path, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Ready,
           "unqualified candidate cannot export evidence");
   Checks.Coverage_Basis_Points := 9_000;
   Quality_Manager.Releases.Evaluate
     (Context, To_String (Release_Id), Assessment, Checks, References, Decision, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "all exact release gates produce a qualified evidence bundle");
   Assert (Decision.Qualified,
      "all exact release gates produce a qualified evidence bundle");
   Assert (Length (Decision.Bundle_Digest) = 64,
      "all exact release gates produce a qualified evidence bundle");
   Quality_Manager.Releases.Export_Evidence
     (Context, To_String (Release_Id), Export_Path, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "qualified evidence exports only after digest verification");
   Assert (Ada.Directories.Exists (Export_Path),
      "qualified evidence exports only after digest verification");
   Quality_Manager.Releases.Export_Evidence
     (Context, To_String (Release_Id), "/tmp/no-such-release-output/evidence.json", Result);
   Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
           "release evidence export reports an unwritable destination");
   Check_Corrupt_Evidence ("commit-corrupt-envelope", "not-an-envelope");
   Check_Corrupt_Evidence
     ("commit-corrupt-digest", "digest=wrong" & ASCII.LF & "{""schema_version"":1}");
   Check_Corrupt_Evidence
     ("commit-corrupt-zero-chunks", "digest=wrong" & ASCII.LF & "chunks=0");
   Check_Corrupt_Evidence
     ("commit-corrupt-count", "digest=wrong" & ASCII.LF & "chunks=not-a-number");
   Check_Corrupt_Evidence
     ("commit-missing-chunk", "digest=wrong" & ASCII.LF & "chunks=1");
   Check_Corrupt_Chunk_Digest;
   Quality_Manager.Releases.Invalidate_If_Changed
     (Context, To_String (Release_Id), "commit-2", "source-2", Invalidated, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
           "source modification invalidates a prior qualification");
   Assert (Invalidated,
           "source modification invalidates a prior qualification");
   Quality_Manager.Releases.New_Generation
     (Context, To_String (Release_Id), "commit-1", "source-1", "policy-1", "toolchain-1",
      "release-config-1", Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "candidate generation requires a new exact source");
   Quality_Manager.Releases.New_Generation
     (Context, To_String (Release_Id), "commit-2", "source-2", "policy-1", "toolchain-1",
      "release-config-1", Result);
   Assert (Result.Kind = Quality_Manager.Results.Success,
           "source-changing remediation creates a new candidate generation");
   Quality_Manager.Storage.Prepare_Operation
     (Store, 300, "release-checks", "fixture", "release-checks:300", Result);
   Quality_Manager.Storage.Advance_Operation
     (Store, 300, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
      "release-checks:300", "fixture started", Result);
   Quality_Manager.Releases.Run_Local_Checks
     (Context, 0, "/project", "commit-2", "source-2", "release-config-1", 9_000,
      False, Recovered_Checks, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "release checks require a durable operation identity");
   Journal_Record :=
     (Internal_Id => 1, Kind => Quality_Manager.Storage.Release_Record,
      Entity_Key => To_Unbounded_String ("release-checks:300"),
      State => To_Unbounded_String ("OBSERVED"),
      Payload => To_Unbounded_String
        ("{""candidate_commit"":""commit-2"",""source_fingerprint"":""source-2""," &
         """release_config_digest"":""release-config-1"",""clean_build"":true," &
         """reproducible_build"":true,""source_unchanged"":true,""git_clean"":true," &
         """aunit_passed"":true,""proof_applicable"":false," &
         """gnatprove_passed"":true,""coverage_basis_points"":9000," &
         """release_checks_passed"":true}"),
      Terminal => True, Generation => 1);
   Quality_Manager.Storage.Put (Store, Journal_Record, Result);
   Quality_Manager.Releases.Run_Local_Checks
     (Context, 300, "/project", "commit-2", "source-2", "release-config-1", 9_000,
      False, Recovered_Checks, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "interrupted idempotent release checks adopt their durable observed result");
   Assert (Recovered_Checks.Release_Checks_Passed,
      "interrupted idempotent release checks adopt their durable observed result");
   Quality_Manager.Storage.Read (Store, "journal:300", Journal_Record, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "adopted release checks complete their recovery journal");
   Assert (To_String (Journal_Record.State) = Quality_Manager.Journal.Journal_State'Image
        (Quality_Manager.Journal.Committed),
      "adopted release checks complete their recovery journal");
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 0, Release_Fixture, "fixture-commit", "source-2", "release-config-1",
      9_000, False, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "release checks require a durable operation identity");
   declare
      Conflict : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1, Kind => Quality_Manager.Storage.Project_Record,
         Entity_Key => To_Unbounded_String ("journal:312"),
         State => To_Unbounded_String ("CONFLICT"), Payload => To_Unbounded_String ("conflict"),
         Terminal => False, Generation => 1);
      Closed_Store : aliased Quality_Manager.Storage.Store;
      Closed_Context : Quality_Manager.Releases.Context;
   begin
      Quality_Manager.Storage.Put (Store, Conflict, Result);
      Quality_Manager.Releases.Run_Local_Checks_With_Tools
        (Context, 312, Release_Fixture, "fixture-commit", "source-2", "release-config-1",
         9_000, False, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "release checks reject a conflicting durable journal identity");
      Quality_Manager.Storage.Open
        (Closed_Store, "/tmp/quality-manager-release-closed.database", True, Result);
      Quality_Manager.Releases.Initialize (Closed_Context, Closed_Store'Unchecked_Access);
      Quality_Manager.Storage.Close (Closed_Store, Result);
      Quality_Manager.Releases.Run_Local_Checks_With_Tools
        (Closed_Context, 313, Release_Fixture, "fixture-commit", "source-2", "release-config-1",
         9_000, False, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
      Assert (Result.Kind /= Quality_Manager.Results.Success,
              "release checks fail closed when persistent storage is unavailable: "
              & Quality_Manager.Results.Message (Result));
      if Ada.Directories.Exists ("/tmp/quality-manager-release-closed.database") then
         Ada.Directories.Delete_File ("/tmp/quality-manager-release-closed.database");
      end if;
   end;
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 301, Release_Fixture,
      "fixture-commit",
      "source-2", "release-config-1", 9_000, False,
      Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "local release checks run clean build, reproducibility, and test gates: "
      & Quality_Manager.Results.Message (Result)
      & " commit=" & To_String (Actual_Checks.Candidate_Commit)
      & " clean=" & Boolean'Image (Actual_Checks.Clean_Build)
      & " reproducible=" & Boolean'Image (Actual_Checks.Reproducible_Build)
      & " tests=" & Boolean'Image (Actual_Checks.AUnit_Passed));
   Assert (Actual_Checks.Clean_Build,
      "local release checks run clean build, reproducibility, and test gates: "
      & Quality_Manager.Results.Message (Result)
      & " commit=" & To_String (Actual_Checks.Candidate_Commit)
      & " clean=" & Boolean'Image (Actual_Checks.Clean_Build)
      & " reproducible=" & Boolean'Image (Actual_Checks.Reproducible_Build)
      & " tests=" & Boolean'Image (Actual_Checks.AUnit_Passed));
   Assert (Actual_Checks.Reproducible_Build,
      "local release checks run clean build, reproducibility, and test gates: "
      & Quality_Manager.Results.Message (Result)
      & " commit=" & To_String (Actual_Checks.Candidate_Commit)
      & " clean=" & Boolean'Image (Actual_Checks.Clean_Build)
      & " reproducible=" & Boolean'Image (Actual_Checks.Reproducible_Build)
      & " tests=" & Boolean'Image (Actual_Checks.AUnit_Passed));
   Assert (Actual_Checks.AUnit_Passed,
      "local release checks run clean build, reproducibility, and test gates: "
      & Quality_Manager.Results.Message (Result)
      & " commit=" & To_String (Actual_Checks.Candidate_Commit)
      & " clean=" & Boolean'Image (Actual_Checks.Clean_Build)
      & " reproducible=" & Boolean'Image (Actual_Checks.Reproducible_Build)
      & " tests=" & Boolean'Image (Actual_Checks.AUnit_Passed));
   Assert (Actual_Checks.Release_Checks_Passed,
      "local release checks run clean build, reproducibility, and test gates: "
      & Quality_Manager.Results.Message (Result)
      & " commit=" & To_String (Actual_Checks.Candidate_Commit)
      & " clean=" & Boolean'Image (Actual_Checks.Clean_Build)
      & " reproducible=" & Boolean'Image (Actual_Checks.Reproducible_Build)
      & " tests=" & Boolean'Image (Actual_Checks.AUnit_Passed));
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 302, Release_Fixture,
      "fixture-commit",
      "source-2", "release-config-1", 9_000, True,
      Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
      "applicable proof gate is executed through the configured release toolchain");
   Assert (Actual_Checks.GNATprove_Passed,
      "applicable proof gate is executed through the configured release toolchain");
   Touch (Nondeterministic_Marker);
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 305, Release_Fixture, "fixture-commit", "source-2", "release-config-1", 9_000,
      False, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Negative_Result
      and then not Actual_Checks.Reproducible_Build,
      "successful builds with different artifacts fail reproducibility qualification");
   Delete_If_Present (Nondeterministic_Marker);

   Touch (Mutation_Marker);
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 306, Release_Fixture, "fixture-commit", "source-2", "release-config-1", 9_000,
      False, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Negative_Result
      and then not Actual_Checks.Source_Unchanged,
      "a successful test command that changes authored Ada source invalidates qualification");
   Delete_If_Present (Mutation_Marker);
   Delete_If_Present (Mutation_Source);

   Touch (Proof_Marker);
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 307, Release_Fixture, "fixture-commit", "source-2", "release-config-1", 9_000,
      True, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Negative_Result
      and then not Actual_Checks.GNATprove_Passed,
      "applicable proof without a valid proof report is rejected");
   Delete_If_Present (Proof_Marker);
   Touch (Empty_Proof_Marker);
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 309, Release_Fixture, "fixture-commit", "source-2", "release-config-1", 9_000,
      True, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Negative_Result
      and then not Actual_Checks.GNATprove_Passed,
      "an empty proof report cannot satisfy an applicable release proof gate");
   Delete_If_Present (Empty_Proof_Marker);
   Touch (Extra_Project);
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 310, Release_Fixture, "fixture-commit", "source-2", "release-config-1", 9_000,
      True, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Negative_Result
      and then not Actual_Checks.GNATprove_Passed,
      "ambiguous proof project selection cannot satisfy the release proof gate");
   Delete_If_Present (Extra_Project);
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 308, "/tmp/no-such-release-source", "fixture-commit", "source-2",
      "release-config-1", 9_000, False, Tool_Fixture, Tool_Fixture, Actual_Checks, Result);
   Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
           "unavailable clean release source is an infrastructure failure");
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 303, Release_Fixture, "commit-2", "source-2", "release-config-1", 9_000,
      False, "/tmp/no-such-git-tool", "/tmp/no-such-alire-tool", Actual_Checks, Result);
   Assert (Result.Kind = Quality_Manager.Results.Execution_Error,
           "release check infrastructure start failures are distinguished from negative gates");
   Quality_Manager.Releases.Run_Local_Checks_With_Tools
     (Context, 304, Release_Fixture, "commit-2", "source-2", "release-config-1", 9_000,
      False, "/bin/false", "/bin/false", Actual_Checks, Result);
   Assert (Result.Kind = Quality_Manager.Results.Negative_Result,
           "completed failing release commands remain negative gate outcomes");
   declare
      Release_Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database-a"), 7, To_Unbounded_String (Release_Fixture));
      Candidate_Commit : constant String := "fixture-commit";
      Release_Quality : Quality_Manager.Integrations.Quality.Adapter;
      Qualified_Id    : Unbounded_String;
      First_Digest    : Unbounded_String;
   begin
      Quality_Manager.Integrations.Quality.Initialize
        (Release_Quality, Tool_Fixture, "release-quality.db", Release_Fixture);
      Quality_Manager.Releases.Create
        (Context, Release_Project, Candidate_Commit, "candidate-source", "policy", "toolchain",
         "release-config-qualified", Qualified_Id, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "configured qualification fixture creates an exact candidate");
      Quality_Manager.Releases.Qualify_With_Tools
        (Context, Release_Quality, To_String (Qualified_Id), Tool_Fixture, Tool_Fixture,
         Decision, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "configured qualification obtains fresh evidence and runs every local gate: "
         & Quality_Manager.Results.Message (Result));
      Assert (Decision.Qualified,
         "configured qualification obtains fresh evidence and runs every local gate: "
         & Quality_Manager.Results.Message (Result));
      Assert (Length (Decision.Bundle_Digest) = 64,
         "configured qualification obtains fresh evidence and runs every local gate: "
         & Quality_Manager.Results.Message (Result));
      First_Digest := Decision.Bundle_Digest;
      Quality_Manager.Releases.Qualify_With_Tools
        (Context, Release_Quality, To_String (Qualified_Id), Tool_Fixture, Tool_Fixture,
         Decision, Result);
Assert (Result.Kind = Quality_Manager.Results.Success,
         "repeated qualification adopts journaled assessment and check evidence idempotently");
      Assert (Decision.Qualified,
         "repeated qualification adopts journaled assessment and check evidence idempotently");
      Assert (Decision.Bundle_Digest = First_Digest,
         "repeated qualification adopts journaled assessment and check evidence idempotently");
   end;
   declare
      Release_Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
         7, To_Unbounded_String (Release_Fixture));
      Release_Quality : Quality_Manager.Integrations.Quality.Adapter;
      Planner         : Quality_Manager.Integrations.Improve.Adapter;
      Runner          : Quality_Manager.Integrations.Runner.Adapter;
      Scheduler       : aliased Quality_Manager.Scheduler.Scheduler_Type;
      Maintenance_Item : Quality_Manager.Maintenance.Context;
      Remediation_Id  : Unbounded_String;
      Approval        : Quality_Manager.Storage.Schema.Approval;
      Candidate       : Quality_Manager.Storage.Stored_Entity;
   begin
      Delete_If_Present (Integrated_Marker);
      Quality_Manager.Integrations.Quality.Initialize
        (Release_Quality, Tool_Fixture, "release-remediation-quality.db", Release_Fixture);
      Quality_Manager.Integrations.Improve.Initialize
        (Planner, Tool_Fixture, "improve.toml", "release-remediation-quality.db", "improve.db");
      Quality_Manager.Integrations.Runner.Initialize (Runner, Tool_Fixture);
      Quality_Manager.Scheduler.Initialize (Scheduler);
      Quality_Manager.Scheduler.Configure (Scheduler, Store'Unchecked_Access, 1, 1);
      Quality_Manager.Maintenance.Initialize
        (Maintenance_Item, Store'Unchecked_Access, Scheduler'Unchecked_Access,
         Release_Quality, Planner, Runner, 60, 2);
      Quality_Manager.Releases.Qualify_With_Remediation
        (Context, Maintenance_Item, Release_Quality, "missing-release",
         Tool_Fixture, Tool_Fixture, 1, Decision, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "release remediation requires a persisted candidate");
      Approval :=
        (Approval_Id => To_Unbounded_String ("approval-release-remediation"),
         Project => Release_Project,
         Plan_Id => To_Unbounded_String ("PLAN-001"),
         Plan_Revision => 1,
         Content_Digest => To_Unbounded_String
           ("plan-content-sha256-v2:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
         Authorized_Action => To_Unbounded_String ("publish"),
         Policy_Digest => To_Unbounded_String ("policy"),
         Approver => To_Unbounded_String ("quality-manager-test"),
         Created_At => 1,
         Expires_At => 4_102_444_800);
      Quality_Manager.Storage.Records.Save (Store, Approval, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "release remediation has an exact durable approval");
      Quality_Manager.Releases.Create
        (Context, Release_Project, "fixture-commit", "candidate-source", "policy", "toolchain",
         "release-config-remediation", Remediation_Id, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success,
              "failing release candidate is persisted before remediation");
      Quality_Manager.Releases.Qualify_With_Remediation
        (Context, Maintenance_Item, Release_Quality, To_String (Remediation_Id),
         Tool_Fixture, Tool_Fixture, 2, Decision, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success and then Decision.Qualified,
         "release workflow remediates and requalifies an authorized failing candidate: "
         & Quality_Manager.Results.Message (Result) & " ["
         & Quality_Manager.Results.Diagnostic_Strings.To_String (Result.Upstream_Code) & "]");
      Quality_Manager.Storage.Read
        (Store, "release:" & To_String (Remediation_Id), Candidate, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Success
         and then Ada.Strings.Fixed.Index (To_String (Candidate.Payload), """generation"":2") > 0
         and then Ada.Strings.Fixed.Index
           (To_String (Candidate.Payload), """candidate_commit"":""fixture-commit-remediated""") > 0
         and then Ada.Strings.Fixed.Index
           (To_String (Candidate.Payload), """source_digest"":""integrated-source""") > 0,
         "release remediation creates and qualifies an exact new candidate generation");
      Quality_Manager.Scheduler.Shutdown (Scheduler);
      Delete_If_Present (Integrated_Marker);
   end;
   declare
      Blocked_Path    : constant String := "/tmp/quality-manager-release-blocked.database";
      Blocked_Store   : aliased Quality_Manager.Storage.Store;
      Blocked_Release : Quality_Manager.Releases.Context;
      Blocked_Scheduler : aliased Quality_Manager.Scheduler.Scheduler_Type;
      Blocked_Maintenance : Quality_Manager.Maintenance.Context;
      Blocked_Quality : Quality_Manager.Integrations.Quality.Adapter;
      Blocked_Planner : Quality_Manager.Integrations.Improve.Adapter;
      Blocked_Runner  : Quality_Manager.Integrations.Runner.Adapter;
      Blocked_Id      : Unbounded_String;
      Blocked_Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("123e4567-e89b-12d3-a456-426614174000"),
         7, To_Unbounded_String (Release_Fixture));
   begin
      Delete_If_Present (Integrated_Marker);
      if Ada.Directories.Exists (Blocked_Path) then
         Ada.Directories.Delete_File (Blocked_Path);
      end if;
      Quality_Manager.Storage.Open (Blocked_Store, Blocked_Path, True, Result);
      Quality_Manager.Releases.Initialize (Blocked_Release, Blocked_Store'Unchecked_Access);
      Quality_Manager.Integrations.Quality.Initialize
        (Blocked_Quality, Tool_Fixture, "release-remediation-quality.db", Release_Fixture);
      Quality_Manager.Integrations.Improve.Initialize
        (Blocked_Planner, Tool_Fixture, "improve.toml",
         "release-remediation-quality.db", "improve.db");
      Quality_Manager.Integrations.Runner.Initialize (Blocked_Runner, Tool_Fixture);
      Quality_Manager.Scheduler.Initialize (Blocked_Scheduler);
      Quality_Manager.Scheduler.Configure (Blocked_Scheduler, Blocked_Store'Unchecked_Access, 1, 1);
      Quality_Manager.Maintenance.Initialize
        (Blocked_Maintenance, Blocked_Store'Unchecked_Access, Blocked_Scheduler'Unchecked_Access,
         Blocked_Quality, Blocked_Planner, Blocked_Runner, 60, 1);
      Quality_Manager.Releases.Create
        (Blocked_Release, Blocked_Project, "fixture-commit", "candidate-source", "policy", "toolchain",
         "release-config-blocked", Blocked_Id, Result);
      Quality_Manager.Releases.Qualify_With_Remediation
        (Blocked_Release, Blocked_Maintenance, Blocked_Quality, To_String (Blocked_Id),
         Tool_Fixture, Tool_Fixture, 1, Decision, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "release remediation stops when exact authorization is unavailable");
      Quality_Manager.Scheduler.Shutdown (Blocked_Scheduler);
      Quality_Manager.Storage.Close (Blocked_Store, Result);
      if Ada.Directories.Exists (Blocked_Path) then
         Ada.Directories.Delete_File (Blocked_Path);
      end if;
   end;
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Release_Qualification;

