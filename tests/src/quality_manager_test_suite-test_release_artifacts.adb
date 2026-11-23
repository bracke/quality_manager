separate (Quality_Manager_Test_Suite)
procedure Test_Release_Artifacts (Item : in out Fixture) is
   pragma Unreferenced (Item);

   Artifact : constant String := "/tmp/quality-manager-artifact-test.json";
   Private_Key : constant String := "/tmp/quality-manager-artifact-test.key";
   Public_Key : constant String := "/tmp/quality-manager-artifact-test.pub";
   SBOM : constant String := "/tmp/quality-manager-artifact-test.cdx.json";
   Invalid_Manifest : constant String := "/tmp/quality-manager-artifact-invalid.toml";
   Invalid_Key : constant String := "/tmp/quality-manager-artifact-invalid.key";
   Alternate_Key : constant String := "/tmp/quality-manager-artifact-alternate.key";
   Unsigned : constant String := "/tmp/quality-manager-artifact-unsigned.json";
   Large_Key : constant String := "/tmp/quality-manager-artifact-large.key";
   Minimal_Manifest : constant String := "/tmp/quality-manager-artifact-minimal.toml";
   Minimal_SBOM : constant String := "/tmp/quality-manager-artifact-minimal.cdx.json";
   Root_Manifest : constant String :=
     (if Ada.Directories.Exists (Ada.Directories.Current_Directory & "/alire.toml")
      then Ada.Directories.Current_Directory & "/alire.toml"
      else Ada.Directories.Current_Directory & "/../alire.toml");
   Result : Quality_Manager.Results.Operation_Result;

   procedure Delete (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete;

   procedure Cleanup is
   begin
      Delete (Artifact);
      Delete (Artifact & ".sig");
      Delete (Private_Key);
      Delete (Public_Key);
      Delete (SBOM);
      Delete (SBOM & ".sig");
      Delete (Invalid_Manifest);
      Delete (Invalid_Manifest & ".sbom");
      Delete (Invalid_Key);
      Delete (Alternate_Key);
      Delete (Unsigned);
      Delete (Large_Key);
      Delete (Minimal_Manifest);
      Delete (Minimal_SBOM);
   end Cleanup;

   procedure Write (Path, Text : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (File, Text);
      Ada.Text_IO.Close (File);
   end Write;

   function Read (Path : String) return String is
      File : Ada.Text_IO.File_Type;
      Text : Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Text, Ada.Text_IO.Get_Line (File));
         Append (Text, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (File);
      return To_String (Text);
   end Read;

   function Mutate_Field (Text, Marker : String) return String is
      Changed  : String := Text;
      Position : constant Natural := Ada.Strings.Fixed.Index (Text, Marker) + Marker'Length;
   begin
      if Position > Marker'Length and then Position <= Changed'Last then
         Changed (Position) := (if Changed (Position) = '0' then '1' else '0');
      end if;
      return Changed;
   end Mutate_Field;
begin
   Cleanup;
   Write (Artifact, "{""schema_version"":1,""qualified"":true}" & ASCII.LF);
   Quality_Manager.Release_Artifacts.Generate_Keypair (Private_Key, Public_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "release signing keypair is generated");
   Assert
     (Ada.Directories.Exists (Private_Key) and then Ada.Directories.Exists (Public_Key),
      "release signing key files are durable");

   Quality_Manager.Release_Artifacts.Generate_Keypair (Private_Key, Public_Key, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Invalid_Request,
      "release signing keys are never overwritten");

   Quality_Manager.Release_Artifacts.Generate_Keypair (Alternate_Key, Public_Key, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Invalid_Request
      and then not Ada.Directories.Exists (Alternate_Key),
      "a public-key collision removes the partially created private key");

   Write (Invalid_Key, "not-a-key");
   Quality_Manager.Release_Artifacts.Sign (Artifact, Invalid_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "invalid private keys are rejected");
   Write (Invalid_Key, Mutate_Field (Read (Private_Key), "public="));
   Quality_Manager.Release_Artifacts.Sign (Artifact, Invalid_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "inconsistent private keys are rejected");
   Quality_Manager.Release_Artifacts.Sign ("/tmp/no-such-release-artifact", Private_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing release artifacts cannot be signed");
   Write (Large_Key, String'(1 .. 32 * 1_024 => 'x'));
   Quality_Manager.Release_Artifacts.Sign (Artifact, Large_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "oversized private key metadata is rejected");

   Quality_Manager.Release_Artifacts.Sign (Artifact, Private_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "release evidence receives a detached signature");
   Quality_Manager.Release_Artifacts.Verify (Artifact, Public_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "untouched release evidence verifies");

   declare
      Original_Signature : constant String := Read (Artifact & ".sig");
   begin
      Write (Artifact & ".sig", "{}" & ASCII.LF);
      Quality_Manager.Release_Artifacts.Verify (Artifact, Public_Key, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "noncanonical signature metadata is rejected");
      Write
        (Artifact & ".sig",
         Mutate_Field (Original_Signature, """artifact_sha256"":"""));
      declare
         Corrupt : String := Read (Artifact & ".sig");
         Position : constant Natural := Ada.Strings.Fixed.Index
           (Corrupt, """artifact_sha256"":""") + 19;
      begin
         Corrupt (Position) := 'g';
         Write (Artifact & ".sig", Corrupt);
      end;
      Quality_Manager.Release_Artifacts.Verify (Artifact, Public_Key, Result);
      Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "nonhexadecimal digest metadata is rejected");
      Write (Artifact & ".sig", Mutate_Field (Original_Signature, """signature"":"""));
      Quality_Manager.Release_Artifacts.Verify (Artifact, Public_Key, Result);
      Assert
        (Result.Kind = Quality_Manager.Results.Integrity_Error
         and then Quality_Manager.Results.Message (Result) = "artifact signature verification failed",
         "invalid Ed25519 signatures are rejected cryptographically: "
         & Quality_Manager.Results.Message (Result));
      Write (Artifact & ".sig", Original_Signature);
   end;

   Write (Invalid_Key, "format=invalid" & ASCII.LF & "public=00" & ASCII.LF);
   Quality_Manager.Release_Artifacts.Verify (Artifact, Invalid_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "invalid public keys are rejected");
   Write (Unsigned, "{}" & ASCII.LF);
   Quality_Manager.Release_Artifacts.Verify (Unsigned, Public_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing signature sidecars are rejected");

   Delete (Artifact);
   Quality_Manager.Release_Artifacts.Verify (Artifact, Public_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found, "signed metadata cannot stand in for a missing artifact");
   Write (Artifact, "{""schema_version"":1,""qualified"":true}" & ASCII.LF);

   Write (Artifact, "{""schema_version"":1,""qualified"":false}" & ASCII.LF);
   Quality_Manager.Release_Artifacts.Verify (Artifact, Public_Key, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Integrity_Error,
      "a one-byte-equivalent evidence change invalidates its signature");

   Quality_Manager.Release_Artifacts.Generate_SBOM (Root_Manifest, SBOM, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "exact pinned manifest produces an SBOM");
   declare
      Generated : constant String := Read (SBOM);
   begin
      Assert
        (Ada.Strings.Fixed.Index (Generated, """bomFormat"":""CycloneDX""") > 0
         and then Ada.Strings.Fixed.Index (Generated, """config""") > 0
         and then Ada.Strings.Fixed.Index (Generated, """cryptolib""") > 0
         and then Ada.Strings.Fixed.Index (Generated, """database""") > 0
         and then Ada.Strings.Fixed.Index (Generated, """hostkit""") > 0
         and then Ada.Strings.Fixed.Index (Generated, """jsonlib""") > 0
         and then Ada.Strings.Fixed.Index (Generated, """representation""") > 0,
         "SBOM identifies its format and every exact dependency pin");
   end;
   Quality_Manager.Release_Artifacts.Generate_SBOM (Root_Manifest, SBOM, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "SBOM output is never overwritten");
   Quality_Manager.Release_Artifacts.Sign (SBOM, Private_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "SBOM receives a detached signature");
   Quality_Manager.Release_Artifacts.Verify (SBOM, Public_Key, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "signed SBOM verifies independently");

   Write (Invalid_Manifest, "name = ""missing-pins""" & ASCII.LF & "version = ""1.0.0""" & ASCII.LF);
   Quality_Manager.Release_Artifacts.Generate_SBOM (Invalid_Manifest, Invalid_Manifest & ".sbom", Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Invalid_Request,
      "SBOM generation fails closed without exact dependency pins");
   Quality_Manager.Release_Artifacts.Generate_SBOM ("/tmp/no-such-sbom-manifest", Invalid_Manifest & ".sbom", Result);
   Assert (Result.Kind = Quality_Manager.Results.Not_Found, "missing SBOM manifests are rejected");
   Write
     (Minimal_Manifest,
      "name = ""minimal""" & ASCII.LF & "version = ""1.0.0""" & ASCII.LF
      & "[[pins]]" & ASCII.LF
      & "dependency = { url = ""https://github.com/bracke/dependency.git"", "
      & "commit = ""0123456789abcdef0123456789abcdef01234567"" }");
   Quality_Manager.Release_Artifacts.Generate_SBOM (Minimal_Manifest, Minimal_SBOM, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "a final manifest line need not end with a newline");
   Cleanup;
exception
   when others =>
      Cleanup;
      raise;
end Test_Release_Artifacts;
