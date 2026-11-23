separate (Quality_Manager.Storage)
procedure Acquire_Exclusive_Lease
  (Item         : in out Store;
   Resource_Key : String;
   Owner        : String;
   Now          : Interfaces.Unsigned_64;
   Expires_At   : Interfaces.Unsigned_64;
   Generation   : in out Interfaces.Unsigned_64;
   Result       : out Operation_Result) is
   Tx      : Database.Transactions.Transaction;
   Lease   : Stored_Entity;
   Status  : Database.Status.Result;
   New_Row : Boolean := False;
   Key     : constant String := "lease:" & Resource_Key;
   Requested_Generation : constant Interfaces.Unsigned_64 := Generation;
   procedure Validate_Request is
   begin
      if Resource_Key'Length = 0 then
         Result := Make_Result
           (Invalid_Request, "lease resource and owner are required", "qm.lease.identity");
      elsif Owner'Length = 0 then
         Result := Make_Result
           (Invalid_Request, "lease resource and owner are required", "qm.lease.identity");
      elsif Expires_At <= Now then
         Result := Make_Result
           (Invalid_Request, "lease expiration must be in the future", "qm.lease.expiration");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Request;

   procedure Create_New_Lease is
   begin
      if Requested_Generation /= 0 then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result
           (Invalid_Request, "new lease requires generation zero", "qm.lease.stale");
         return;
      end if;
      Lease :=
        (Internal_Id => Item.Next_Id,
         Kind => Lease_Record,
         Entity_Key => To_Unbounded_String (Key),
         State => To_Unbounded_String (Owner),
         Payload => To_Unbounded_String (Interfaces.Unsigned_64'Image (Expires_At)),
         Terminal => False,
         Generation => 1);
      New_Row := True;
      Status := Entity_Tables.Insert (Tx, Item.DB, Item.Table, Lease);
   end Create_New_Lease;

   procedure Validate_Existing_Lease is
      Previous_Expiration : Interfaces.Unsigned_64;
   begin
      if Lease.Kind /= Lease_Record then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result
           (Integrity_Error, "lease identity has the wrong record kind", "qm.lease.kind");
         return;
      end if;
      Previous_Expiration := Interfaces.Unsigned_64'Value (To_String (Lease.Payload));
      if Previous_Expiration > Now and then To_String (Lease.State) /= Owner then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result
           (Authorization_Required, "another coordinator owns the active lease", "qm.lease.active");
      elsif Previous_Expiration > Now and then Requested_Generation /= Lease.Generation then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result
           (Invalid_Request, "lease generation precondition failed", "qm.lease.stale");
      elsif Lease.Generation = Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) then
         Database.Transactions.Rollback (Tx);
         Result := Make_Result
           (Integrity_Error, "lease generation exhausted", "qm.lease.generation");
      else
         Result := Make_Result (Success);
      end if;
   exception
      when Constraint_Error =>
         Database.Transactions.Rollback (Tx);
         Result := Make_Result
           (Integrity_Error, "lease expiration is malformed", "qm.lease.payload");
   end Validate_Existing_Lease;

   procedure Load_Or_Create is
   begin
      Find_In_Transaction (Item, Tx, Key, Lease, Status);
      if Status.Code = Database.Status.Not_Found then
         Create_New_Lease;
      elsif not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Result := Database_Failure (Status, "read exclusive lease");
      else
         Validate_Existing_Lease;
         if Result.Kind = Success then
            Lease.State := To_Unbounded_String (Owner);
            Lease.Payload := To_Unbounded_String (Interfaces.Unsigned_64'Image (Expires_At));
            Lease.Generation := Lease.Generation + 1;
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Table, Lease);
         end if;
      end if;
   end Load_Or_Create;

   procedure Commit_Lease is
   begin
      if Database.Status.Is_Ok (Status) then
         Status := Database.Transactions.Commit (Tx);
      else
         Database.Transactions.Rollback (Tx);
      end if;
      if Database.Status.Is_Ok (Status) then
         if New_Row then
            Item.Next_Id := Item.Next_Id + 1;
         end if;
         Generation := Lease.Generation;
         Result := Make_Result (Success);
      else
         Result := Database_Failure (Status, "commit exclusive lease");
      end if;
   end Commit_Lease;
begin
   Validate_Request;
   if Result.Kind /= Success then
      return;
   end if;
   Begin_Write (Item, Tx, Result);
   if Result.Kind /= Success then
      return;
   end if;
   Load_Or_Create;
   if Result.Kind = Success then
      Commit_Lease;
   end if;
end Acquire_Exclusive_Lease;

