with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Database.UUIDs;
with Hostkit.Process;

package body Quality_Manager.Integrations.Processes is
   use type Ada.Directories.File_Size;

   function Capture_Path (Suffix : String) return String is
   begin
      return "/tmp/quality-manager-"
        & Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
            (Database.UUIDs.UUID_To_String (Database.UUIDs.Generate_UUID))
        & Suffix;
   end Capture_Path;

   function Read_Bounded (Path : String; Maximum : Positive) return String is
      package IO renames Ada.Streams.Stream_IO;
      use type IO.Count;
      File : IO.File_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         return "";
      end if;
      IO.Open (File, IO.In_File, Path);
      declare
         Amount : constant Natural := Natural'Min (Natural (IO.Size (File)), Maximum);
      begin
         if Amount = 0 then
            IO.Close (File);
            return "";
         end if;
         declare
            Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Amount));
            Last : Ada.Streams.Stream_Element_Offset;
            Text : String (1 .. Amount);
         begin
            IO.Read (File, Data, Last);
            IO.Close (File);
            for Index in 1 .. Natural (Last) loop
               Text (Index) := Character'Val (Data (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
            return Text (1 .. Natural (Last));
         end;
      end;
   exception
      when others =>  --  AQ: audited exception boundary
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         return "";
   end Read_Bounded;

   procedure Remove (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>  --  AQ: audited exception boundary
         null;
   end Remove;

   procedure Execute (Value : Request; Result : out Execution_Result) is
      Stdout_Path : constant String := Capture_Path (".stdout");
      Stderr_Path : constant String := Capture_Path (".stderr");
      Program     : constant String := Hostkit.Process.Locate (To_String (Value.Executable));
      Env_Program : constant String := Hostkit.Process.Locate ("env");
      Arguments   : String_Vectors.Vector;
      Limit_Hit   : Boolean := False;
      User_Cancel : Boolean := False;

      function Too_Large (Path : String) return Boolean is
        (Ada.Directories.Exists (Path)
         and then Ada.Directories.Size (Path) > Ada.Directories.File_Size (Value.Output_Limit));

      function Should_Cancel return Boolean is
      begin
         Limit_Hit := Too_Large (Stdout_Path) or else Too_Large (Stderr_Path);
         User_Cancel := Value.Cancelled /= null and then Value.Cancelled.all;
         return Limit_Hit or else User_Cancel;
      end Should_Cancel;

      Outcome : Hostkit.Process.Process_Outcome;
      Timeout : constant Natural :=
        (if Value.Timeout_Seconds > Natural'Last / 1_000
         then Natural'Last
         else Value.Timeout_Seconds * 1_000);
   begin
      Result := (others => <>);
      if Program'Length = 0 or else Env_Program'Length = 0 then
         return;
      end if;
      Arguments.Append (To_Unbounded_String ("-i"));
      for Variable of Value.Environment loop
         Arguments.Append (Variable);
      end loop;
      Arguments.Append (To_Unbounded_String (Program));
      for Argument of Value.Arguments loop
         Arguments.Append (Argument);
      end loop;

      Outcome := Hostkit.Process.Run_Captured
        (Program           => Env_Program,
         Arguments         => Arguments,
         Working_Directory => To_String (Value.Working_Directory),
         Stdin_Path        => "/dev/null",
         Stdout_Path       => Stdout_Path,
         Stderr_Path       => Stderr_Path,
         Timeout_Ms        => Timeout,
         Cancelled         => Should_Cancel'Unrestricted_Access,
         Whole_Group       => True);
      Result.Started := Outcome.Started;
      Result.Timed_Out := Outcome.Timed_Out and then not Limit_Hit and then not User_Cancel;
      Result.Cancelled := User_Cancel;
      Result.Output_Exceeded := Limit_Hit or else Too_Large (Stdout_Path) or else Too_Large (Stderr_Path);
      Result.Exit_Status := Outcome.Exit_Status;
      Result.Standard_Output := To_Unbounded_String (Read_Bounded (Stdout_Path, Value.Output_Limit));
      Result.Error_Output := To_Unbounded_String (Read_Bounded (Stderr_Path, Value.Output_Limit));
      Remove (Stdout_Path);
      Remove (Stderr_Path);
   exception
      when others =>  --  AQ: audited exception boundary
         Remove (Stdout_Path);
         Remove (Stderr_Path);
         Result := (others => <>);
   end Execute;
end Quality_Manager.Integrations.Processes;
