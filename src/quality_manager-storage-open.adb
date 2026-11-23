separate (Quality_Manager.Storage)
procedure Open
  (Item     : in out Store;
   Path     : String;
   Writable : Boolean;
   Result   : out Operation_Result) is
   Exists  : constant Boolean := Ada.Directories.Exists (Path);
   Created : Boolean := False;
   Status  : Database.Status.Result;
   procedure Close_Existing is
   begin
      if Item.Opened then
         Close (Item, Result);
      end if;
   end Close_Existing;

   procedure Ensure_Parent is
      Parent : constant String := Ada.Directories.Containing_Directory (Path);
   begin
      if Result.Kind /= Success then
         return;
      end if;
      if Writable and then not Exists
        and then Parent'Length > 0
        and then not Ada.Directories.Exists (Parent)
      then
         Ada.Directories.Create_Path (Parent);
      end if;
   exception
      when Error : others =>  --  AQ: audited exception boundary
         Result := Make_Result
           (Execution_Error,
            "create coordinator database directory: " & Ada.Exceptions.Exception_Message (Error),
            "qm.storage.create-directory");
   end Ensure_Parent;

   procedure Open_Database is
   begin
      if Result.Kind /= Success then
         return;
      end if;
      if Writable and then Exists then
         Database.Open (Item.DB, Encode (Path));
      elsif Writable then
         Database.Create (Item.DB, Encode (Path));
         Created := Database.Last_Operation_Succeeded (Item.DB);
      elsif Exists then
         Database.Open_Read_Only (Item.DB, Encode (Path));
      else
         Result := Make_Result
           (Not_Found, "coordinator database not found: " & Path, "qm.storage.not-found");
         return;
      end if;
      if not Database.Last_Operation_Succeeded (Item.DB) then
         Result := Database_Failure (Database.Last_Result (Item.DB), "open coordinator database");
      else
         Result := Make_Result (Success);
      end if;
   end Open_Database;

   procedure Load_Schema is
   begin
      if Result.Kind /= Success then
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
      else
         Result := Make_Result (Success);
      end if;
   end Load_Schema;

   procedure Initialize_New_Store is
      Tx         : Database.Transactions.Transaction;
      Metadata   : Stored_Entity;
      Store_UUID : constant String := Decode
        (Database.UUIDs.UUID_To_String (Database.UUIDs.Generate_UUID));
   begin
      if Result.Kind /= Success then
         return;
      end if;
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
      else
         Item.Store_Id := To_Unbounded_String (Store_UUID);
         Item.Next_Id := 2;
         Result := Make_Result (Success);
      end if;
   end Initialize_New_Store;

   function Valid_Metadata
     (Entity : Stored_Entity;
      Prefix : String) return Boolean is
      Payload : constant String := To_String (Entity.Payload);
   begin
      if Entity.Kind /= Metadata_Record then return False;
      elsif To_String (Entity.State) /= Number_Image (Current_Schema_Version) then return False;
      elsif Payload'Length <= Prefix'Length then return False;
      else return Payload (Payload'First .. Payload'First + Prefix'Length - 1) = Prefix;
      end if;
   end Valid_Metadata;

   procedure Load_Existing_Store is
      Tx       : Database.Transactions.Transaction;
      Cursor   : Entity_Tables.Cursor;
      Entity   : Stored_Entity;
      Metadata_Found : Boolean := False;
      Prefix   : constant String := "installation_identity=";
   begin
      if Result.Kind /= Success then
         return;
      end if;
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
               Result := Make_Result
                 (Integrity_Error, "coordinator identity space exhausted", "qm.storage.ids");
               Database.Transactions.Rollback (Tx);
               return;
            end if;
            Item.Next_Id := Entity.Internal_Id + 1;
         end if;
         if To_String (Entity.Entity_Key) = "metadata:schema" then
            Metadata_Found := True;
            if not Valid_Metadata (Entity, Prefix) then
               Result := Make_Result
                 (Incompatible_Contract, "unsupported coordinator schema metadata",
                  "qm.storage.schema");
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
      elsif not Metadata_Found then
         Result := Make_Result
           (Integrity_Error, "coordinator metadata is missing", "qm.storage.metadata");
      elsif Length (Item.Store_Id) = 0 then
         Result := Make_Result
           (Integrity_Error, "coordinator metadata is missing", "qm.storage.metadata");
      else
         Result := Make_Result (Success);
      end if;
   end Load_Existing_Store;
begin
   Result := Make_Result (Success);
   Close_Existing;
   Ensure_Parent;
   Open_Database;
   Load_Schema;
   if Created then
      Initialize_New_Store;
   else
      Load_Existing_Store;
   end if;
exception
   when others =>  --  AQ: audited exception boundary
      if Database.Is_Open (Item.DB) then
         Database.Close (Item.DB);
      end if;
      Item.Opened := False;
      Result := Make_Result (Integrity_Error, "coordinator storage initialization failed", "qm.storage.internal");
end Open;
