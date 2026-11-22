with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Quality_Manager.Model;
with Quality_Manager.Storage.Records;
with Quality_Manager.Storage.Schema;

package body Quality_Manager.Approvals is
   use type Jsonlib.Documents.Value_Kind;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_64;
   use type Quality_Manager.Results.Result_Kind;
   use Quality_Manager.Results;

   function Read_File (Path : String; Success : out Boolean) return String is
      package IO renames Ada.Streams.Stream_IO;
      use type IO.Count;
      File : IO.File_Type;
   begin
      IO.Open (File, IO.In_File, Path);
      declare
         Length : constant IO.Count := IO.Size (File);
         Data   : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Length));
         Last   : Ada.Streams.Stream_Element_Offset;
         Text   : String (1 .. Natural (Length));
      begin
         IO.Read (File, Data, Last);
         IO.Close (File);
         if Last /= Data'Last then
            Success := False;
            return "";
         end if;
         for Index in Text'Range loop
            Text (Index) := Character'Val (Data (Ada.Streams.Stream_Element_Offset (Index)));
         end loop;
         Success := True;
         return Text;
      end;
   exception
      when others =>  --  AQ: audited exception boundary
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         Success := False;
         return "";
   end Read_File;

   function String_Field
     (Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Unbounded_String) return Boolean is
      Node : constant Jsonlib.Documents.Node := Document.Member (Root, Name);
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.String_Value
      then
         Value := Null_Unbounded_String;
         return False;
      end if;
      Value := To_Unbounded_String (Document.As_String (Node));
      return Length (Value) > 0;
   end String_Field;

   function Number_Field
     (Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Interfaces.Unsigned_64) return Boolean is
      Node   : constant Jsonlib.Documents.Node := Document.Member (Root, Name);
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
   end Number_Field;

   procedure Apply_Decision
     (Store            : in out Quality_Manager.Storage.Store;
      Definition_Path  : String;
      Expected_Approve : Boolean;
      Result           : out Operation_Result) is
      Read_OK  : Boolean;
      Text     : constant String := Read_File (Definition_Path, Read_OK);
      Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Error    : Jsonlib.Errors.Error_Info;
      Schema, Project_Id, Revision, Created, Expires : Interfaces.Unsigned_64;
      Decision, Approval_Id, Database_Id, Path, Plan_Id, Digest, Action,
        Policy, Approver : Unbounded_String;
      Valid : Boolean;
   begin
      if not Read_OK then
         Result := Make_Result (Not_Found, "cannot read approval decision", "qm.approval.file");
         return;
      end if;
      Jsonlib.Parsers.Parse
        (Text, Document, Error,
         (Max_Depth => 16,
          Max_Length => 1_048_576,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result (Invalid_Request, "invalid approval JSON", "qm.approval.json");
         return;
      end if;
      Root := Document.Root;
      Valid := Document.Kind (Root) = Jsonlib.Documents.Object_Value;
      Valid := Number_Field (Document, Root, "schema_version", Schema) and Valid;
      Valid := (Schema = 1) and Valid;
      Valid := String_Field (Document, Root, "decision", Decision) and Valid;
      Valid := String_Field (Document, Root, "approval_id", Approval_Id) and Valid;
      Valid := String_Field (Document, Root, "quality_database_id", Database_Id) and Valid;
      Valid := Number_Field (Document, Root, "quality_project_id", Project_Id) and Valid;
      Valid := (Project_Id in 1 .. Interfaces.Unsigned_64 (Positive'Last)) and Valid;
      Valid := String_Field (Document, Root, "canonical_path", Path) and Valid;
      Valid := String_Field (Document, Root, "plan_id", Plan_Id) and Valid;
      Valid := Number_Field (Document, Root, "plan_revision", Revision) and Valid;
      Valid := (Revision in 1 .. Interfaces.Unsigned_64 (Positive'Last)) and Valid;
      Valid := String_Field (Document, Root, "content_sha256", Digest) and Valid;
      Valid := String_Field (Document, Root, "authorized_action", Action) and Valid;
      Valid := String_Field (Document, Root, "policy_sha256", Policy) and Valid;
      Valid := String_Field (Document, Root, "approver", Approver) and Valid;
      Valid := Number_Field (Document, Root, "created_at", Created) and Valid;
      Valid := Number_Field (Document, Root, "expires_at", Expires) and Valid;
      if not Valid or else Expires <= Created then
         Result := Make_Result
           (Invalid_Request, "approval decision is incomplete or invalid", "qm.approval.contract");
         return;
      elsif (To_String (Decision) = "approve") /= Expected_Approve
        or else To_String (Decision) not in "approve" | "reject"
      then
         Result := Make_Result
           (Invalid_Request, "approval decision does not match the command", "qm.approval.decision");
         return;
      end if;

      if Expected_Approve then
         Quality_Manager.Storage.Records.Save
           (Store,
            Quality_Manager.Storage.Schema.Approval'
              (Approval_Id       => Approval_Id,
               Project           =>
                 (Quality_Database_Id => Database_Id,
                  Quality_Project_Id  => Positive (Project_Id),
                  Canonical_Path      => Path),
               Plan_Id           => Plan_Id,
               Plan_Revision     => Positive (Revision),
               Content_Digest    => Digest,
               Authorized_Action => Action,
               Policy_Digest     => Policy,
               Approver          => Approver,
               Created_At        => Created,
               Expires_At        => Expires),
            Result);
      else
         Quality_Manager.Storage.Put
           (Store,
            (Internal_Id => 1,
             Kind        => Quality_Manager.Storage.Event_Record,
             Entity_Key  => To_Unbounded_String ("approval-rejection:" & To_String (Approval_Id)),
             State       => To_Unbounded_String (Quality_Manager.Model.Cancelled'Image),
             Payload     => To_Unbounded_String
               ("plan_id=" & To_String (Plan_Id) & ASCII.LF
                & "plan_revision=" & Positive'Image (Positive (Revision)) & ASCII.LF
                & "content_sha256=" & To_String (Digest) & ASCII.LF
                & "policy_sha256=" & To_String (Policy) & ASCII.LF
                & "approver=" & To_String (Approver)),
             Terminal    => True,
             Generation  => 1),
            Result);
      end if;
   exception
      when Constraint_Error =>
         Result := Make_Result
           (Invalid_Request, "approval decision contains an out-of-range value", "qm.approval.range");
   end Apply_Decision;
end Quality_Manager.Approvals;
