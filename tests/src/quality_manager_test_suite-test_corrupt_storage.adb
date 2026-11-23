separate (Quality_Manager_Test_Suite)
procedure Test_Corrupt_Storage (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Path   : constant String := "/tmp/quality-manager-corrupt.database";
   File   : Ada.Text_IO.File_Type;
   Store  : Quality_Manager.Storage.Store;
   Result : Quality_Manager.Results.Operation_Result;
begin
   if Ada.Directories.Exists (Path) then
      Ada.Directories.Delete_File (Path);
   end if;
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put (File, "not a coordinator database");
   Ada.Text_IO.Close (File);
   Quality_Manager.Storage.Open (Store, Path, True, Result);
   Assert (Result.Kind = Quality_Manager.Results.Integrity_Error, "corrupt database is rejected explicitly");
   Assert (not Quality_Manager.Storage.Is_Open (Store), "corrupt database is not silently repaired");
   Ada.Directories.Delete_File (Path);
exception
   when others =>  --  AQ: audited exception boundary
      if Ada.Text_IO.Is_Open (File) then
         Ada.Text_IO.Close (File);
      end if;
      Quality_Manager.Storage.Close (Store, Result);
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      raise;
end Test_Corrupt_Storage;

