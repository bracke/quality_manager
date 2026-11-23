separate (Quality_Manager.Verification)
procedure Establish_Assessment
     (Store    : in out Quality_Manager.Storage.Store;
      Quality  : Quality_Manager.Integrations.Quality.Adapter;
      Request  : Assessment_Request;
      Evidence : out Assessment_Evidence;
      Result   : out Operation_Result) is
      Item      : Quality_Manager.Storage.Stored_Entity;
      State     : Quality_Manager.Journal.Journal_State := Quality_Manager.Journal.Prepared;
      Response  : Quality_Manager.Integrations.JSON_CLI.Response;
      Run       : Natural := 0;
      Pending   : constant String := "assessment:pending:" & Number (Request.Operation);
      Intent    : constant String := Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value ("authoritative-assessment-v1"),
          Quality_Manager.Identities.Text_Value (To_String (Request.Work_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Project.Quality_Database_Id)),
          Quality_Manager.Identities.Number_Value
            (Interfaces.Unsigned_64 (Request.Project.Quality_Project_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Project.Canonical_Path)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Project_Selector)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Candidate_Source)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Policy_Fingerprint)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Toolchain_Fingerprint)),
          Quality_Manager.Identities.Text_Value (To_String (Request.Profile))]);

      function Request_Is_Valid return Boolean is
        (Request.Operation /= 0
         and then Length (Request.Work_Id) > 0
         and then Length (Request.Project.Quality_Database_Id) > 0
         and then Length (Request.Project.Canonical_Path) > 0
         and then Length (Request.Project_Selector) > 0
         and then Length (Request.Candidate_Source) > 0
         and then Length (Request.Policy_Fingerprint) > 0
         and then Length (Request.Toolchain_Fingerprint) > 0);

      procedure Prepare_Intent (Failed : out Boolean) is
      begin
         Failed := False;
         Read_Journal (Store, Request.Operation, Item, State, Result);
         if Result.Kind = Success then
            if not Has_Intent (Item, Intent, Pending) then
               Result := Make_Result
                 (Integrity_Error, "assessment operation identity has another intent", "qm.verify.assessment-intent");
               Failed := True;
            end if;
         elsif Result.Kind = Not_Found then
            Quality_Manager.Storage.Prepare_Operation
              (Store, Request.Operation, "authoritative-assessment", Intent, Pending, Result);
            Failed := Result.Kind /= Success;
            State := Quality_Manager.Journal.Prepared;
         else
            Failed := True;
         end if;
      end Prepare_Intent;

      procedure Obtain_Response (Failed : out Boolean) is
      begin
         Failed := False;
         case State is
            when Quality_Manager.Journal.Invoking =>
               Quality_Manager.Storage.Advance_Operation
                 (Store, Request.Operation, State, Quality_Manager.Journal.Needs_Intervention,
                  Pending, "Ada Quality cannot reconcile an interrupted check by operation identity", Result);
               if Result.Kind = Success then
                  Result := Make_Result
                    (Authorization_Required, "interrupted assessment requires explicit reconciliation",
                     "qm.verify.assessment-ambiguous");
               end if;
               Failed := True;
            when Quality_Manager.Journal.Reconciling | Quality_Manager.Journal.Committed =>
               Run := Assessment_External_Id (Item);
               if Run = 0 then
                  Result := Make_Result
                    (Integrity_Error, "assessment journal has no durable run identity", "qm.verify.assessment-run");
                  Failed := True;
               else
                  Quality_Manager.Integrations.Quality.Read_Assessment (Quality, Positive (Run), Response);
               end if;
            when Quality_Manager.Journal.Prepared =>
               Quality_Manager.Storage.Advance_Operation
                 (Store, Request.Operation, State, Quality_Manager.Journal.Invoking, Pending, "", Result);
               if Result.Kind /= Success then
                  Failed := True;
               else
                  State := Quality_Manager.Journal.Invoking;
                  Quality_Manager.Integrations.Quality.Run_Check
                    (Quality, To_String (Request.Project_Selector), To_String (Request.Profile), False, Response);
               end if;
            when others =>
               Result := Make_Result
                 (Authorization_Required,
                  "assessment operation is terminally blocked",
                  "qm.verify.assessment-terminal");
               Failed := True;
         end case;
      end Obtain_Response;

      procedure Commit_Assessment is
         External_Id : constant String := "assessment:" & Ada.Strings.Fixed.Trim
           (Natural'Image (Evidence.Assessment_Id), Ada.Strings.Both);
      begin
         if State = Quality_Manager.Journal.Invoking then
            Quality_Manager.Storage.Advance_Operation
              (Store, Request.Operation, State, Quality_Manager.Journal.Reconciling,
               External_Id, "completed assessment observed", Result);
            if Result.Kind /= Success then
               return;
            end if;
            State := Quality_Manager.Journal.Reconciling;
         end if;
         if State = Quality_Manager.Journal.Reconciling then
            Quality_Manager.Storage.Advance_Operation
              (Store, Request.Operation, State, Quality_Manager.Journal.Committed,
               External_Id, "assessment adopted", Result);
         end if;
      end Commit_Assessment;

      Failed : Boolean;
   begin
      Evidence := (others => <>);
      if not Request_Is_Valid then
         Result := Make_Result
           (Invalid_Request, "assessment request is incomplete", "qm.verify.assessment-request");
         return;
      end if;
      Prepare_Intent (Failed);
      if Failed then
         return;
      end if;
      Obtain_Response (Failed);
      if Failed then
         return;
      end if;

      Decode_Assessment (Response, Evidence, Result);
      if Result.Kind /= Success or else Evidence.Assessment_Id = 0 then
         return;
      end if;
      Commit_Assessment;
   end Establish_Assessment;
