separate (Quality_Manager.Releases)
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

