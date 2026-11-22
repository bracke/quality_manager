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
      if not String_Field (Document, Root, "global_remediation", Value.Global_Remediation)
        or else Length (Value.Global_Remediation) = 0
        or else not Project_Field (Document, Root, Value.Project)
        or else not String_Field (Document, Root, "origin", Origin)
        or else not String_Field (Document, Root, "findings", Value.Finding_Identities)
        or else not Natural_Field (Document, Root, "priority", Value.Priority)
        or else not String_Field (Document, Root, "plan_id", Value.Improve_Plan_Id)
        or else not Natural_Field (Document, Root, "plan_revision", Value.Improve_Revision)
        or else not String_Field (Document, Root, "task_id", Value.Improve_Task_Id)
        or else not String_Field (Document, Root, "content_sha256", Value.Improve_Content_SHA256)
        or else not String_Field
          (Document, Root, "planned_source_fingerprint", Value.Planned_Source_Fingerprint)
        or else not String_Field (Document, Root, "policy_digest", Value.Effective_Policy_Digest)
        or else not String_Field (Document, Root, "outcome", Outcome)
      then
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
      when others =>
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
      if not String_Field (Document, Root, "dispatch_id", Value.Dispatch_Id)
        or else Length (Value.Dispatch_Id) = 0
        or else not String_Field (Document, Root, "work_id", Value.Work_Id)
        or else not String_Field (Document, Root, "plan_id", Value.Improve_Task.Plan_Id)
        or else not Natural_Field (Document, Root, "plan_revision", Revision)
        or else Revision = 0
        or else not String_Field (Document, Root, "improve_task_id", Value.Improve_Task.Task_Id)
        or else not String_Field (Document, Root, "native_task_id", Value.Native_Task_Id)
        or else Length (Value.Native_Task_Id) = 0
        or else not String_Field (Document, Root, "authorization_id", Value.Authorization_Id)
      then
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
      when others =>
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
   begin
      Value := Empty_Approval;
      if Stored.Kind /= Approval_Record
        or else Key'Length <= Prefix'Length
        or else Key (Key'First .. Key'First + Prefix'Length - 1) /= Prefix
      then
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
      if not Project_Field (Document, Root, Value.Project)
        or else not String_Field (Document, Root, "plan_id", Value.Plan_Id)
        or else Length (Value.Plan_Id) = 0
        or else not Natural_Field (Document, Root, "plan_revision", Revision)
        or else Revision = 0
        or else not String_Field (Document, Root, "content_digest", Value.Content_Digest)
        or else Length (Value.Content_Digest) = 0
        or else not String_Field (Document, Root, "action", Value.Authorized_Action)
        or else Length (Value.Authorized_Action) = 0
        or else not String_Field (Document, Root, "policy_digest", Value.Policy_Digest)
        or else Length (Value.Policy_Digest) = 0
        or else not String_Field (Document, Root, "approver", Value.Approver)
        or else Length (Value.Approver) = 0
        or else not Sequence_Field (Document, Root, "created_at", Value.Created_At)
        or else not Sequence_Field (Document, Root, "expires_at", Value.Expires_At)
      then
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
      when others =>
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
         if Quality_Manager.Identities.Equal (Decoded.Project, Work.Project)
           and then Decoded.Plan_Id = Work.Improve_Plan_Id
           and then Natural (Decoded.Plan_Revision) = Work.Improve_Revision
           and then Decoded.Content_Digest = Work.Improve_Content_SHA256
           and then To_String (Decoded.Authorized_Action) = "publish"
           and then Decoded.Policy_Digest = Work.Effective_Policy_Digest
         then
            if Decoded.Created_At > Now
              or else (Decoded.Expires_At > 0 and then Now > Decoded.Expires_At)
            then
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
