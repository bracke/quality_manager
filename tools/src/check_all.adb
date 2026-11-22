with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

procedure Check_All is
   use Ada.Strings.Unbounded;

   function Project_Root return String is
      Here : constant String := Ada.Directories.Current_Directory;
   begin
      if Ada.Directories.Exists (Here & "/quality_manager.gpr") then
         return Here;
      elsif Ada.Directories.Exists (Here & "/../quality_manager.gpr") then
         return Ada.Directories.Full_Name (Here & "/..");
      else
         return "";
      end if;
   end Project_Root;

   Root   : constant String := Project_Root;
   Failed : Boolean := False;

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Message);
      Failed := True;
   end Fail;

   procedure Require_File (Relative_Path : String) is
   begin
      if Root = "" or else not Ada.Directories.Exists (Root & "/" & Relative_Path) then
         Fail ("missing required release file: " & Relative_Path);
      end if;
   end Require_File;

   function Read_File (Path : String) return String is
      File    : Ada.Text_IO.File_Type;
      Content : Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Content, Ada.Text_IO.Get_Line (File));
         Append (Content, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (File);
      return To_String (Content);
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return "";
   end Read_File;

   function Value_Of (Text, Name : String) return String is
      Prefix : constant String := Name & "=";
      Start  : Natural := Text'First;
   begin
      while Start <= Text'Last loop
         declare
            Stop : Natural := Start;
         begin
            while Stop <= Text'Last and then Text (Stop) /= ASCII.LF loop
               Stop := Stop + 1;
            end loop;
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

   procedure Check_Coverage is
      Summary : constant String := Read_File (Root & "/coverage/gcov-summary.txt");
      Covered : Natural := 0;
      Total   : Natural := 0;
   begin
      if Value_Of (Summary, "complete") /= "true"
        or else Value_Of (Summary, "inventory") /= "gcov-production-lines-v3"
        or else Value_Of (Summary, "source_fingerprint")'Length /= 16
        or else Value_Of (Summary, "toolchain_fingerprint")'Length /= 16
      then
         Fail ("coverage evidence is incomplete or lacks exact provenance");
         return;
      end if;
      Covered := Natural'Value (Value_Of (Summary, "covered"));
      Total := Natural'Value (Value_Of (Summary, "total"));
      if Total = 0 or else Long_Long_Integer (Covered) * 10_000 < Long_Long_Integer (Total) * 9_000 then
         Fail ("production line coverage is below 90 percent");
      end if;
   exception
      when Constraint_Error =>
         Fail ("coverage evidence contains invalid counts");
   end Check_Coverage;

   Manifest : constant String :=
     (if Root = "" then "" else Read_File (Root & "/alire.release.toml"));
begin
   if Root = "" then
      Fail ("check_all must run from the Quality Manager root or tools directory");
   end if;
   Require_File ("alire.toml");
   Require_File ("alire.release.toml");
   Require_File ("quality_manager.gpr");
   Require_File ("README.md");
   Require_File ("LICENSE");
   Require_File ("tests/alire.toml");
   Require_File ("tests/quality_manager_tests.gpr");
   Require_File ("schemas/approval-decision-v1.schema.json");
   Require_File ("schemas/release-evidence-v1.schema.json");
   Require_File ("docs/release-checklist.md");
   Require_File ("coverage/gcov-summary.txt");
   if Ada.Strings.Fixed.Index (Manifest, "[[pins]]") > 0 then
      Fail ("canonical release manifest contains local path pins");
   end if;
   if Root /= "" and then Ada.Directories.Exists (Root & "/coverage/gcov-summary.txt") then
      Check_Coverage;
   end if;
   if Failed then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Ada.Text_IO.Put_Line ("Quality Manager release checklist passed");
   end if;
end Check_All;
