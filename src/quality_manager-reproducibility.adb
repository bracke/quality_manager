with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with CryptoLib.Hashes;
with GNAT.OS_Lib;
with Hostkit.FS;
with Hostkit.Regular_Files;
with Quality_Manager.Identities;

package body Quality_Manager.Reproducibility is
   use Quality_Manager.Results;
   use type Ada.Directories.File_Kind;
   use type Ada.Streams.Stream_Element_Offset;
   use type GNAT.OS_Lib.File_Descriptor;

   package Manifests is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);

   function Excluded (Name : String; Include_Artifacts : Boolean) return Boolean is
     (Name in "." | ".." | ".git" | ".codex" | ".agents" | ".aws" | "alire" | "obj" | "var"
      or else (not Include_Artifacts and then Name in "bin" | "lib"));

   function Hex (Value : CryptoLib.Hashes.SHA256_Digest) return String is
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

   function File_Digest (Path : String; Valid : out Boolean) return String is
      File      : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Supported : Boolean;
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Count     : Integer;
      Context   : CryptoLib.Hashes.SHA256_Context;
   begin
      File := Hostkit.Regular_Files.Open_Read (Path, False, Supported);
      Valid := Supported and then File /= GNAT.OS_Lib.Invalid_FD;
      if not Valid then
         return "";
      end if;
      CryptoLib.Hashes.Initialize_SHA256 (Context);
      loop
         Count := GNAT.OS_Lib.Read (File, Buffer'Address, Buffer'Length);
         if Count < 0 then
            GNAT.OS_Lib.Close (File);
            Valid := False;
            return "";
         end if;
         exit when Count = 0;
         CryptoLib.Hashes.Update
           (Context, Buffer (Buffer'First .. Buffer'First
            + Ada.Streams.Stream_Element_Offset (Count) - 1));
      end loop;
      GNAT.OS_Lib.Close (File);
      File := GNAT.OS_Lib.Invalid_FD;
      return Hex (CryptoLib.Hashes.Finalize (Context));
   exception
      when others =>
         if File /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (File);
         end if;
         Valid := False;
         return "";
   end File_Digest;

   procedure Copy_Tree
     (Source    : String;
      Target    : String;
      Result    : out Operation_Result) is
      Search : Ada.Directories.Search_Type;
      Item_Entry : Ada.Directories.Directory_Entry_Type;
   begin
      Ada.Directories.Create_Path (Target);
      Ada.Directories.Start_Search
        (Search, Source, "*", [others => True]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item_Entry);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item_Entry);
            From : constant String := Ada.Directories.Full_Name (Item_Entry);
            To   : constant String := Ada.Directories.Compose (Target, Name);
            Kind : constant Ada.Directories.File_Kind := Ada.Directories.Kind (Item_Entry);
         begin
            if Excluded (Name, False) then
               null;
            elsif Hostkit.FS.Is_Link (From) then
               Result := Make_Result
                 (Invalid_Request, "source tree contains an unsupported symbolic link",
                  "qm.release.workspace-link");
               Ada.Directories.End_Search (Search);
               return;
            elsif Kind = Ada.Directories.Directory then
               Copy_Tree (From, To, Result);
               if Result.Kind /= Success then
                  Ada.Directories.End_Search (Search);
                  return;
               end if;
            elsif Kind = Ada.Directories.Ordinary_File then
               Ada.Directories.Copy_File (From, To);
            else
               Result := Make_Result
                 (Invalid_Request, "source tree contains an unsupported special file",
                  "qm.release.workspace-special");
               Ada.Directories.End_Search (Search);
               return;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      Result := Make_Result (Success);
   end Copy_Tree;

   procedure Prepare_Clean_Workspace
     (Source    : String;
      Workspace : String;
      Result    : out Operation_Result) is
   begin
      if not Ada.Directories.Exists (Source)
        or else Ada.Directories.Kind (Source) /= Ada.Directories.Directory
      then
         Result := Make_Result (Not_Found, "release source directory is unavailable", "qm.release.source");
      elsif Ada.Directories.Exists (Workspace) then
         Result := Make_Result
           (Not_Ready, "clean release workspace already exists", "qm.release.workspace-exists");
      else
         Copy_Tree (Source, Workspace, Result);
      end if;
   exception
      when others =>
         Result := Make_Result
           (Execution_Error, "cannot prepare clean release workspace", "qm.release.workspace-copy");
   end Prepare_Clean_Workspace;

   procedure Manifest
     (Root              : String;
      Include_Artifacts : Boolean;
      Digest            : out Unbounded_String;
      Artifact_Count    : out Natural;
      Result            : out Operation_Result) is
      Items : Manifests.Map;

      procedure Scan (Directory, Relative : String) is
         Search : Ada.Directories.Search_Type;
         Item_Entry : Ada.Directories.Directory_Entry_Type;
      begin
         Ada.Directories.Start_Search (Search, Directory, "*", [others => True]);
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item_Entry);
            declare
               Name : constant String := Ada.Directories.Simple_Name (Item_Entry);
               Path : constant String := Ada.Directories.Full_Name (Item_Entry);
               Key  : constant String := (if Relative = "" then Name else Relative & "/" & Name);
               Kind : constant Ada.Directories.File_Kind := Ada.Directories.Kind (Item_Entry);
               Valid : Boolean;
            begin
               if Excluded (Name, Include_Artifacts) then
                  null;
               elsif Hostkit.FS.Is_Link (Path) then
                  raise Program_Error;
               elsif Kind = Ada.Directories.Directory then
                  Scan (Path, Key);
               elsif Kind = Ada.Directories.Ordinary_File then
                  declare
                     Hash : constant String := File_Digest (Path, Valid);
                  begin
                     if not Valid then
                        raise Program_Error;
                     end if;
                     Items.Insert (Key, Hash);
                     if Include_Artifacts
                       and then (Key = "bin" or else Key = "lib"
                                 or else (Key'Length > 4
                                   and then Key (Key'First .. Key'First + 3) in "bin/" | "lib/"))
                     then
                        Artifact_Count := Artifact_Count + 1;
                     end if;
                  end;
               else
                  raise Program_Error;
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
      end Scan;

      Text : Unbounded_String;
   begin
      Digest := Null_Unbounded_String;
      Artifact_Count := 0;
      Scan (Root, "");
      for Position in Items.Iterate loop
         Append (Text, Manifests.Key (Position) & ASCII.LF);
         Append (Text, Manifests.Element (Position) & ASCII.LF);
      end loop;
      Digest := To_Unbounded_String
        (Quality_Manager.Identities.Canonical_Digest
           ([Quality_Manager.Identities.Text_Value (To_String (Text))]));
      Result := Make_Result (Success);
   exception
      when others =>
         Digest := Null_Unbounded_String;
         Artifact_Count := 0;
         Result := Make_Result
           (Integrity_Error, "cannot create reproducibility manifest", "qm.release.manifest");
   end Manifest;

   procedure Remove_Workspace
     (Workspace : String;
      Result    : out Operation_Result) is
      Prefix : constant String := "/tmp/quality-manager-release-";
   begin
      if Workspace'Length <= Prefix'Length
        or else Workspace (Workspace'First .. Workspace'First + Prefix'Length - 1) /= Prefix
        or else Ada.Strings.Fixed.Index
          (Workspace (Workspace'First + Prefix'Length .. Workspace'Last), "/") > 0
      then
         Result := Make_Result
           (Invalid_Request, "release workspace path is unsafe", "qm.release.workspace-path");
      elsif Ada.Directories.Exists (Workspace) then
         Ada.Directories.Delete_Tree (Workspace);
         Result := Make_Result (Success);
      else
         Result := Make_Result (Success);
      end if;
   exception
      when others =>
         Result := Make_Result
           (Execution_Error, "cannot remove release workspace", "qm.release.workspace-remove");
   end Remove_Workspace;
end Quality_Manager.Reproducibility;
