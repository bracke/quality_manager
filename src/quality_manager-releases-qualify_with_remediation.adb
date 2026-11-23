separate (Quality_Manager.Releases)
procedure Qualify_With_Remediation
  (Item                : in out Context;
   Maintenance_Context : in out Quality_Manager.Maintenance.Context;
   Quality             : Quality_Manager.Integrations.Quality.Adapter;
   Release_Id          : String;
   Alire_Executable    : String;
   Git_Executable      : String;
   Maximum_Cycles      : Positive;
   Decision            : out Qualification_Decision;
   Result              : out Operation_Result) is
   Candidate  : Quality_Manager.Storage.Schema.Release;
   Evidence   : Quality_Manager.Verification.Assessment_Evidence;
   Response   : Quality_Manager.Integrations.JSON_CLI.Response;
   Arguments  : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
   Commit     : Unbounded_String;
   Selector   : Unbounded_String;
   Cycle      : Natural := 0;

   procedure Observe_New_Candidate is
   begin
      Load_Release (Item, Release_Id, Candidate, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Selector := To_Unbounded_String
        (Ada.Strings.Fixed.Trim
           (Positive'Image (Candidate.Project.Quality_Project_Id), Ada.Strings.Both));
      Quality_Manager.Integrations.Quality.Run_Check
        (Quality, To_String (Selector), "release", False, Response);
      Quality_Manager.Verification.Decode_Assessment (Response, Evidence, Result);
      if Result.Kind /= Success then
         return;
      elsif not Evidence.Completed or else not Evidence.Complete
        or else Evidence.Project_Id /= Candidate.Project.Quality_Project_Id
        or else Evidence.Project_Path /= Candidate.Project.Canonical_Path
      then
         Result := Make_Result
           (Stale_Evidence, "remediation did not produce complete candidate evidence",
            "qm.release.remediation-evidence");
         return;
      end if;
      Arguments.Append (To_Unbounded_String ("rev-parse"));
      Arguments.Append (To_Unbounded_String ("HEAD"));
      Execute_Simple
        (Git_Executable, Arguments, To_String (Candidate.Project.Canonical_Path), Commit, Result);
      if Result.Kind /= Success then
         return;
      elsif Commit = Candidate.Candidate_Commit
        or else Evidence.Source_Fingerprint = Candidate.Source_Digest
      then
         Result := Make_Result
           (Authorization_Required,
            "release remediation has not produced a new committed candidate",
            "qm.release.remediation-pending");
         return;
      end if;
      New_Generation
        (Item, Release_Id, To_String (Commit), To_String (Evidence.Source_Fingerprint),
         To_String (Evidence.Policy_Fingerprint), To_String (Evidence.Toolchain_Fingerprint),
         To_String (Candidate.Release_Config), Result);
   end Observe_New_Candidate;
begin
   Decision := (others => <>);
   Qualify_With_Tools
     (Item, Quality, Release_Id, Alire_Executable, Git_Executable, Decision, Result);
   while Result.Kind = Negative_Result and then Cycle < Maximum_Cycles loop
      Cycle := Cycle + 1;
      Load_Release (Item, Release_Id, Candidate, Result);
      exit when Result.Kind /= Success;
      Selector := To_Unbounded_String
        (Ada.Strings.Fixed.Trim
           (Positive'Image (Candidate.Project.Quality_Project_Id), Ada.Strings.Both));
      Quality_Manager.Maintenance.Run_Cycle
        (Maintenance_Context, To_String (Selector), False, Result);
      exit when Result.Kind /= Success;
      Observe_New_Candidate;
      exit when Result.Kind /= Success;
      Qualify_With_Tools
        (Item, Quality, Release_Id, Alire_Executable, Git_Executable, Decision, Result);
   end loop;
   if Result.Kind = Negative_Result and then Cycle = Maximum_Cycles then
      Result := Make_Result
        (Negative_Result, "release remediation budget exhausted", "qm.release.remediation-budget");
   end if;
end Qualify_With_Remediation;
