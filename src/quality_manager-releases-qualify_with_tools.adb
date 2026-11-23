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
   Assessment, Final_Assessment : Quality_Manager.Verification.Assessment_Evidence;
   Checks     : Check_Results;
   References : Evidence_References;
begin
   Decision := (others => <>);
   Load_Release (Item, Release_Id, Candidate, Result);
   if Result.Kind /= Success then
      return;
   end if;
   References :=
     (Improve_Audit => To_Unbounded_String
        (if Candidate.Generation = 1 then "not-required:no-remediation"
         else "durable:release-remediation:" & Release_Id),
      Native_Audit => To_Unbounded_String
        (if Candidate.Generation = 1 then "not-required:no-agent-execution"
         else "durable:model-runner-attempts:" & Release_Id),
      Regression_Evidence => To_Unbounded_String ("full-release-assessment"),
      Authorization_Audit => To_Unbounded_String
        (if Candidate.Generation = 1 then "not-required:measurement-only"
         else "durable:exact-plan-approval:" & Release_Id));
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
   Quality_Manager.Verification.Establish_Assessment
     (Item.Database.all, Quality,
      (Operation => Qualification_Operation
         (Release_Id, Candidate.Generation, "post-check-assessment"),
       Work_Id => To_Unbounded_String ("release:" & Release_Id & ":post-check"),
       Project => Candidate.Project,
       Project_Selector => To_Unbounded_String
         (Ada.Strings.Fixed.Trim
            (Positive'Image (Candidate.Project.Quality_Project_Id), Ada.Strings.Both)),
       Profile => To_Unbounded_String ("release"),
       Candidate_Source => Candidate.Source_Digest,
       Policy_Fingerprint => Candidate.Policy_Digest,
       Toolchain_Fingerprint => Candidate.Toolchain),
      Final_Assessment, Result);
   if Result.Kind /= Success then
      return;
   elsif not Final_Assessment.Completed or else not Final_Assessment.Complete
     or else Final_Assessment.Source_Fingerprint /= Candidate.Source_Digest
     or else Final_Assessment.Policy_Fingerprint /= Candidate.Policy_Digest
     or else Final_Assessment.Toolchain_Fingerprint /= Candidate.Toolchain
   then
      Result := Make_Result
        (Stale_Evidence,
         "post-check assessment no longer represents the exact release candidate",
         "qm.release.post-check-identity");
      return;
   end if;
   Evaluate (Item, Release_Id, Final_Assessment, Checks, References, Decision, Result);
end Qualify_With_Tools;

