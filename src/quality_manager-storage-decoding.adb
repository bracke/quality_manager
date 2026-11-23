with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Quality_Manager.Identities;
with Quality_Manager.Model;

package body Quality_Manager.Storage.Decoding is
   use type Jsonlib.Documents.Value_Kind;
   use type Interfaces.Unsigned_64;
   use type Quality_Manager.Results.Result_Kind;
   use Quality_Manager.Results;

   Empty_Work : constant Quality_Manager.Storage.Schema.Work_Item :=
     (Work_Id => Null_Unbounded_String,
      Global_Remediation => Null_Unbounded_String,
      Project => (Null_Unbounded_String, 1, Null_Unbounded_String),
      Origin => Quality_Manager.Model.Maintenance,
      Finding_Identities => Null_Unbounded_String,
      Priority => 0,
      Baseline_Assessment_Run => 0,
      Improve_Plan_Id => Null_Unbounded_String,
      Improve_Revision => 0,
      Improve_Task_Id => Null_Unbounded_String,
      Improve_Content_SHA256 => Null_Unbounded_String,
      Planned_Source_Fingerprint => Null_Unbounded_String,
      Effective_Policy_Digest => Null_Unbounded_String,
      State => Quality_Manager.Model.Discovered,
      Outcome => Quality_Manager.Model.No_Outcome);

   Empty_Dispatch : constant Quality_Manager.Storage.Schema.Dispatch :=
     (Dispatch_Id => Null_Unbounded_String,
      Work_Id => Null_Unbounded_String,
      Logical_Remediation => Null_Unbounded_String,
      Improve_Task =>
        (Plan_Id => Null_Unbounded_String,
         Revision => 1,
         Task_Id => Null_Unbounded_String),
      Native_Task_Id => Null_Unbounded_String,
      Authorization_Id => Null_Unbounded_String,
      State => Quality_Manager.Model.Published,
      Active => False);

   Empty_Approval : constant Quality_Manager.Storage.Schema.Approval :=
     (Approval_Id => Null_Unbounded_String,
      Project => (Null_Unbounded_String, 1, Null_Unbounded_String),
      Plan_Id => Null_Unbounded_String,
      Plan_Revision => 1,
      Content_Digest => Null_Unbounded_String,
      Authorized_Action => Null_Unbounded_String,
      Policy_Digest => Null_Unbounded_String,
      Approver => Null_Unbounded_String,
      Created_At => 0,
      Expires_At => 0);

   function String_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Unbounded_String) return Boolean is
      Node : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.String_Value
      then
         Value := Null_Unbounded_String;
         return False;
      end if;
      Value := To_Unbounded_String (Document.As_String (Node));
      return True;
   end String_Field;

   function Natural_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Natural) return Boolean is
      Node   : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
      Number : Long_Long_Integer;
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.Integer_Value
      then
         Value := 0;
         return False;
      end if;
      Number := Document.As_Integer (Node);
      if Number not in 0 .. Long_Long_Integer (Natural'Last) then
         Value := 0;
         return False;
      end if;
      Value := Natural (Number);
      return True;
   end Natural_Field;

   function Sequence_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Interfaces.Unsigned_64) return Boolean is
      Node   : constant Jsonlib.Documents.Node := Document.Member (Parent, Name);
      Number : Long_Long_Integer;
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.Integer_Value
      then
         Value := 0;
         return False;
      end if;
      Number := Document.As_Integer (Node);
      if Number < 0 then
         Value := 0;
         return False;
      end if;
      Value := Interfaces.Unsigned_64 (Number);
      return True;
   end Sequence_Field;

   function Project_Field
     (Document : Jsonlib.Documents.Document;
      Parent   : Jsonlib.Documents.Node;
      Value    : out Quality_Manager.Identities.Project_Key) return Boolean is
      Node     : constant Jsonlib.Documents.Node := Document.Member (Parent, "project");
      Database : Unbounded_String;
      Path     : Unbounded_String;
      Id       : Natural;
   begin
      Value := (Null_Unbounded_String, 1, Null_Unbounded_String);
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.Object_Value
        or else not String_Field (Document, Node, "quality_database_id", Database)
        or else not Natural_Field (Document, Node, "quality_project_id", Id)
        or else Id = 0
        or else not String_Field (Document, Node, "canonical_path", Path)
        or else Length (Database) = 0
        or else Length (Path) = 0
      then
         return False;
      end if;
      Value := (Database, Positive (Id), Path);
      return True;
   end Project_Field;

   procedure Parse
     (Text     : String;
      Document : in out Jsonlib.Documents.Document;
      Result   : out Operation_Result) is
      Error : Jsonlib.Errors.Error_Info;
   begin
      Jsonlib.Parsers.Parse
        (Text, Document, Error,
         (Max_Depth => 32, Max_Length => 4 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      Result :=
        (if Jsonlib.Errors.Failed (Error)
         then Make_Result
           (Integrity_Error, "persisted coordinator record is invalid JSON", "qm.storage.decode-json")
         else Make_Result (Success));
   end Parse;

   procedure Read_Work
     (Item    : in out Quality_Manager.Storage.Store;
      Work_Id : String;
      Value   : out Quality_Manager.Storage.Schema.Work_Item;
      Result  : out Operation_Result) is
      Stored   : Quality_Manager.Storage.Stored_Entity;
      Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Origin   : Unbounded_String;
      Outcome  : Unbounded_String;

      procedure Read_String
        (Name     : String;
         Field    : out Unbounded_String;
         Complete : in out Boolean) is
      begin
         if not String_Field (Document, Root, Name, Field) then
            Complete := False;
         end if;
      end Read_String;

      procedure Read_Natural
        (Name     : String;
         Field    : out Natural;
         Complete : in out Boolean) is
      begin
         if not Natural_Field (Document, Root, Name, Field) then
            Complete := False;
         end if;
      end Read_Natural;

      procedure Read_Fields (Complete : out Boolean) is
      begin
         Complete := Project_Field (Document, Root, Value.Project);
         Read_String ("global_remediation", Value.Global_Remediation, Complete);
         if Length (Value.Global_Remediation) = 0 then
            Complete := False;
         end if;
         Read_String ("origin", Origin, Complete);
         Read_String ("findings", Value.Finding_Identities, Complete);
         Read_Natural ("priority", Value.Priority, Complete);
         Read_Natural ("baseline_assessment_run", Value.Baseline_Assessment_Run, Complete);
         Read_String ("plan_id", Value.Improve_Plan_Id, Complete);
         Read_Natural ("plan_revision", Value.Improve_Revision, Complete);
         Read_String ("task_id", Value.Improve_Task_Id, Complete);
         Read_String ("content_sha256", Value.Improve_Content_SHA256, Complete);
         Read_String ("planned_source_fingerprint", Value.Planned_Source_Fingerprint, Complete);
         Read_String ("policy_digest", Value.Effective_Policy_Digest, Complete);
         Read_String ("outcome", Outcome, Complete);
      end Read_Fields;

      Complete : Boolean;
   begin
      Value := Empty_Work;
      Quality_Manager.Storage.Read (Item, Work_Id, Stored, Result);
      if Result.Kind /= Success then
         return;
      elsif Stored.Kind /= Work_Item_Record then
         Result := Make_Result
           (Integrity_Error, "work identity resolves to another record kind", "qm.storage.work-kind");
         return;
      end if;
      Parse (To_String (Stored.Payload), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Root := Document.Root;
      Value.Work_Id := Stored.Entity_Key;
      Read_Fields (Complete);
      if not Complete then
         Result := Make_Result
           (Integrity_Error, "persisted work record is incomplete", "qm.storage.work-fields");
         return;
      end if;
      Value.Origin := Quality_Manager.Model.Workflow_Kind'Value (To_String (Origin));
      Value.State := Quality_Manager.Model.Work_State'Value (To_String (Stored.State));
      Value.Outcome := Quality_Manager.Model.Outcome_Kind'Value (To_String (Outcome));
      Result := Make_Result (Success);
   exception
      when Constraint_Error =>
         Value := Empty_Work;
         Result := Make_Result
           (Incompatible_Contract, "persisted work record has unknown values", "qm.storage.work-values");
      when others =>  --  AQ: audited exception boundary
         Value := Empty_Work;
         Result := Make_Result
           (Integrity_Error, "persisted work record cannot be decoded", "qm.storage.work-decode");
   end Read_Work;

   procedure Read_Active_Dispatch
     (Item                : in out Quality_Manager.Storage.Store;
      Logical_Remediation : String;
      Value               : out Quality_Manager.Storage.Schema.Dispatch;
      Result              : out Operation_Result) is
      Stored   : Quality_Manager.Storage.Stored_Entity;
      Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Revision : Natural;

      procedure Read_String
        (Name     : String;
         Field    : out Unbounded_String;
         Complete : in out Boolean) is
      begin
         if not String_Field (Document, Root, Name, Field) then
            Complete := False;
         end if;
      end Read_String;

      procedure Read_Fields (Complete : out Boolean) is
      begin
         Complete := True;
         Read_String ("dispatch_id", Value.Dispatch_Id, Complete);
         if Length (Value.Dispatch_Id) = 0 then
            Complete := False;
         end if;
         Read_String ("work_id", Value.Work_Id, Complete);
         Read_String ("plan_id", Value.Improve_Task.Plan_Id, Complete);
         if not Natural_Field (Document, Root, "plan_revision", Revision) then
            Complete := False;
         elsif Revision = 0 then
            Complete := False;
         end if;
         Read_String ("improve_task_id", Value.Improve_Task.Task_Id, Complete);
         Read_String ("native_task_id", Value.Native_Task_Id, Complete);
         if Length (Value.Native_Task_Id) = 0 then
            Complete := False;
         end if;
         Read_String ("authorization_id", Value.Authorization_Id, Complete);
      end Read_Fields;

      Complete : Boolean;
   begin
      Value := Empty_Dispatch;
      Quality_Manager.Storage.Read
        (Item, "active-dispatch:" & Logical_Remediation, Stored, Result);
      if Result.Kind /= Success then
         return;
      elsif Stored.Kind /= Dispatch_Record or else Stored.Terminal then
         Result := Make_Result
           (Integrity_Error, "active dispatch identity is inconsistent", "qm.storage.dispatch-kind");
         return;
      end if;
      Parse (To_String (Stored.Payload), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Root := Document.Root;
      Value.Logical_Remediation := To_Unbounded_String (Logical_Remediation);
      Value.Active := True;
      Read_Fields (Complete);
      if not Complete then
         Result := Make_Result
           (Integrity_Error, "persisted active dispatch is incomplete", "qm.storage.dispatch-fields");
         return;
      end if;
      Value.Improve_Task.Revision := Positive (Revision);
      Value.State := Quality_Manager.Model.Work_State'Value (To_String (Stored.State));
      Result := Make_Result (Success);
   exception
      when Constraint_Error =>
         Value := Empty_Dispatch;
         Result := Make_Result
           (Incompatible_Contract, "persisted dispatch has unknown values", "qm.storage.dispatch-values");
      when others =>  --  AQ: audited exception boundary
         Value := Empty_Dispatch;
         Result := Make_Result
           (Integrity_Error, "persisted dispatch cannot be decoded", "qm.storage.dispatch-decode");
   end Read_Active_Dispatch;

   procedure Decode_Approval
     (Stored : Quality_Manager.Storage.Stored_Entity;
      Value  : out Quality_Manager.Storage.Schema.Approval;
      Result : out Operation_Result) is
      Prefix   : constant String := "approval:";
      Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Revision : Natural;
      Key      : constant String := To_String (Stored.Entity_Key);

      procedure Read_String
        (Name     : String;
         Field    : out Unbounded_String;
         Complete : in out Boolean) is
      begin
         if not String_Field (Document, Root, Name, Field) then
            Complete := False;
         elsif Length (Field) = 0 then
            Complete := False;
         end if;
      end Read_String;

      procedure Read_Fields (Complete : out Boolean) is
      begin
         Complete := Project_Field (Document, Root, Value.Project);
         Read_String ("plan_id", Value.Plan_Id, Complete);
         if not Natural_Field (Document, Root, "plan_revision", Revision) then
            Complete := False;
         elsif Revision = 0 then
            Complete := False;
         end if;
         Read_String ("content_digest", Value.Content_Digest, Complete);
         Read_String ("action", Value.Authorized_Action, Complete);
         Read_String ("policy_digest", Value.Policy_Digest, Complete);
         Read_String ("approver", Value.Approver, Complete);
         if not Sequence_Field (Document, Root, "created_at", Value.Created_At) then
            Complete := False;
         end if;
         if not Sequence_Field (Document, Root, "expires_at", Value.Expires_At) then
            Complete := False;
         end if;
      end Read_Fields;

      Complete : Boolean;
   begin
      Value := Empty_Approval;
      if Stored.Kind /= Approval_Record then
         Result := Make_Result
           (Integrity_Error, "approval record identity is inconsistent", "qm.storage.approval-kind");
         return;
      elsif Key'Length <= Prefix'Length then
         Result := Make_Result
           (Integrity_Error, "approval record identity is inconsistent", "qm.storage.approval-kind");
         return;
      elsif Key (Key'First .. Key'First + Prefix'Length - 1) /= Prefix then
         Result := Make_Result
           (Integrity_Error, "approval record identity is inconsistent", "qm.storage.approval-kind");
         return;
      end if;
      Parse (To_String (Stored.Payload), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Root := Document.Root;
      Value.Approval_Id := To_Unbounded_String (Key (Key'First + Prefix'Length .. Key'Last));
      Read_Fields (Complete);
      if not Complete then
         Result := Make_Result
           (Integrity_Error, "persisted approval is incomplete", "qm.storage.approval-fields");
         return;
      end if;
      Value.Plan_Revision := Positive (Revision);
      Result := Make_Result (Success);
   exception
      when Constraint_Error =>
         Value := Empty_Approval;
         Result := Make_Result
           (Incompatible_Contract, "persisted approval has unknown values", "qm.storage.approval-values");
      when others =>  --  AQ: audited exception boundary
         Value := Empty_Approval;
         Result := Make_Result
           (Integrity_Error, "persisted approval cannot be decoded", "qm.storage.approval-decode");
   end Decode_Approval;

   procedure Find_Approval_For_Work
     (Item   : in out Quality_Manager.Storage.Store;
      Work   : Quality_Manager.Storage.Schema.Work_Item;
      Now    : Interfaces.Unsigned_64;
      Value  : out Quality_Manager.Storage.Schema.Approval;
      Result : out Operation_Result) is
      Values  : Quality_Manager.Storage.Entity_Vectors.Vector;
      Decoded : Quality_Manager.Storage.Schema.Approval;
      Found   : Boolean := False;
      Expired : Boolean := False;

      function Matches_Work
        (Approval : Quality_Manager.Storage.Schema.Approval) return Boolean is
      begin
         if not Quality_Manager.Identities.Equal (Approval.Project, Work.Project) then
            return False;
         elsif Approval.Plan_Id /= Work.Improve_Plan_Id then
            return False;
         elsif Natural (Approval.Plan_Revision) /= Work.Improve_Revision then
            return False;
         elsif Approval.Content_Digest /= Work.Improve_Content_SHA256 then
            return False;
         elsif To_String (Approval.Authorized_Action) /= "publish" then
            return False;
         else
            return Approval.Policy_Digest = Work.Effective_Policy_Digest;
         end if;
      end Matches_Work;

      function Is_Expired
        (Approval : Quality_Manager.Storage.Schema.Approval) return Boolean is
      begin
         return Approval.Created_At > Now
           or else (Approval.Expires_At > 0 and then Now > Approval.Expires_At);
      end Is_Expired;
   begin
      Value := Empty_Approval;
      Quality_Manager.Storage.List
        (Item, Approval_Record, Values, 100_000, Result);
      if Result.Kind /= Success then
         return;
      end if;
      for Stored of Values loop
         Decode_Approval (Stored, Decoded, Result);
         if Result.Kind /= Success then
            return;
         end if;
         if Matches_Work (Decoded) then
            if Is_Expired (Decoded) then
               Expired := True;
            elsif not Found
              or else To_String (Decoded.Approval_Id) < To_String (Value.Approval_Id)
            then
               Value := Decoded;
               Found := True;
            end if;
         end if;
      end loop;
      if Found then
         Result := Make_Result (Success);
      elsif Expired then
         Result := Make_Result
           (Authorization_Required, "matching approval is not currently valid", "qm.approval.time");
      else
         Result := Make_Result
           (Not_Found, "no exact durable approval exists for remediation", "qm.approval.not-found");
      end if;
   end Find_Approval_For_Work;
end Quality_Manager.Storage.Decoding;
