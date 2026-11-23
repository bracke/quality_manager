with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with CryptoLib.Ed25519;
with CryptoLib.Errors;
with CryptoLib.Hashes;
with CryptoLib.Random;
with CryptoLib.Secure_Wipe;
with GNAT.OS_Lib;
with Hostkit.Private_Paths;
with Hostkit.Regular_Files;
with Jsonlib.Serializers;
with Quality_Manager.Schemas;

package body Quality_Manager.Release_Artifacts is
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type CryptoLib.Errors.Status;
   use type GNAT.OS_Lib.File_Descriptor;
   use Quality_Manager.Results;

   Private_Format   : constant String := "quality-manager-ed25519-private-v1";
   Public_Format    : constant String := "quality-manager-ed25519-public-v1";
   Signature_Format : constant String := "quality-manager-release-signature-v1";
   Maximum_Metadata_Bytes : constant Positive := 32 * 1_024;
   Maximum_Manifest_Bytes : constant Positive := 1_024 * 1_024;

   subtype Key_Array is Ada.Streams.Stream_Element_Array
     (1 .. Ada.Streams.Stream_Element_Offset (CryptoLib.Ed25519.Public_Key_Length));
   subtype Signature_Array is Ada.Streams.Stream_Element_Array
     (1 .. Ada.Streams.Stream_Element_Offset (CryptoLib.Ed25519.Signature_Length));
   subtype Digest_Array is Ada.Streams.Stream_Element_Array (1 .. 32);

   type Component is record
      Name   : Unbounded_String;
      URL    : Unbounded_String;
      Commit : Unbounded_String;
   end record;

   package Component_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Component);

   function Q (Value : String) return String is
     ('"' & Jsonlib.Serializers.Escape (Value) & '"');

   function Hex (Value : Ada.Streams.Stream_Element_Array) return String is
      Alphabet : constant String := "0123456789abcdef";
      Answer   : String (1 .. Value'Length * 2);
      Position : Positive := Answer'First;
   begin
      for Byte of Value loop
         Answer (Position) := Alphabet (Natural (Byte) / 16 + 1);
         Answer (Position + 1) := Alphabet (Natural (Byte) mod 16 + 1);
         Position := Position + 2;
      end loop;
      return Answer;
   end Hex;

   function Nibble (Value : Character; Valid : in out Boolean)
     return Ada.Streams.Stream_Element is
   begin
      if Value in '0' .. '9' then
         return Ada.Streams.Stream_Element (Character'Pos (Value) - Character'Pos ('0'));
      elsif Value in 'a' .. 'f' then
         return Ada.Streams.Stream_Element (Character'Pos (Value) - Character'Pos ('a') + 10);
      end if;
      Valid := False;
      return 0;
   end Nibble;

   procedure Decode_Hex
     (Text   : String;
      Value  : out Ada.Streams.Stream_Element_Array;
      Valid  : out Boolean) is
      Position : Natural := Text'First;
   begin
      Value := [others => 0];
      Valid := Text'Length = Value'Length * 2;
      if not Valid then
         return;
      end if;
      for Index in Value'Range loop
         declare
            High : constant Ada.Streams.Stream_Element := Nibble (Text (Position), Valid);
            Low  : constant Ada.Streams.Stream_Element := Nibble (Text (Position + 1), Valid);
         begin
            Value (Index) := Ada.Streams.Stream_Element
              (Natural (High) * 16 + Natural (Low));
         end;
         Position := Position + 2;
      end loop;
      if not Valid then
         Value := [others => 0];
      end if;
   end Decode_Hex;

   procedure Remove_Partial (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         null;
   end Remove_Partial;

   function Create_File (Path : String; Private_File : Boolean)
     return GNAT.OS_Lib.File_Descriptor is
      File : GNAT.OS_Lib.File_Descriptor := Hostkit.Regular_Files.Create_New
        (Path, Mode => (if Private_File then 8#600# else 8#644#));
   begin
      if File /= GNAT.OS_Lib.Invalid_FD
        and then Private_File
        and then not Hostkit.Private_Paths.Restrict_Open_File (Integer (File))
      then
         GNAT.OS_Lib.Close (File);
         Remove_Partial (Path);
         File := GNAT.OS_Lib.Invalid_FD;
      end if;
      return File;
   end Create_File;

   function Write_All
     (File : GNAT.OS_Lib.File_Descriptor;
      Text : String) return Boolean is
      Written : Natural := 0;
      Count   : Integer;
   begin
      while Written < Text'Length loop
         Count := GNAT.OS_Lib.Write
           (File, Text (Text'First + Written)'Address, Text'Length - Written);
         if Count <= 0 then
            return False;
         end if;
         Written := Written + Natural (Count);
      end loop;
      return True;
   end Write_All;

   procedure Write_New_File
     (Path         : String;
      Text         : String;
      Private_File : Boolean;
      Result       : out Operation_Result) is
      File : constant GNAT.OS_Lib.File_Descriptor := Create_File (Path, Private_File);
   begin
      if File = GNAT.OS_Lib.Invalid_FD then
         Result := Make_Result
           (Invalid_Request, "output already exists or is unsafe", "qm.artifact.output");
      elsif not Write_All (File, Text) then
         GNAT.OS_Lib.Close (File);
         Remove_Partial (Path);
         Result := Make_Result (Execution_Error, "cannot write output", "qm.artifact.write");
      else
         GNAT.OS_Lib.Close (File);
         Result := Make_Result (Success);
      end if;
   exception
      when others =>
         if File /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (File);
         end if;
         Remove_Partial (Path);
         Result := Make_Result (Execution_Error, "cannot write output", "qm.artifact.write");
   end Write_New_File;

   function Read_Bounded
     (Path       : String;
      Maximum    : Positive;
      Text       : out Unbounded_String) return Boolean is
      File      : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Supported : Boolean;
      Buffer    : String (1 .. 8 * 1_024);
      Count     : Integer;
      Total     : Natural := 0;
   begin
      Text := Null_Unbounded_String;
      File := Hostkit.Regular_Files.Open_Read (Path, False, Supported);
      if not Supported or else File = GNAT.OS_Lib.Invalid_FD then
         return False;
      end if;
      loop
         Count := GNAT.OS_Lib.Read (File, Buffer'Address, Buffer'Length);
         if Count < 0 or else Count > Maximum - Total then
            GNAT.OS_Lib.Close (File);
            Text := Null_Unbounded_String;
            return False;
         end if;
         exit when Count = 0;
         Append (Text, Buffer (1 .. Count));
         Total := Total + Natural (Count);
      end loop;
      GNAT.OS_Lib.Close (File);
      return True;
   exception
      when others =>
         if File /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (File);
         end if;
         Text := Null_Unbounded_String;
         return False;
   end Read_Bounded;

   function Digest_File (Path : String; Digest : out Digest_Array) return Boolean is
      File      : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Supported : Boolean;
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Count     : Integer;
      Context   : CryptoLib.Hashes.SHA256_Context;
      Native    : CryptoLib.Hashes.SHA256_Digest;
   begin
      Digest := [others => 0];
      File := Hostkit.Regular_Files.Open_Read (Path, False, Supported);
      if not Supported or else File = GNAT.OS_Lib.Invalid_FD then
         return False;
      end if;
      CryptoLib.Hashes.Initialize_SHA256 (Context);
      loop
         Count := GNAT.OS_Lib.Read (File, Buffer'Address, Buffer'Length);
         if Count < 0 then
            GNAT.OS_Lib.Close (File);
            return False;
         end if;
         exit when Count = 0;
         CryptoLib.Hashes.Update
           (Context, Buffer (Buffer'First .. Buffer'First
            + Ada.Streams.Stream_Element_Offset (Count) - 1));
      end loop;
      GNAT.OS_Lib.Close (File);
      Native := CryptoLib.Hashes.Finalize (Context);
      for Index in Digest'Range loop
         Digest (Index) := Native (Positive (Index));
      end loop;
      return True;
   exception
      when others =>
         if File /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (File);
         end if;
         Digest := [others => 0];
         return False;
   end Digest_File;

   function Value_Of (Text, Key : String) return String is
      Prefix : constant String := Key & "=";
      Start  : Natural := Text'First;
   begin
      while Start <= Text'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index
              (Text, String'(1 => ASCII.LF), From => Start);
         begin
            if Stop = 0 then
               Stop := Text'Last + 1;
            end if;
            if Stop - Start >= Prefix'Length
              and then Text (Start .. Start + Prefix'Length - 1) = Prefix
            then
               return Text (Start + Prefix'Length .. Stop - 1);
            end if;
            Start := Stop + 1;
         end;
      end loop;
      return "";
   end Value_Of;

   function JSON_Value (Text, Key : String) return String is
      Prefix : constant String := '"' & Key & """:""";
      First  : constant Natural := Ada.Strings.Fixed.Index (Text, Prefix);
      Last   : Natural;
   begin
      if First = 0 then
         return "";
      end if;
      Last := Ada.Strings.Fixed.Index
        (Text, String'(1 => '"'), From => First + Prefix'Length);
      return
        (if Last = 0 then ""
         else Text (First + Prefix'Length .. Last - 1));
   end JSON_Value;

   function Public_Id (Public : Key_Array) return String is
      Native : constant CryptoLib.Hashes.SHA256_Digest := CryptoLib.Hashes.SHA256 (Public);
      Prefix : Digest_Array;
   begin
      for Index in Prefix'Range loop
         Prefix (Index) := Native (Positive (Index));
      end loop;
      return "ed25519-" & Hex (Prefix (1 .. 8));
   end Public_Id;

   function Public_Content (Public : Key_Array) return String is
     ("format=" & Public_Format & ASCII.LF & "public=" & Hex (Public) & ASCII.LF);

   function Signature_Content
     (Key_Id, Digest, Signature : String) return String is
     ("{""schema_version"":1,""kind"":""" & Signature_Format
      & """,""algorithm"":""ed25519-sha256"",""key_id"":""" & Key_Id
      & """,""artifact_sha256"":""" & Digest & """,""signature"":"""
      & Signature & """}" & ASCII.LF);

   procedure Generate_Keypair
     (Private_Key_Path : String;
      Public_Key_Path  : String;
      Result           : out Operation_Result) is
      Random  : CryptoLib.Random.Random_Source;
      Seed    : Key_Array;
      Public  : Key_Array;
      Status  : CryptoLib.Errors.Status;
      Private_File : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Encoded : aliased String (1 .. Key_Array'Length * 2);
   begin
      CryptoLib.Random.Initialize_Production (Random);
      Status := CryptoLib.Ed25519.Generate_Keypair (Random, Seed, Public);
      if Status /= CryptoLib.Errors.Ok then
         Result := Make_Result (Execution_Error, "Ed25519 key generation failed", "qm.artifact.keygen");
         return;
      end if;
      Private_File := Create_File (Private_Key_Path, True);
      if Private_File = GNAT.OS_Lib.Invalid_FD then
         Result := Make_Result
           (Invalid_Request, "private key destination already exists or is unsafe", "qm.artifact.private-key");
         CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
         return;
      end if;
      if not Write_All (Private_File, "format=" & Private_Format & ASCII.LF & "seed=") then
         raise Program_Error;
      end if;
      Encoded := Hex (Seed);
      if not Write_All (Private_File, Encoded) then
         raise Program_Error;
      end if;
      CryptoLib.Secure_Wipe.Wipe (Encoded'Address, Encoded'Length);
      Encoded := Hex (Public);
      if not Write_All (Private_File, ASCII.LF & "public=" & Encoded & ASCII.LF) then
         raise Program_Error;
      end if;
      CryptoLib.Secure_Wipe.Wipe (Encoded'Address, Encoded'Length);
      GNAT.OS_Lib.Close (Private_File);
      Private_File := GNAT.OS_Lib.Invalid_FD;
      Write_New_File (Public_Key_Path, Public_Content (Public), False, Result);
      if Result.Kind /= Success then
         Remove_Partial (Private_Key_Path);
      end if;
      CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
   exception
      when others =>
         CryptoLib.Secure_Wipe.Wipe (Encoded'Address, Encoded'Length);
         CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
         if Private_File /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (Private_File);
         end if;
         Remove_Partial (Private_Key_Path);
         Remove_Partial (Public_Key_Path);
         Result := Make_Result (Execution_Error, "cannot create signing keys", "qm.artifact.keygen");
   end Generate_Keypair;

   procedure Load_Private
     (Path   : String;
      Seed   : out Key_Array;
      Public : out Key_Array;
      Valid  : out Boolean) is
      File      : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Supported : Boolean;
      Content   : aliased String (1 .. Maximum_Metadata_Bytes);
      Last      : Natural := 0;
      Count     : Integer;
      Seed_OK, Public_OK : Boolean;
   begin
      Seed := [others => 0];
      Public := [others => 0];
      File := Hostkit.Regular_Files.Open_Read (Path, False, Supported);
      Valid := Supported and then File /= GNAT.OS_Lib.Invalid_FD;
      while Valid and then Last < Content'Length loop
         Count := GNAT.OS_Lib.Read
           (File, Content (Content'First + Last)'Address, Content'Length - Last);
         Valid := Count >= 0;
         exit when not Valid or else Count = 0;
         Last := Last + Natural (Count);
      end loop;
      if Valid and then Last = Content'Length then
         Count := GNAT.OS_Lib.Read (File, Content'Address, 1);
         Valid := Count = 0;
      end if;
      if File /= GNAT.OS_Lib.Invalid_FD then
         GNAT.OS_Lib.Close (File);
         File := GNAT.OS_Lib.Invalid_FD;
      end if;
      if Valid and then Last > 0 then
         Decode_Hex (Value_Of (Content (1 .. Last), "seed"), Seed, Seed_OK);
         Decode_Hex (Value_Of (Content (1 .. Last), "public"), Public, Public_OK);
         Valid := Seed_OK and then Public_OK
           and then Value_Of (Content (1 .. Last), "format") = Private_Format;
      else
         Valid := False;
      end if;
      if not Valid then
         Seed := [others => 0];
         Public := [others => 0];
      end if;
      CryptoLib.Secure_Wipe.Wipe (Content'Address, Content'Length);
   exception
      when others =>
         if File /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (File);
         end if;
         CryptoLib.Secure_Wipe.Wipe (Content'Address, Content'Length);
         Seed := [others => 0];
         Public := [others => 0];
         Valid := False;
   end Load_Private;

   procedure Sign
     (Artifact_Path    : String;
      Private_Key_Path : String;
      Result           : out Operation_Result) is
      Seed, Public, Derived : Key_Array;
      Digest      : Digest_Array;
      Signature   : Signature_Array;
      Valid       : Boolean;
      Status      : CryptoLib.Errors.Status;
   begin
      Load_Private (Private_Key_Path, Seed, Public, Valid);
      if not Valid then
         Result := Make_Result (Invalid_Request, "invalid private key", "qm.artifact.private-key");
         return;
      end if;
      Status := CryptoLib.Ed25519.Public_Key_From_Seed (Seed, Derived);
      if Status /= CryptoLib.Errors.Ok or else Derived /= Public then
         Result := Make_Result (Integrity_Error, "private key is inconsistent", "qm.artifact.private-key");
      elsif not Digest_File (Artifact_Path, Digest) then
         Result := Make_Result (Not_Found, "artifact is unavailable or unsafe", "qm.artifact.input");
      else
         Status := CryptoLib.Ed25519.Sign (Seed, Public, Digest, Signature);
         if Status /= CryptoLib.Errors.Ok then
            Result := Make_Result (Execution_Error, "Ed25519 signing failed", "qm.artifact.sign");
         else
            Write_New_File
              (Artifact_Path & ".sig",
               Signature_Content (Public_Id (Public), Hex (Digest), Hex (Signature)), False, Result);
         end if;
      end if;
      CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
   exception
      when others =>
         CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
         Result := Make_Result (Execution_Error, "cannot sign artifact", "qm.artifact.sign");
   end Sign;

   procedure Verify
     (Artifact_Path   : String;
      Public_Key_Path : String;
      Result          : out Operation_Result) is
      Public_Text, Signature_Text : Unbounded_String;
      Public    : Key_Array;
      Signature : Signature_Array;
      Recorded, Actual : Digest_Array;
      Public_OK, Signature_OK, Digest_OK : Boolean;
      Key_Id, Digest_Hex, Signature_Hex : Unbounded_String;
      Status : CryptoLib.Errors.Status;
      Contract : Operation_Result;
   begin
      if not Read_Bounded (Public_Key_Path, Maximum_Metadata_Bytes, Public_Text)
        or else Value_Of (To_String (Public_Text), "format") /= Public_Format
      then
         Result := Make_Result (Invalid_Request, "invalid public key", "qm.artifact.public-key");
         return;
      end if;
      Decode_Hex (Value_Of (To_String (Public_Text), "public"), Public, Public_OK);
      if not Public_OK
        or else To_String (Public_Text) /= Public_Content (Public)
        or else not Read_Bounded
          (Artifact_Path & ".sig", Maximum_Metadata_Bytes, Signature_Text)
      then
         Result := Make_Result (Invalid_Request, "invalid key or signature metadata", "qm.artifact.signature");
         return;
      end if;
      Quality_Manager.Schemas.Validate_Versioned_JSON
        (To_String (Signature_Text), 1, Contract, "kind", Signature_Format);
      if Contract.Kind /= Success then
         Result := Make_Result (Integrity_Error, "signature metadata is invalid", "qm.artifact.signature");
         return;
      end if;
      Key_Id := To_Unbounded_String (JSON_Value (To_String (Signature_Text), "key_id"));
      Digest_Hex := To_Unbounded_String (JSON_Value (To_String (Signature_Text), "artifact_sha256"));
      Signature_Hex := To_Unbounded_String (JSON_Value (To_String (Signature_Text), "signature"));
      Decode_Hex (To_String (Digest_Hex), Recorded, Digest_OK);
      Decode_Hex (To_String (Signature_Hex), Signature, Signature_OK);
      if not Digest_OK or else not Signature_OK
        or else To_String (Key_Id) /= Public_Id (Public)
        or else JSON_Value (To_String (Signature_Text), "algorithm") /= "ed25519-sha256"
      then
         Result := Make_Result (Integrity_Error, "signature metadata is invalid", "qm.artifact.signature");
         return;
      elsif not Digest_File (Artifact_Path, Actual) then
         Result := Make_Result (Not_Found, "artifact is unavailable or unsafe", "qm.artifact.input");
         return;
      elsif Actual /= Recorded then
         Result := Make_Result (Integrity_Error, "artifact digest does not match", "qm.artifact.digest");
         return;
      end if;
      Status := CryptoLib.Ed25519.Verify (Public, Signature, Actual);
      Result :=
        (if Status = CryptoLib.Errors.Ok then Make_Result (Success)
         else Make_Result (Integrity_Error, "artifact signature verification failed", "qm.artifact.verify"));
   exception
      when others =>
         Result := Make_Result (Integrity_Error, "cannot verify artifact", "qm.artifact.verify");
   end Verify;

   function TOML_String (Line, Key : String) return String is
      Prefix : constant String := Key & " = """;
      First  : constant Natural := Ada.Strings.Fixed.Index (Line, Prefix);
      Last   : Natural;
   begin
      if First = 0 then
         return "";
      end if;
      Last := Ada.Strings.Fixed.Index
        (Line, String'(1 => '"'), From => First + Prefix'Length);
      return
        (if Last = 0 then ""
         else Line (First + Prefix'Length .. Last - 1));
   end TOML_String;

   function Valid_Commit (Value : String) return Boolean is
     (Value'Length = 40 and then (for all C of Value => C in '0' .. '9' | 'a' .. 'f'));

   procedure Generate_SBOM
     (Manifest_Path : String;
      Output_Path   : String;
      Result        : out Operation_Result) is
      Manifest : Unbounded_String;
      Name, Version : Unbounded_String;
      Components : Component_Vectors.Vector;
      Output : Unbounded_String;
      Start  : Natural;
   begin
      if not Read_Bounded (Manifest_Path, Maximum_Manifest_Bytes, Manifest) then
         Result := Make_Result (Not_Found, "release manifest is unavailable or unsafe", "qm.sbom.manifest");
         return;
      end if;
      Start := To_String (Manifest)'First;
      while Start <= To_String (Manifest)'Last loop
         declare
            Text : constant String := To_String (Manifest);
            Stop : Natural := Ada.Strings.Fixed.Index
              (Text, String'(1 => ASCII.LF), From => Start);
         begin
            if Stop = 0 then
               Stop := Text'Last + 1;
            end if;
            declare
               Line : constant String := Text (Start .. Stop - 1);
               Equal : constant Natural := Ada.Strings.Fixed.Index (Line, " = {");
               URL : constant String := TOML_String (Line, "url");
               Commit : constant String := TOML_String (Line, "commit");
            begin
               if Length (Name) = 0 and then TOML_String (Line, "name") /= "" then
                  Name := To_Unbounded_String (TOML_String (Line, "name"));
               elsif Length (Version) = 0 and then TOML_String (Line, "version") /= "" then
                  Version := To_Unbounded_String (TOML_String (Line, "version"));
               end if;
               if Equal > Line'First and then URL /= "" and then Valid_Commit (Commit)
                 and then URL'Length > 8 and then URL (URL'First .. URL'First + 7) = "https://"
               then
                  Components.Append
                    (Component'
                       (Name => To_Unbounded_String
                       (Ada.Strings.Fixed.Trim (Line (Line'First .. Equal - 1), Ada.Strings.Both)),
                      URL => To_Unbounded_String (URL), Commit => To_Unbounded_String (Commit)));
               end if;
            end;
            Start := Stop + 1;
         end;
      end loop;
      if Length (Name) = 0 or else Length (Version) = 0 or else Components.Is_Empty then
         Result := Make_Result
           (Invalid_Request, "release manifest lacks exact pinned components", "qm.sbom.manifest");
         return;
      end if;
      Append
        (Output, "{""bomFormat"":""CycloneDX"",""specVersion"":""1.6"",""version"":1,"
         & """metadata"":{""component"":{""type"":""application"",""name"":"
         & Q (To_String (Name)) & ",""version"":" & Q (To_String (Version)) & "}},""components"":[");
      for Index in Components.First_Index .. Components.Last_Index loop
         if Index > Components.First_Index then
            Append (Output, ",");
         end if;
         Append
           (Output, "{""type"":""library"",""name"":" & Q (To_String (Components (Index).Name))
            & ",""version"":" & Q (To_String (Components (Index).Commit))
            & ",""externalReferences"":[{""type"":""vcs"",""url"":"
            & Q (To_String (Components (Index).URL)) & "}]}");
      end loop;
      Append (Output, "]}" & ASCII.LF);
      Write_New_File (Output_Path, To_String (Output), False, Result);
   exception
      when others =>
         Result := Make_Result (Invalid_Request, "cannot generate SBOM", "qm.sbom.generate");
   end Generate_SBOM;
end Quality_Manager.Release_Artifacts;
