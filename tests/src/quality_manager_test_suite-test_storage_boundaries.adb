separate (Quality_Manager_Test_Suite)
procedure Test_Storage_Boundaries (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path   : constant String := "/tmp/quality-manager-storage-boundaries.database";
   Store  : Quality_Manager.Storage.Store;
   Result : Quality_Manager.Results.Operation_Result;
   Values : Quality_Manager.Storage.Entity_Vectors.Vector;
   Loaded : Quality_Manager.Storage.Stored_Entity;

   procedure Remove (Name : String) is
   begin
      if Ada.Directories.Exists (Name) then Ada.Directories.Delete_File (Name); end if;
   end Remove;

   procedure Cleanup is
   begin
      Remove (Path);
      Remove (Path & ".wal");
      Remove (Path & ".journal");
      Remove (Path & ".lock");
   end Cleanup;

   function Entity
     (Key : String;
      Kind : Quality_Manager.Storage.Record_Kind := Quality_Manager.Storage.Work_Item_Record)
      return Quality_Manager.Storage.Stored_Entity is
     ((Internal_Id => 1, Kind => Kind, Entity_Key => To_Unbounded_String (Key),
       State => To_Unbounded_String (Quality_Manager.Model.Work_State'Image
         (Quality_Manager.Model.Discovered)),
       Payload => To_Unbounded_String ("boundary"), Terminal => False, Generation => 1));
begin
   Cleanup;
   Quality_Manager.Storage.Open (Store, Path, False, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found, "read-only open rejects a missing database");
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "boundary store created");
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "opening an open store safely reopens it");

   declare
      Invalid : Quality_Manager.Storage.Stored_Entity := Entity ("");
   begin
      Quality_Manager.Storage.Put (Store, Invalid, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty entity key is rejected");
      Invalid := Entity ("generation-zero");
      Invalid.Generation := 0;
      Quality_Manager.Storage.Put (Store, Invalid, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "zero generation is rejected");
      Invalid := Entity ("metadata:external", Quality_Manager.Storage.Metadata_Record);
      Quality_Manager.Storage.Put (Store, Invalid, Result);
      Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
              "external metadata mutation is rejected");
      Invalid := Entity ("event:nonterminal", Quality_Manager.Storage.Event_Record);
      Quality_Manager.Storage.Put (Store, Invalid, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "nonterminal append-only event is rejected");
      Invalid := Entity ("work:unknown-state");
      Invalid.State := To_Unbounded_String ("UNKNOWN");
      Quality_Manager.Storage.Put (Store, Invalid, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "unknown persisted work state is rejected");
      Invalid := Entity ("journal:unknown", Quality_Manager.Storage.Journal_Record);
      Invalid.State := To_Unbounded_String ("UNKNOWN");
      Quality_Manager.Storage.Put (Store, Invalid, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "unknown persisted journal state is rejected");
   end;

   declare
      Work_Value : Quality_Manager.Storage.Schema.Work_Item;
      Dispatch_Value : Quality_Manager.Storage.Schema.Dispatch;
      Approval_Value : Quality_Manager.Storage.Schema.Approval;
      Stored : Quality_Manager.Storage.Stored_Entity :=
        Entity ("work:decode-kind", Quality_Manager.Storage.Project_Record);
      Project : constant Quality_Manager.Identities.Project_Key :=
        (To_Unbounded_String ("database"), 1, To_Unbounded_String ("/project"));
      Approval_Work : constant Quality_Manager.Storage.Schema.Work_Item :=
        (Work_Id => To_Unbounded_String ("work:approval-decode"),
         Global_Remediation => To_Unbounded_String ("remediation:approval-decode"),
         Project => Project, Origin => Quality_Manager.Model.Maintenance,
         Finding_Identities => To_Unbounded_String ("AQ-01"), Priority => 1,
         Baseline_Assessment_Run => 1,
         Improve_Plan_Id => To_Unbounded_String ("PLAN"), Improve_Revision => 1,
         Improve_Task_Id => To_Unbounded_String ("TASK"),
         Improve_Content_SHA256 => To_Unbounded_String ("content"),
         Planned_Source_Fingerprint => To_Unbounded_String ("source"),
         Effective_Policy_Digest => To_Unbounded_String ("policy"),
         State => Quality_Manager.Model.Awaiting_Approval,
         Outcome => Quality_Manager.Model.No_Outcome);
   begin
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Quality_Manager.Storage.Decoding.Read_Work (Store, "work:decode-kind", Work_Value, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "work decoder rejects a conflicting record kind");

      Stored := Entity ("work:decode-json");
      Stored.Payload := To_Unbounded_String ("{");
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Quality_Manager.Storage.Decoding.Read_Work (Store, "work:decode-json", Work_Value, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "work decoder rejects malformed JSON");

      Stored := Entity ("work:decode-fields");
      Stored.Payload := To_Unbounded_String ("{}");
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Quality_Manager.Storage.Decoding.Read_Work (Store, "work:decode-fields", Work_Value, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "work decoder rejects incomplete fields");

      Stored := Entity ("work:decode-values");
      Stored.Payload := To_Unbounded_String
        ("{""global_remediation"":""remediation"",""project"":{" &
         """quality_database_id"":""database"",""quality_project_id"":1," &
         """canonical_path"":""/project""},""origin"":""UNKNOWN""," &
         """findings"":""AQ-01"",""priority"":1,""baseline_assessment_run"":1," &
         """plan_id"":""PLAN"",""plan_revision"":1,""task_id"":""TASK""," &
         """content_sha256"":""content"",""planned_source_fingerprint"":""source""," &
         """policy_digest"":""policy"",""outcome"":""NO_OUTCOME""}");
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Quality_Manager.Storage.Decoding.Read_Work (Store, "work:decode-values", Work_Value, Result);
      Assert (Result.Kind = Quality_Manager.Results.Incompatible_Contract,
              "work decoder rejects unknown enum values");

      Stored := Entity ("active-dispatch:decode-kind", Quality_Manager.Storage.Project_Record);
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Quality_Manager.Storage.Decoding.Read_Active_Dispatch
        (Store, "decode-kind", Dispatch_Value, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "dispatch decoder rejects a conflicting record kind");

      Stored := Entity ("active-dispatch:decode-json", Quality_Manager.Storage.Dispatch_Record);
      Stored.State := To_Unbounded_String (Quality_Manager.Model.Published'Image);
      Stored.Payload := To_Unbounded_String ("{");
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Quality_Manager.Storage.Decoding.Read_Active_Dispatch
        (Store, "decode-json", Dispatch_Value, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "dispatch decoder rejects malformed JSON");

      Stored := Entity ("active-dispatch:decode-fields", Quality_Manager.Storage.Dispatch_Record);
      Stored.State := To_Unbounded_String (Quality_Manager.Model.Published'Image);
      Stored.Payload := To_Unbounded_String ("{}");
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Quality_Manager.Storage.Decoding.Read_Active_Dispatch
        (Store, "decode-fields", Dispatch_Value, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "dispatch decoder rejects incomplete fields");

      Stored := Entity ("approval:decode", Quality_Manager.Storage.Approval_Record);
      Stored.Payload := To_Unbounded_String ("{");
      Quality_Manager.Storage.Put (Store, Stored, Result);
      Quality_Manager.Storage.Decoding.Find_Approval_For_Work
        (Store, Approval_Work, 10, Approval_Value, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "approval lookup rejects malformed durable evidence");
   end;

   Quality_Manager.Storage.Put_Current (Store, Entity ("work:not-current"), Result);
   Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
           "append-only record class cannot use current-record replacement");
   declare
      Current : Quality_Manager.Storage.Stored_Entity :=
        Entity ("project:current-idempotent", Quality_Manager.Storage.Project_Record);
   begin
      Quality_Manager.Storage.Put_Current (Store, Current, Result);
      Quality_Manager.Storage.Read (Store, "project:current-idempotent", Loaded, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Loaded.Generation = 1,
              "new current record starts at generation one");
      Quality_Manager.Storage.Put_Current (Store, Current, Result);
      Quality_Manager.Storage.Read (Store, "project:current-idempotent", Loaded, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Loaded.Generation = 1,
              "idempotent current-record replay does not advance its fencing generation");
      Current.Payload := To_Unbounded_String ("changed");
      Quality_Manager.Storage.Put_Current (Store, Current, Result);
      Quality_Manager.Storage.Read (Store, "project:current-idempotent", Loaded, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Loaded.Generation = 2,
              "changed current-record content advances its generation once");
      Current.Kind := Quality_Manager.Storage.Cycle_Record;
      Quality_Manager.Storage.Put_Current (Store, Current, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "current-record replacement cannot change the durable record kind");
   end;
   Quality_Manager.Storage.Put (Store, Entity ("work:boundary-1"), Result);
   Quality_Manager.Storage.Put (Store, Entity ("work:boundary-2"), Result);
   Quality_Manager.Storage.List
     (Store, Quality_Manager.Storage.Work_Item_Record, Values, 1, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "bounded scans fail on overflow");
   Quality_Manager.Storage.Read (Store, "missing", Loaded, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing entity read is explicit");
   Quality_Manager.Storage.Transition_Work
     (Store, "work:boundary-1", Quality_Manager.Model.Planning, Quality_Manager.Model.Queued,
      "event:boundary", "stale", "", Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "stale transition precondition is rejected");
   declare
      Cycle : Quality_Manager.Storage.Stored_Entity :=
        Entity ("cycle:boundary", Quality_Manager.Storage.Cycle_Record);
      Event : Quality_Manager.Storage.Stored_Entity :=
        Entity ("event:cycle:duplicate", Quality_Manager.Storage.Event_Record);
   begin
      Cycle.State := To_Unbounded_String (Quality_Manager.Model.Queued'Image);
      Quality_Manager.Storage.Put_Current (Store, Cycle, Result);
      Quality_Manager.Storage.Complete_Cycle
        (Store, "cycle:boundary", Quality_Manager.Model.Discovered,
         "event:cycle:stale", "stale", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "cycle completion enforces its state precondition");
      Event.Terminal := True;
      Quality_Manager.Storage.Put (Store, Event, Result);
      Quality_Manager.Storage.Complete_Cycle
        (Store, "cycle:boundary", Quality_Manager.Model.Queued,
         "event:cycle:duplicate", "duplicate", "", Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "duplicate cycle completion event aborts the transaction");
   end;
   Quality_Manager.Storage.Acquire_Lease
     (Store, "boundary", "owner", 1, 1, 10, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "lease generation must increase");
   Quality_Manager.Storage.Acquire_Lease
     (Store, "boundary", "owner", 1, 2, 10, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "new lease requires generation zero");
   declare
      Generation : Interfaces.Unsigned_64 := 0;
      Wrong_Kind : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1,
         Kind => Quality_Manager.Storage.Project_Record,
         Entity_Key => To_Unbounded_String ("lease:wrong-kind"),
         State => To_Unbounded_String ("owner"),
         Payload => To_Unbounded_String ("100"),
         Terminal => False,
         Generation => 1);
      Malformed : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1,
         Kind => Quality_Manager.Storage.Lease_Record,
         Entity_Key => To_Unbounded_String ("lease:malformed"),
         State => To_Unbounded_String ("owner"),
         Payload => To_Unbounded_String ("not-a-time"),
         Terminal => False,
         Generation => 1);
      Exhausted : constant Quality_Manager.Storage.Stored_Entity :=
        (Internal_Id => 1,
         Kind => Quality_Manager.Storage.Lease_Record,
         Entity_Key => To_Unbounded_String ("lease:exhausted"),
         State => To_Unbounded_String ("owner"),
         Payload => To_Unbounded_String ("100"),
         Terminal => False,
         Generation => Interfaces.Unsigned_64 (Interfaces.Integer_64'Last));
   begin
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "", "owner", 10, 20, Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "exclusive lease requires a resource identity");
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "expired", "owner", 20, 20, Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "exclusive lease requires a future expiration");
      Generation := 7;
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "new-with-generation", "owner", 10, 20, Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request and then Generation = 7,
              "new exclusive lease requires generation zero");
      Generation := 0;
      Quality_Manager.Storage.Put (Store, Wrong_Kind, Result);
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "wrong-kind", "owner", 10, 20, Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "exclusive lease rejects a conflicting record kind");
      Quality_Manager.Storage.Release_Lease
        (Store, "wrong-kind", "owner", 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "lease release rejects a conflicting record kind");
      Quality_Manager.Storage.Put (Store, Malformed, Result);
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "malformed", "owner", 10, 20, Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "exclusive lease rejects malformed expiration evidence");
      Quality_Manager.Storage.Put (Store, Exhausted, Result);
      Generation := Interfaces.Unsigned_64 (Interfaces.Integer_64'Last);
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "exhausted", "owner", 10, 20, Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "exclusive lease rejects fencing-generation exhaustion");
      Generation := 0;
      Quality_Manager.Storage.Release_Lease
        (Store, "missing-release", "owner", 1, Result);
      Assert (Result.Kind = Quality_Manager.Results.Not_Found,
              "release of an unknown lease is explicit");
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "renewal", "owner", 10, 20, Generation, Result);
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "renewal", "owner", 11, 30, Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Success and then Generation = 2,
              "the current coordinator renews its own active lease");
      Generation := 1;
      Quality_Manager.Storage.Acquire_Exclusive_Lease
        (Store, "renewal", "owner", 12, 40, Generation, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request and then Generation = 1,
              "an obsolete fencing generation cannot renew an active lease");
   end;
   Quality_Manager.Storage.Advance_Operation
     (Store, 500, Quality_Manager.Journal.Committed, Quality_Manager.Journal.Invoking,
      "external", "", Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "invalid journal transition is rejected before mutation");
   Quality_Manager.Storage.Advance_Operation
     (Store, 500, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
      "external", "", Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found,
           "missing journal operation is explicit");
   Quality_Manager.Storage.Prepare_Operation
     (Store, 501, "boundary", "intent", "external", Result);
   Quality_Manager.Storage.Advance_Operation
     (Store, 501, Quality_Manager.Journal.Invoking, Quality_Manager.Journal.Reconciling,
      "external", "", Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
           "journal advancement enforces its persisted state precondition");

   declare
      Quality : Quality_Manager.Integrations.Quality.Adapter;
      Malformed_Work : Quality_Manager.Storage.Stored_Entity :=
        Entity ("work:recovery-malformed");
      Malformed_Operation : constant Quality_Manager.Identities.Operation_Id :=
        Quality_Manager.Identities.Operation_Identity
          ("maintenance-assessment", "work:recovery-malformed");
   begin
      Quality_Manager.Integrations.Quality.Initialize
        (Quality, "./bin/qm_adapter_fixture", "quality.db");
      Quality_Manager.Recovery.Reconcile_Assessment (Store, Quality, 0, 2, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "assessment recovery requires a nonzero operation identity");

      Quality_Manager.Storage.Put
        (Store, Entity ("journal:600", Quality_Manager.Storage.Project_Record), Result);
      Quality_Manager.Recovery.Reconcile_Assessment (Store, Quality, 600, 2, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "assessment recovery rejects a non-journal operation record");

      Quality_Manager.Storage.Prepare_Operation
        (Store, 601, "assessment", "intent", "assessment:2", Result);
      Quality_Manager.Recovery.Reconcile_Assessment (Store, Quality, 601, 2, Result);
      Assert (Result.Kind = Quality_Manager.Results.Invalid_Request,
              "assessment recovery rejects a journal that was never invoked");

      Quality_Manager.Storage.Prepare_Operation
        (Store, 602, "assessment", "intent", "assessment:2", Result);
      Quality_Manager.Storage.Advance_Operation
        (Store, 602, Quality_Manager.Journal.Prepared, Quality_Manager.Journal.Invoking,
         "assessment:2", "", Result);
      Quality_Manager.Recovery.Reconcile_Assessment (Store, Quality, 602, 2, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "assessment recovery requires exactly one matching work item");

      Malformed_Work.State := To_Unbounded_String (Quality_Manager.Model.Executing'Image);
      Malformed_Work.Payload := To_Unbounded_String ("{");
      Quality_Manager.Storage.Put (Store, Malformed_Work, Result);
      Quality_Manager.Storage.Prepare_Operation
        (Store, Malformed_Operation, "assessment", "intent", "assessment:2", Result);
      Quality_Manager.Storage.Advance_Operation
        (Store, Malformed_Operation, Quality_Manager.Journal.Prepared,
         Quality_Manager.Journal.Invoking, "assessment:2", "", Result);
      Quality_Manager.Recovery.Reconcile_Assessment
        (Store, Quality, Malformed_Operation, 2, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error,
              "assessment recovery rejects malformed qualified project evidence");
   end;

   Quality_Manager.Storage.Close (Store, Result);
   Quality_Manager.Storage.Put (Store, Entity ("work:closed"), Result);
   Assert (Result.Kind = Quality_Manager.Results.Authorization_Required,
           "closed store cannot be mutated");
   Quality_Manager.Storage.Close (Store, Result);
   Cleanup;
exception
   when others =>  --  AQ: audited exception boundary
      Quality_Manager.Storage.Close (Store, Result);
      Cleanup;
      raise;
end Test_Storage_Boundaries;

