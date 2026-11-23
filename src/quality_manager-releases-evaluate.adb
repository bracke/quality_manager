separate (Quality_Manager.Releases)
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

   function Assessment_Passes
     (Candidate : Quality_Manager.Storage.Schema.Release) return Boolean is
   begin
      if not Assessment.Completed then return False;
      elsif not Assessment.Complete then return False;
      elsif Assessment.Indicator_Count /= 33 then return False;
      elsif Assessment.Violations /= 0 then return False;
      elsif Assessment.Assessment_Id = 0 then return False;
      elsif Assessment.Project_Id /= Candidate.Project.Quality_Project_Id then return False;
      elsif To_String (Assessment.Project_Path) /= To_String (Candidate.Project.Canonical_Path) then return False;
      elsif To_String (Assessment.Source_Fingerprint) /= To_String (Candidate.Source_Digest) then return False;
      elsif To_String (Assessment.Policy_Fingerprint) /= To_String (Candidate.Policy_Digest) then return False;
      else
         return To_String (Assessment.Toolchain_Fingerprint) = To_String (Candidate.Toolchain);
      end if;
   end Assessment_Passes;

   function Local_Checks_Pass
     (Candidate : Quality_Manager.Storage.Schema.Release) return Boolean is
   begin
      if To_String (Checks.Candidate_Commit) /= To_String (Candidate.Candidate_Commit) then return False;
      elsif To_String (Checks.Source_Fingerprint) /= To_String (Candidate.Source_Digest) then return False;
      elsif To_String (Checks.Release_Config_Digest) /= To_String (Candidate.Release_Config) then return False;
      elsif not Checks.Clean_Build then return False;
      elsif not Checks.Reproducible_Build then return False;
      elsif not Checks.AUnit_Passed then return False;
      elsif Checks.Proof_Applicable and then not Checks.GNATprove_Passed then return False;
      elsif Checks.Coverage_Basis_Points not in 9_000 .. 10_000 then return False;
      else return Checks.Release_Checks_Passed;
      end if;
   end Local_Checks_Pass;
begin
   Decision := (others => <>);
   Load_Release (Item, Release_Id, Candidate, Result);
   if Result.Kind /= Success then return; end if;
   Gate := Assessment_Passes (Candidate) and then Local_Checks_Pass (Candidate);
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

