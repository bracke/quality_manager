with Ada.Directories;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Database.Catalog;
with Database.Predicates;
with Database.Rows;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.UUIDs;
with Database.Values;

with Quality_Manager.Transitions;

package body Quality_Manager.Storage is
   use type Database.Status_Code;
   use type Interfaces.Unsigned_64;
   use type Quality_Manager.Results.Result_Kind;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Quality_Manager.Results;

   Table_Name : constant Wide_Wide_String := "quality_manager_records";

   function Encode (Text : String) return Wide_Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text));

   function Decode (Text : Wide_Wide_String) return String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode (Text));

   function Image (Kind : Record_Kind) return String is
     (Ada.Strings.Fixed.Trim (Record_Kind'Image (Kind), Ada.Strings.Both));

   function Number_Image (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   function To_Row (Item : Stored_Entity) return Database.Rows.Row is
      Row : Database.Rows.Row;
   begin
      if Item.Generation > Interfaces.Unsigned_64 (Long_Long_Integer'Last) then
         raise Constraint_Error with "storage generation exceeds database range";
      end if;
      Database.Rows.Append (Row, Database.Values.From_Integer (Item.Internal_Id));
      Database.Rows.Append (Row, Database.Values.From_Text (Encode (Image (Item.Kind))));
      Database.Rows.Append (Row, Database.Values.From_Text (Encode (To_String (Item.Entity_Key))));
      Database.Rows.Append (Row, Database.Values.From_Text (Encode (To_String (Item.State))));
      Database.Rows.Append (Row, Database.Values.From_Text (Encode (To_String (Item.Payload))));
      Database.Rows.Append (Row, Database.Values.From_Boolean (Item.Terminal));
      Database.Rows.Append
        (Row, Database.Values.From_Long_Integer (Long_Long_Integer (Item.Generation)));
      return Row;
   end To_Row;

   function From_Row (Row : Database.Rows.Row) return Stored_Entity is
   begin
      if Database.Rows.Column_Count (Row) /= 7 then
         raise Ada.IO_Exceptions.Data_Error with "coordinator record has the wrong column count";
      end if;
      return
        (Internal_Id => Positive (Database.Rows.Get (Row, 0).Int),
         Kind        => Record_Kind'Value (Decode (To_Wide_Wide_String (Database.Rows.Get (Row, 1).Text))),
         Entity_Key  => To_Unbounded_String
           (Decode (To_Wide_Wide_String (Database.Rows.Get (Row, 2).Text))),
         State       => To_Unbounded_String
           (Decode (To_Wide_Wide_String (Database.Rows.Get (Row, 3).Text))),
         Payload     => To_Unbounded_String
           (Decode (To_Wide_Wide_String (Database.Rows.Get (Row, 4).Text))),
         Terminal    => Database.Rows.Get (Row, 5).Bool,
         Generation  => Interfaces.Unsigned_64 (Database.Rows.Get (Row, 6).Long_Int));
   exception
      when Constraint_Error =>
         raise Ada.IO_Exceptions.Data_Error with "coordinator record is malformed";
   end From_Row;

   function Key_Of (Item : Stored_Entity) return Positive is (Item.Internal_Id);
   function Key_Value (Key : Positive) return Database.Values.Value is
     (Database.Values.From_Integer (Key));

   package Entity_Tables is new Database.Tables.Typed
     (Stored_Entity, Positive, To_Row, From_Row, Key_Of, Key_Value);

   function New_Schema return Database.Schema.Table_Schema is
      Result : Database.Schema.Table_Schema;
   begin
      Result.Name := To_Unbounded_Wide_Wide_String (Table_Name);
      Database.Schema.Add_Column (Result, "internal_id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (Result, "record_kind", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "entity_key", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "state", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "payload", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "terminal", Database.Types.Boolean_Value, False);
      Database.Schema.Add_Column (Result, "generation", Database.Types.Long_Integer_Value, False);
      return Result;
   end New_Schema;

   function Database_Failure
     (Status  : Database.Status.Result;
      Context : String) return Operation_Result is
      Kind : constant Result_Kind :=
        (case Status.Code is
            when Database.Status.Not_Found => Not_Found,
            when Database.Status.Duplicate_Key | Database.Status.Already_Exists => Integrity_Error,
            when Database.Status.Transaction_Conflict => Temporarily_Unavailable,
            when Database.Status.Invalid_File | Database.Status.Corrupt_File | Database.Status.Corruption_Detected
               | Database.Status.WAL_Corruption | Database.Status.Corrupt_Index => Integrity_Error,
            when others => Execution_Error);
   begin
      return Make_Result
        (Kind,
         Context & ": " & Decode (To_Wide_Wide_String (Status.Message)),
         "qm.storage.database." & Ada.Strings.Fixed.Trim (Database.Status_Code'Image (Status.Code), Ada.Strings.Both));
   end Database_Failure;

   procedure Begin_Read
     (Item   : in out Store;
      Tx     : out Database.Transactions.Transaction;
      Result : out Operation_Result) is
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      if Database.Status.Is_Ok (Database.Transactions.Result (Tx)) then
         Result := Make_Result (Success);
      else
         Result := Database_Failure (Database.Transactions.Result (Tx), "begin read transaction");
      end if;
   end Begin_Read;

   procedure Begin_Write
     (Item   : in out Store;
      Tx     : out Database.Transactions.Transaction;
      Result : out Operation_Result) is
   begin
      if not Item.Writable then
         Result := Make_Result (Authorization_Required, "store is read-only", "qm.storage.read-only");
         return;
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      if Database.Status.Is_Ok (Database.Transactions.Result (Tx)) then
         Result := Make_Result (Success);
      else
         Result := Database_Failure (Database.Transactions.Result (Tx), "begin write transaction");
      end if;
   end Begin_Write;

   function Same (Left, Right : Stored_Entity) return Boolean is
     (Left.Kind = Right.Kind
      and then Left.Entity_Key = Right.Entity_Key
      and then Left.State = Right.State
      and then Left.Payload = Right.Payload
      and then Left.Terminal = Right.Terminal
      and then Left.Generation = Right.Generation);

   function Same_Current_Content (Left, Right : Stored_Entity) return Boolean is
     (Left.Kind = Right.Kind
      and then Left.Entity_Key = Right.Entity_Key
      and then Left.State = Right.State
      and then Left.Payload = Right.Payload
      and then Left.Terminal = Right.Terminal);

   function Validate_Entity (Value : Stored_Entity) return Operation_Result is
   begin
      if Length (Value.Entity_Key) = 0 then
         return Make_Result (Invalid_Request, "entity key must not be empty", "qm.storage.empty-key");
      elsif Value.Generation = 0 then
         return Make_Result (Invalid_Request, "entity generation must be positive", "qm.storage.generation");
      elsif Value.Kind = Metadata_Record then
         return Make_Result
           (Authorization_Required, "schema metadata is managed internally", "qm.storage.metadata-write");
      elsif Value.Kind = Event_Record and then not Value.Terminal then
         return Make_Result (Invalid_Request, "events are append-only terminal records", "qm.event.terminal");
      elsif Value.Kind = Work_Item_Record then
         declare
            State : Quality_Manager.Model.Work_State;
         begin
            begin
               State := Quality_Manager.Model.Work_State'Value (To_String (Value.State));
            exception
               when Constraint_Error =>
                  return Make_Result
                    (Incompatible_Contract, "unknown work state", "qm.transition.unknown-state");
            end;
            if Value.Terminal /= Quality_Manager.Transitions.Is_Terminal (State) then
               return Make_Result
                 (Invalid_Request, "work terminal marker disagrees with state", "qm.transition.terminal-marker");
            end if;
         end;
      elsif Value.Kind = Journal_Record then
         declare
            State : Quality_Manager.Journal.Journal_State;
         begin
            begin
               State := Quality_Manager.Journal.Journal_State'Value (To_String (Value.State));
            exception
               when Constraint_Error =>
                  return Make_Result
                    (Incompatible_Contract, "unknown journal state", "qm.journal.unknown-state");
            end;
            if Value.Terminal /= Quality_Manager.Journal.Is_Terminal (State) then
               return Make_Result
                 (Invalid_Request, "journal terminal marker disagrees with state", "qm.journal.terminal-marker");
            end if;
         end;
      end if;
      return Make_Result (Success);
   end Validate_Entity;

   procedure Find_In_Transaction
     (Item       : in out Store;
      Tx         : in out Database.Transactions.Transaction;
      Entity_Key : String;
      Value      : out Stored_Entity;
      Status     : out Database.Status.Result) is
      Cursor : Entity_Tables.Cursor;
   begin
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Table,
         Database.Predicates.Column_Equals (2, Database.Values.From_Text (Encode (Entity_Key))),
         Cursor);
      if Database.Status.Is_Ok (Status) then
         if Entity_Tables.Has_Element (Cursor) then
            Value := Entity_Tables.Element (Cursor);
         else
            Status := Database.Status.Failure (Database.Status.Not_Found, "entity key not found");
         end if;
      end if;
   end Find_In_Transaction;

   procedure Open
     (Item     : in out Store;
      Path     : String;
      Writable : Boolean;
      Result   : out Operation_Result) is
      Exists  : constant Boolean := Ada.Directories.Exists (Path);
      Created : Boolean := False;
      Status  : Database.Status.Result;
   begin
      if Item.Opened then
         Close (Item, Result);
         if Result.Kind /= Success then
            return;
         end if;
      end if;
      if Writable and then not Exists then
         declare
            Parent : constant String := Ada.Directories.Containing_Directory (Path);
         begin
            if Parent'Length > 0 and then not Ada.Directories.Exists (Parent) then
               Ada.Directories.Create_Path (Parent);
            end if;
         exception
            when Error : others =>
               Result := Make_Result
                 (Execution_Error,
                  "create coordinator database directory: " & Ada.Exceptions.Exception_Message (Error),
                  "qm.storage.create-directory");
               return;
         end;
      end if;
      if Writable then
         if Exists then
            Database.Open (Item.DB, Encode (Path));
         else
            Database.Create (Item.DB, Encode (Path));
            Created := Database.Last_Operation_Succeeded (Item.DB);
         end if;
      elsif Exists then
         Database.Open_Read_Only (Item.DB, Encode (Path));
      else
         Result := Make_Result (Not_Found, "coordinator database not found: " & Path, "qm.storage.not-found");
         return;
      end if;
      if not Database.Last_Operation_Succeeded (Item.DB) then
         Result := Database_Failure (Database.Last_Result (Item.DB), "open coordinator database");
         return;
      end if;

      Item.Opened := True;
      Item.Writable := Writable;
      Item.Table := New_Schema;
      if Created then
         Status := Entity_Tables.Register (Item.DB, Item.Table);
      else
         Status := Database.Catalog.Find_By_Name
           (Database.Catalog_State_Key (Item.DB), Table_Name, Item.Table);
      end if;
      if not Database.Status.Is_Ok (Status) then
         Result := Database_Failure (Status, "load coordinator schema");
         Close (Item, Result);
         return;
      end if;

      if Created then
         declare
            Tx : Database.Transactions.Transaction;
            Metadata : Stored_Entity;
            Store_UUID : constant String := Decode
              (Database.UUIDs.UUID_To_String (Database.UUIDs.Generate_UUID));
         begin
            Begin_Write (Item, Tx, Result);
            if Result.Kind /= Success then
               return;
            end if;
            Status := Entity_Tables.Create_Index
              (Tx, Item.DB, Item.Table, "qm_entity_key", 2, Unique => True);
            if Database.Status.Is_Ok (Status) then
               Status := Entity_Tables.Create_Index
                 (Tx, Item.DB, Item.Table, "qm_record_kind", 1);
            end if;
            if Database.Status.Is_Ok (Status) then
               Status := Entity_Tables.Create_Index
                 (Tx, Item.DB, Item.Table, "qm_record_state", 3);
            end if;
            Metadata :=
              (Internal_Id => 1,
               Kind => Metadata_Record,
               Entity_Key => To_Unbounded_String ("metadata:schema"),
               State => To_Unbounded_String (Number_Image (Current_Schema_Version)),
               Payload => To_Unbounded_String ("installation_identity=" & Store_UUID),
               Terminal => False,
               Generation => 1);
            if Database.Status.Is_Ok (Status) then
               Status := Entity_Tables.Insert (Tx, Item.DB, Item.Table, Metadata);
            end if;
            if Database.Status.Is_Ok (Status) then
               Status := Database.Transactions.Commit (Tx);
            else
               Database.Transactions.Rollback (Tx);
            end if;
            if not Database.Status.Is_Ok (Status) then
               Result := Database_Failure (Status, "initialize coordinator schema");
               return;
            end if;
            Item.Store_Id := To_Unbounded_String (Store_UUID);
            Item.Next_Id := 2;
         end;
      else
         declare
            Tx       : Database.Transactions.Transaction;
            Cursor   : Entity_Tables.Cursor;
            Entity   : Stored_Entity;
            Metadata_Found : Boolean := False;
            Prefix   : constant String := "installation_identity=";
         begin
            Begin_Read (Item, Tx, Result);
            if Result.Kind /= Success then
               return;
            end if;
            Status := Entity_Tables.Scan
              (Tx, Item.DB, Item.Table, Database.Predicates.True_Predicate, Cursor);
            while Database.Status.Is_Ok (Status) and then Entity_Tables.Has_Element (Cursor) loop
               Entity := Entity_Tables.Element (Cursor);
               if Entity.Internal_Id >= Item.Next_Id then
                  if Entity.Internal_Id = Positive'Last then
                     Result := Make_Result (Integrity_Error, "coordinator identity space exhausted", "qm.storage.ids");
                     Database.Transactions.Rollback (Tx);
                     return;
                  end if;
                  Item.Next_Id := Entity.Internal_Id + 1;
               end if;
               if To_String (Entity.Entity_Key) = "metadata:schema" then
                  Metadata_Found := True;
                  if Entity.Kind /= Metadata_Record
                    or else To_String (Entity.State) /= Number_Image (Current_Schema_Version)
                    or else To_String (Entity.Payload)'Length <= Prefix'Length
                    or else To_String (Entity.Payload) (1 .. Prefix'Length) /= Prefix
                  then
                     Result := Make_Result
                       (Incompatible_Contract, "unsupported coordinator schema metadata", "qm.storage.schema");
                     Database.Transactions.Rollback (Tx);
                     return;
                  end if;
                  Item.Store_Id := To_Unbounded_String
                    (To_String (Entity.Payload) (Prefix'Length + 1 .. To_String (Entity.Payload)'Last));
               end if;
               Status := Entity_Tables.Next
                 (Tx, Item.DB, Item.Table, Database.Predicates.True_Predicate, Cursor);
            end loop;
            Database.Transactions.Rollback (Tx);
            if not Database.Status.Is_Ok (Status) then
               Result := Database_Failure (Status, "scan coordinator records");
               return;
            elsif not Metadata_Found or else Length (Item.Store_Id) = 0 then
               Result := Make_Result (Integrity_Error, "coordinator metadata is missing", "qm.storage.metadata");
               return;
            end if;
         end;
      end if;
      Result := Make_Result (Success);
   exception
      when others =>
         if Database.Is_Open (Item.DB) then
            Database.Close (Item.DB);
         end if;
         Item.Opened := False;
         Result := Make_Result (Integrity_Error, "coordinator storage initialization failed", "qm.storage.internal");
   end Open;

   procedure Close (Item : in out Store; Result : out Operation_Result) is
   begin
      if Database.Is_Open (Item.DB) then
         Database.Close (Item.DB);
         if Database.Is_Open (Item.DB) then
            Result := Database_Failure (Database.Last_Result (Item.DB), "close coordinator database");
            return;
         end if;
      end if;
      Item.Opened := False;
      Item.Writable := False;
      Item.Store_Id := Null_Unbounded_String;
      Item.Next_Id := 1;
      Result := Make_Result (Success);
   end Close;

   function Is_Open (Item : Store) return Boolean is (Item.Opened and then Database.Is_Open (Item.DB));
   function Identity (Item : Store) return String is (To_String (Item.Store_Id));

   procedure Put
     (Item   : in out Store;
      Value  : Stored_Entity;
      Result : out Operation_Result) is
      Tx       : Database.Transactions.Transaction;
      Existing : Stored_Entity;
      Status   : Database.Status.Result;
      New_Item : Stored_Entity := Value;
   begin
      Result := Validate_Entity (Value);
      if Result.Kind /= Success then
         return;
      end if;
      Begin_Write (Item, Tx, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Find_In_Transaction (Item, Tx, To_String (Value.Entity_Key), Existing, Status);
      if Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Result :=
           (if Same (Existing, Value)
            then Make_Result (Success)
            else Make_Result (Integrity_Error, "entity key already has different content", "qm.storage.conflict"));
         return;
      elsif Status.Code /= Database.Status.Not_Found then
         Database.Transactions.Rollback (Tx);
         Result := Database_Failure (Status, "check existing coordinator entity");
         return;
      end if;
      New_Item.Internal_Id := Item.Next_Id;
      Status := Entity_Tables.Insert (Tx, Item.DB, Item.Table, New_Item);
      if Database.Status.Is_Ok (Status) then
         Status := Database.Transactions.Commit (Tx);
      else
         Database.Transactions.Rollback (Tx);
      end if;
      if Database.Status.Is_Ok (Status) then
         Item.Next_Id := Item.Next_Id + 1;
         Result := Make_Result (Success);
      else
         Result := Database_Failure (Status, "persist coordinator entity");
      end if;
   exception
      when Constraint_Error =>
         Result := Make_Result (Integrity_Error, "coordinator identity space exhausted", "qm.storage.ids");
   end Put;

   procedure Put_Current
     (Item   : in out Store;
      Value  : Stored_Entity;
      Result : out Operation_Result) is
      Tx       : Database.Transactions.Transaction;
      Existing : Stored_Entity;
      Status   : Database.Status.Result;
      Updated  : Stored_Entity := Value;
      New_Row  : Boolean := False;
   begin
      if Value.Kind not in Project_Record | Campaign_Record | Campaign_Target_Record | Release_Record then
         Result := Make_Result
           (Authorization_Required, "record class is append-only", "qm.storage.current-kind");
         return;
      end if;
      Result := Validate_Entity (Value);
      if Result.Kind /= Success then
         return;
      end if;
      Begin_Write (Item, Tx, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Find_In_Transaction (Item, Tx, To_String (Value.Entity_Key), Existing, Status);
      if Status.Code = Database.Status.Not_Found then
         Updated.Internal_Id := Item.Next_Id;
         New_Row := True;
         Status := Entity_Tables.Insert (Tx, Item.DB, Item.Table, Updated);
      elsif not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Result := Database_Failure (Status, "read current coordinator entity");
         return;
      elsif Existing.Kind /= Value.Kind or else Existing.Terminal then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result (Integrity_Error, "current entity kind mismatch", "qm.storage.current-conflict");
         return;
      elsif Same_Current_Content (Existing, Value) then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result (Success);
         return;
      else
         Updated.Internal_Id := Existing.Internal_Id;
         Updated.Generation := Existing.Generation + 1;
         Status := Entity_Tables.Update (Tx, Item.DB, Item.Table, Updated);
      end if;
      if Database.Status.Is_Ok (Status) then
         Status := Database.Transactions.Commit (Tx);
      else
         Database.Transactions.Rollback (Tx);
      end if;
      if Database.Status.Is_Ok (Status) then
         if New_Row then
            Item.Next_Id := Item.Next_Id + 1;
         end if;
         Result := Make_Result (Success);
      else
         Result := Database_Failure (Status, "persist current coordinator entity");
      end if;
   exception
      when Constraint_Error =>
         Result := Make_Result (Integrity_Error, "coordinator generation exhausted", "qm.storage.generation");
   end Put_Current;

   procedure Read
     (Item       : in out Store;
      Entity_Key : String;
      Value      : out Stored_Entity;
      Result     : out Operation_Result) is
      Tx     : Database.Transactions.Transaction;
      Status : Database.Status.Result;
   begin
      Begin_Read (Item, Tx, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Find_In_Transaction (Item, Tx, Entity_Key, Value, Status);
      Database.Transactions.Rollback (Tx);
      Result :=
        (if Database.Status.Is_Ok (Status)
         then Make_Result (Success)
         else Database_Failure (Status, "read coordinator entity"));
   end Read;

   procedure List
     (Item    : in out Store;
      Kind    : Record_Kind;
      Values  : out Entity_Vectors.Vector;
      Maximum : Positive;
      Result  : out Operation_Result) is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
      Filter : constant Database.Predicates.Predicate :=
        Database.Predicates.Column_Equals
          (1, Database.Values.From_Text (Encode (Image (Kind))));
   begin
      Values.Clear;
      Begin_Read (Item, Tx, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Status := Entity_Tables.Scan (Tx, Item.DB, Item.Table, Filter, Cursor);
      while Database.Status.Is_Ok (Status) and then Entity_Tables.Has_Element (Cursor) loop
         if Natural (Values.Length) = Maximum then
            Database.Transactions.Rollback (Tx);
            Result := Make_Result
              (Integrity_Error, "coordinator record scan limit exceeded", "qm.storage.scan-limit");
            return;
         end if;
         Values.Append (Entity_Tables.Element (Cursor));
         Status := Entity_Tables.Next (Tx, Item.DB, Item.Table, Filter, Cursor);
      end loop;
      Database.Transactions.Rollback (Tx);
      Result :=
        (if Database.Status.Is_Ok (Status)
         then Make_Result (Success)
         else Database_Failure (Status, "scan coordinator records"));
   end List;

   procedure Transition_Work
     (Item           : in out Store;
      Work_Key       : String;
      Expected_State : Quality_Manager.Model.Work_State;
      New_State      : Quality_Manager.Model.Work_State;
      Event_Key      : String;
      Cause          : String;
      Evidence       : String;
      Result         : out Operation_Result) is
      Tx       : Database.Transactions.Transaction;
      Work     : Stored_Entity;
      Existing : Stored_Entity;
      Event    : Stored_Entity;
      Status   : Database.Status.Result;
      Expected : constant String := Quality_Manager.Model.Work_State'Image (Expected_State);
   begin
      Begin_Write (Item, Tx, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Find_In_Transaction (Item, Tx, Work_Key, Work, Status);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Result := Database_Failure (Status, "load work item for transition");
         return;
      elsif Work.Kind /= Work_Item_Record or else To_String (Work.State) /= Expected then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result (Invalid_Request, "work item state precondition failed", "qm.transition.stale");
         return;
      end if;
      Result := Quality_Manager.Transitions.Validate (Expected_State, New_State);
      if Result.Kind /= Success then
         Database.Transactions.Rollback (Tx);
         return;
      end if;
      Find_In_Transaction (Item, Tx, Event_Key, Existing, Status);
      if Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result (Integrity_Error, "event identity already exists", "qm.event.duplicate");
         return;
      elsif Status.Code /= Database.Status.Not_Found then
         Database.Transactions.Rollback (Tx);
         Result := Database_Failure (Status, "check transition event identity");
         return;
      end if;

      Work.State := To_Unbounded_String (Quality_Manager.Model.Work_State'Image (New_State));
      Work.Terminal := Quality_Manager.Transitions.Is_Terminal (New_State);
      Work.Generation := Work.Generation + 1;
      Status := Entity_Tables.Update (Tx, Item.DB, Item.Table, Work);
      Event :=
        (Internal_Id => Item.Next_Id,
         Kind => Event_Record,
         Entity_Key => To_Unbounded_String (Event_Key),
         State => To_Unbounded_String (Expected & "->" & Quality_Manager.Model.Work_State'Image (New_State)),
         Payload => To_Unbounded_String ("cause=" & Cause & ASCII.LF & "evidence=" & Evidence),
         Terminal => True,
         Generation => 1);
      if Database.Status.Is_Ok (Status) then
         Status := Entity_Tables.Insert (Tx, Item.DB, Item.Table, Event);
      end if;
      if Database.Status.Is_Ok (Status) then
         Status := Database.Transactions.Commit (Tx);
      else
         Database.Transactions.Rollback (Tx);
      end if;
      if Database.Status.Is_Ok (Status) then
         Item.Next_Id := Item.Next_Id + 1;
         Result := Make_Result (Success);
      else
         Result := Database_Failure (Status, "commit work transition and event");
      end if;
   end Transition_Work;

   procedure Acquire_Lease
     (Item                : in out Store;
      Resource_Key        : String;
      Owner               : String;
      Expected_Generation : Interfaces.Unsigned_64;
      New_Generation      : Interfaces.Unsigned_64;
      Expires_At          : Interfaces.Unsigned_64;
      Result              : out Operation_Result) is
      Tx       : Database.Transactions.Transaction;
      Lease    : Stored_Entity;
      Status   : Database.Status.Result;
      New_Row  : Boolean := False;
      Key      : constant String := "lease:" & Resource_Key;
   begin
      if New_Generation <= Expected_Generation then
         Result := Make_Result (Invalid_Request, "lease generation must increase", "qm.lease.generation");
         return;
      end if;
      Begin_Write (Item, Tx, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Find_In_Transaction (Item, Tx, Key, Lease, Status);
      if Status.Code = Database.Status.Not_Found then
         if Expected_Generation /= 0 then
            Database.Transactions.Rollback (Tx);
            Result := Make_Result (Invalid_Request, "lease generation precondition failed", "qm.lease.stale");
            return;
         end if;
         Lease :=
           (Internal_Id => Item.Next_Id,
            Kind => Lease_Record,
            Entity_Key => To_Unbounded_String (Key),
            State => To_Unbounded_String (Owner),
            Payload => To_Unbounded_String (Interfaces.Unsigned_64'Image (Expires_At)),
            Terminal => False,
            Generation => New_Generation);
         New_Row := True;
         Status := Entity_Tables.Insert (Tx, Item.DB, Item.Table, Lease);
      elsif not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Result := Database_Failure (Status, "read lease");
         return;
      elsif Lease.Kind /= Lease_Record or else Lease.Generation /= Expected_Generation then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result (Invalid_Request, "lease generation precondition failed", "qm.lease.stale");
         return;
      else
         Lease.State := To_Unbounded_String (Owner);
         Lease.Payload := To_Unbounded_String (Interfaces.Unsigned_64'Image (Expires_At));
         Lease.Generation := New_Generation;
         Status := Entity_Tables.Update (Tx, Item.DB, Item.Table, Lease);
      end if;
      if Database.Status.Is_Ok (Status) then
         Status := Database.Transactions.Commit (Tx);
      else
         Database.Transactions.Rollback (Tx);
      end if;
      if Database.Status.Is_Ok (Status) then
         if New_Row then
            Item.Next_Id := Item.Next_Id + 1;
         end if;
         Result := Make_Result (Success);
      else
         Result := Database_Failure (Status, "commit lease");
      end if;
   end Acquire_Lease;

   function Operation_Key (Operation : Quality_Manager.Identities.Operation_Id) return String is
     ("journal:"
      & Ada.Strings.Fixed.Trim
          (Quality_Manager.Identities.Operation_Id'Image (Operation), Ada.Strings.Both));

   procedure Prepare_Operation
     (Item           : in out Store;
      Operation      : Quality_Manager.Identities.Operation_Id;
      Operation_Kind : String;
      Intent         : String;
      External_Id    : String;
      Result         : out Operation_Result) is
      Record_Item : constant Stored_Entity :=
        (Internal_Id => 1,
         Kind => Journal_Record,
         Entity_Key => To_Unbounded_String (Operation_Key (Operation)),
         State => To_Unbounded_String
           (Quality_Manager.Journal.Journal_State'Image (Quality_Manager.Journal.Prepared)),
         Payload => To_Unbounded_String
           ("kind=" & Operation_Kind & ASCII.LF
            & "intent=" & Intent & ASCII.LF
            & "external_id=" & External_Id),
         Terminal => False,
         Generation => 1);
   begin
      Put (Item, Record_Item, Result);
   end Prepare_Operation;

   procedure Advance_Operation
     (Item           : in out Store;
      Operation      : Quality_Manager.Identities.Operation_Id;
      Expected_State : Quality_Manager.Journal.Journal_State;
      New_State      : Quality_Manager.Journal.Journal_State;
      External_Id    : String;
      Diagnostic     : String;
      Result         : out Operation_Result) is
      Tx     : Database.Transactions.Transaction;
      Record_Item : Stored_Entity;
      Status : Database.Status.Result;
   begin
      if not Quality_Manager.Journal.Allowed (Expected_State, New_State) then
         Result := Make_Result (Invalid_Request, "journal transition is not permitted", "qm.journal.transition");
         return;
      end if;
      Begin_Write (Item, Tx, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Find_In_Transaction (Item, Tx, Operation_Key (Operation), Record_Item, Status);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Result := Database_Failure (Status, "load journal operation");
         return;
      elsif Record_Item.Kind /= Journal_Record
        or else To_String (Record_Item.State) /= Quality_Manager.Journal.Journal_State'Image (Expected_State)
      then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result (Invalid_Request, "journal state precondition failed", "qm.journal.stale");
         return;
      end if;
      Record_Item.State := To_Unbounded_String (Quality_Manager.Journal.Journal_State'Image (New_State));
      Record_Item.Payload := Record_Item.Payload & To_Unbounded_String
        (ASCII.LF & "external_id=" & External_Id & ASCII.LF & "diagnostic=" & Diagnostic);
      Record_Item.Terminal := Quality_Manager.Journal.Is_Terminal (New_State);
      Record_Item.Generation := Record_Item.Generation + 1;
      Status := Entity_Tables.Update (Tx, Item.DB, Item.Table, Record_Item);
      if Database.Status.Is_Ok (Status) then
         Status := Database.Transactions.Commit (Tx);
      else
         Database.Transactions.Rollback (Tx);
      end if;
      Result :=
        (if Database.Status.Is_Ok (Status)
         then Make_Result (Success)
         else Database_Failure (Status, "advance journal operation"));
   end Advance_Operation;

   procedure Recovery_Entries
     (Item    : in out Store;
      Entries : out Entity_Vectors.Vector;
      Maximum : Positive;
      Result  : out Operation_Result) is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
   begin
      Entries.Clear;
      Begin_Read (Item, Tx, Result);
      if Result.Kind /= Success then
         return;
      end if;
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Table,
         Database.Predicates.Column_Equals
           (1, Database.Values.From_Text (Encode (Image (Journal_Record)))),
         Cursor);
      while Database.Status.Is_Ok (Status) and then Entity_Tables.Has_Element (Cursor) loop
         declare
            Record_Item : constant Stored_Entity := Entity_Tables.Element (Cursor);
            State : Quality_Manager.Journal.Journal_State;
         begin
            begin
               State := Quality_Manager.Journal.Journal_State'Value (To_String (Record_Item.State));
            exception
               when Constraint_Error =>
                  Database.Transactions.Rollback (Tx);
                  Result := Make_Result
                    (Incompatible_Contract, "unknown persisted journal state", "qm.journal.state");
                  return;
            end;
            if not Quality_Manager.Journal.Is_Terminal (State) then
               if Natural (Entries.Length) = Maximum then
                  Database.Transactions.Rollback (Tx);
                  Result := Make_Result
                    (Integrity_Error, "journal recovery limit exceeded", "qm.journal.limit");
                  return;
               end if;
               Entries.Append (Record_Item);
            end if;
         end;
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Table,
            Database.Predicates.Column_Equals
              (1, Database.Values.From_Text (Encode (Image (Journal_Record)))),
            Cursor);
      end loop;
      Database.Transactions.Rollback (Tx);
      Result :=
        (if Database.Status.Is_Ok (Status)
         then Make_Result (Success)
         else Database_Failure (Status, "scan journal recovery entries"));
   end Recovery_Entries;

   overriding procedure Finalize (Item : in out Store) is
      Ignored : Operation_Result;
   begin
      Close (Item, Ignored);
   end Finalize;
end Quality_Manager.Storage;
