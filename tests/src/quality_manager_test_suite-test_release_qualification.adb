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
      Clean_Build => True, Reproducible_Build => True, AUnit_Passed => True,
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
   end Cleanup;
begin
   Cleanup;
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
         """reproducible_build"":true,""aunit_passed"":true,""proof_applicable"":false," &
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
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Release_Qualification;

