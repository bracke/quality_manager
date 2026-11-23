separate (Quality_Manager.Releases)
procedure Export_Evidence
  (Item        : in out Context;
   Release_Id  : String;
   Output_Path : String;
   Result      : out Operation_Result) is
   Candidate : Quality_Manager.Storage.Schema.Release;
   Evidence  : Quality_Manager.Storage.Stored_Entity;
   Digest      : Unbounded_String;
   Chunk_Count : Natural := 0;
   Bundle      : Unbounded_String;

   procedure Parse_Envelope is
      Payload       : constant String := To_String (Evidence.Payload);
      Break         : constant Natural := Ada.Strings.Fixed.Index (Payload, ASCII.LF & "");
      Prefix        : constant String := "digest=";
      Chunks_Prefix : constant String := "chunks=";
   begin
      if Break = 0 then
         Result := Make_Result
           (Integrity_Error, "release evidence envelope is corrupt", "qm.release.evidence");
         return;
      elsif Payload'Length <= Prefix'Length then
         Result := Make_Result
           (Integrity_Error, "release evidence envelope is corrupt", "qm.release.evidence");
         return;
      elsif Payload (Payload'First .. Payload'First + Prefix'Length - 1) /= Prefix then
         Result := Make_Result
           (Integrity_Error, "release evidence envelope is corrupt", "qm.release.evidence");
         return;
      end if;
      Digest := To_Unbounded_String (Payload (Payload'First + Prefix'Length .. Break - 1));
      declare
         Declaration : constant String := Payload (Break + 1 .. Payload'Last);
      begin
         if Declaration'Length <= Chunks_Prefix'Length then
            Result := Make_Result
              (Integrity_Error, "release evidence chunk declaration is corrupt", "qm.release.evidence");
            return;
         elsif Declaration
           (Declaration'First .. Declaration'First + Chunks_Prefix'Length - 1) /= Chunks_Prefix
         then
            Result := Make_Result
              (Integrity_Error, "release evidence chunk declaration is corrupt", "qm.release.evidence");
            return;
         end if;
         begin
            Chunk_Count := Natural'Value
              (Declaration (Declaration'First + Chunks_Prefix'Length .. Declaration'Last));
         exception
            when Constraint_Error =>
               Result := Make_Result
                 (Integrity_Error, "release evidence chunk count is invalid", "qm.release.evidence");
               return;
         end;
      end;
      if Chunk_Count = 0 then
         Result := Make_Result
           (Integrity_Error, "release evidence has no chunks", "qm.release.evidence");
      else
         Result := Make_Result (Success);
      end if;
   end Parse_Envelope;

   procedure Read_Chunks is
   begin
      for Chunk in 1 .. Chunk_Count loop
         declare
            Part : Quality_Manager.Storage.Stored_Entity;
         begin
            Quality_Manager.Storage.Read
              (Item.Database.all, Evidence_Chunk_Key (Release_Id, Candidate.Generation, Chunk),
               Part, Result);
            if Result.Kind /= Success then
               Result := Make_Result
                 (Integrity_Error, "release evidence chunk is missing", "qm.release.evidence-chunk");
               return;
            elsif Part.Kind /= Quality_Manager.Storage.Release_Record then
               Result := Make_Result
                 (Integrity_Error, "release evidence chunk is invalid", "qm.release.evidence-chunk");
               return;
            elsif To_String (Part.State) /= "CHUNK" then
               Result := Make_Result
                 (Integrity_Error, "release evidence chunk is invalid", "qm.release.evidence-chunk");
               return;
            elsif not Part.Terminal then
               Result := Make_Result
                 (Integrity_Error, "release evidence chunk is invalid", "qm.release.evidence-chunk");
               return;
            end if;
            Append (Bundle, Part.Payload);
         end;
      end loop;
   end Read_Chunks;

   procedure Verify_And_Write is
      Text   : constant String := To_String (Bundle);
      Actual : constant String := Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value (Text)]);
   begin
      if To_String (Digest) /= Actual then
         Result := Make_Result
           (Integrity_Error, "release evidence digest mismatch", "qm.release.digest");
      else
         Write_File (Output_Path, Text, Result);
      end if;
   end Verify_And_Write;
begin
   Load_Release (Item, Release_Id, Candidate, Result);
   if Result.Kind /= Success then
      return;
   elsif Candidate.State /= Quality_Manager.Model.Verified then
      Result := Make_Result (Not_Ready, "release candidate is not qualified", "qm.release.not-qualified");
      return;
   end if;
   Quality_Manager.Storage.Read
     (Item.Database.all, Evidence_Key (Release_Id, Candidate.Generation), Evidence, Result);
   if Result.Kind /= Success then
      return;
   end if;
   Parse_Envelope;
   if Result.Kind /= Success then
      return;
   end if;
   Read_Chunks;
   if Result.Kind = Success then
      Verify_And_Write;
   end if;
end Export_Evidence;

