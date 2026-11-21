with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;

with Config.Formats;
with Config.Parsers;
with Config.Reader;
with Config.Store;

package body Quality_Manager.Config is
   package External_Formats renames Standard.Config.Formats;
   package External_Parsers renames Standard.Config.Parsers;
   package External_Reader renames Standard.Config.Reader;
   package External_Store renames Standard.Config.Store;

   use type External_Parsers.Parse_Status;
   use type External_Reader.Lookup_Status;
   use Quality_Manager.Results;

   package Components is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   Allowed_Keys : constant array (Positive range <>) of Unbounded_String :=
     [To_Unbounded_String ("coordinator.database"),
      To_Unbounded_String ("quality.database"),
      To_Unbounded_String ("scheduler.assessment_workers"),
      To_Unbounded_String ("scheduler.agent_workers"),
      To_Unbounded_String ("scheduler.maximum_task_seconds"),
      To_Unbounded_String ("scheduler.remediation_attempts"),
      To_Unbounded_String ("autonomy.dry_run")];

   function Defaults return Settings is
     (Coordinator_Database => To_Unbounded_String ("var/quality-manager.db"),
      Quality_Database     => Null_Unbounded_String,
      Assessment_Workers   => 4,
      Agent_Workers        => 1,
      Maximum_Task_Seconds => 3_600,
      Remediation_Attempts => 2,
      Dry_Run              => True);

   function Is_Allowed (Key : String) return Boolean is
   begin
      for Candidate of Allowed_Keys loop
         if Key = To_String (Candidate) then
            return True;
         end if;
      end loop;
      return False;
   end Is_Allowed;

   function Is_Continuation (Value : Natural) return Boolean is
     (Value in 16#80# .. 16#BF#);

   function Is_Valid_UTF_8 (Text : String) return Boolean is
      I : Integer := Text'First;

      function Byte (Offset : Natural) return Natural is
        (Character'Pos (Text (I + Integer (Offset))));

      function Available (Count : Positive) return Boolean is
        (I + Integer (Count) - 1 <= Text'Last);
   begin
      while I <= Text'Last loop
         if Byte (0) <= 16#7F# then
            I := I + 1;
         elsif Byte (0) in 16#C2# .. 16#DF# then
            if not Available (2) or else not Is_Continuation (Byte (1)) then
               return False;
            end if;
            I := I + 2;
         elsif Byte (0) = 16#E0# then
            if not Available (3)
              or else Byte (1) not in 16#A0# .. 16#BF#
              or else not Is_Continuation (Byte (2))
            then
               return False;
            end if;
            I := I + 3;
         elsif Byte (0) in 16#E1# .. 16#EC# or else Byte (0) in 16#EE# .. 16#EF# then
            if not Available (3)
              or else not Is_Continuation (Byte (1))
              or else not Is_Continuation (Byte (2))
            then
               return False;
            end if;
            I := I + 3;
         elsif Byte (0) = 16#ED# then
            if not Available (3)
              or else Byte (1) not in 16#80# .. 16#9F#
              or else not Is_Continuation (Byte (2))
            then
               return False;
            end if;
            I := I + 3;
         elsif Byte (0) = 16#F0# then
            if not Available (4)
              or else Byte (1) not in 16#90# .. 16#BF#
              or else not Is_Continuation (Byte (2))
              or else not Is_Continuation (Byte (3))
            then
               return False;
            end if;
            I := I + 4;
         elsif Byte (0) in 16#F1# .. 16#F3# then
            if not Available (4)
              or else not Is_Continuation (Byte (1))
              or else not Is_Continuation (Byte (2))
              or else not Is_Continuation (Byte (3))
            then
               return False;
            end if;
            I := I + 4;
         elsif Byte (0) = 16#F4# then
            if not Available (4)
              or else Byte (1) not in 16#80# .. 16#8F#
              or else not Is_Continuation (Byte (2))
              or else not Is_Continuation (Byte (3))
            then
               return False;
            end if;
            I := I + 4;
         else
            return False;
         end if;
      end loop;
      return True;
   end Is_Valid_UTF_8;

   function Normalize_Path (Path : String) return String is
      Full  : constant String :=
        (if Path'Length > 0 and then Path (Path'First) = '/'
         then Path
         else Ada.Directories.Current_Directory & "/" & Path);
      Parts : Components.Vector;
      Start : Integer := Full'First;
      Stop  : Integer;
      Result : Unbounded_String := To_Unbounded_String ("/");
   begin
      if Path'Length = 0 then
         return "";
      end if;

      while Start <= Full'Last loop
         while Start <= Full'Last and then Full (Start) = '/' loop
            Start := Start + 1;
         end loop;
         exit when Start > Full'Last;
         Stop := Start;
         while Stop <= Full'Last and then Full (Stop) /= '/' loop
            Stop := Stop + 1;
         end loop;
         declare
            Part : constant String := Full (Start .. Stop - 1);
         begin
            if Part = "." then
               null;
            elsif Part = ".." then
               if not Parts.Is_Empty then
                  Parts.Delete_Last;
               end if;
            else
               Parts.Append (Part);
            end if;
         end;
         Start := Stop + 1;
      end loop;

      for Index in Parts.First_Index .. Parts.Last_Index loop
         if Index > Parts.First_Index then
            Append (Result, "/");
         end if;
         Append (Result, Parts (Index));
      end loop;
      return To_String (Result);
   end Normalize_Path;

   function Read_File (Path : String; Ok : out Boolean) return String is
      package IO renames Ada.Streams.Stream_IO;
      use type IO.Count;
      use type Ada.Streams.Stream_Element_Offset;
      File : IO.File_Type;
   begin
      IO.Open (File, IO.In_File, Path);
      declare
         Length : constant IO.Count := IO.Size (File);
      begin
         if Length = 0 then
            IO.Close (File);
            Ok := True;
            return "";
         end if;
         declare
            Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Length));
            Last : Ada.Streams.Stream_Element_Offset;
            Text : String (1 .. Natural (Length));
         begin
            IO.Read (File, Data, Last);
            IO.Close (File);
            if Last /= Data'Last then
               Ok := False;
               return "";
            end if;
            for Index in Text'Range loop
               Text (Index) := Character'Val (Data (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
            Ok := True;
            return Text;
         end;
      end;
   exception
      when others =>
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         Ok := False;
         return "";
   end Read_File;

   procedure Load
     (Path     : String;
      Required : Boolean;
      Item     : out Settings;
      Result   : out Operation_Result) is
      Store       : External_Store.Store (Capacity => 32, Values_Capacity => 64, Pool => 8_192);
      Parse       : External_Parsers.Parse_Result;
      Read_Ok     : Boolean;
      Integer_Val : Interfaces.Integer_64;
      Status      : External_Reader.Lookup_Status;
      Bool_Val    : Boolean;
   begin
      Item := Defaults;
      if Path'Length = 0 then
         Result := Make_Result (Success);
         return;
      end if;
      if not Ada.Directories.Exists (Path) then
         Result :=
           (if Required
            then Make_Result (Not_Found, "configuration file not found: " & Path, "qm.config.not-found")
            else Make_Result (Success));
         return;
      end if;

      declare
         Text : constant String := Read_File (Path, Read_Ok);
      begin
         if not Read_Ok then
            Result := Make_Result (Execution_Error, "cannot read configuration: " & Path, "qm.config.read");
            return;
         elsif not Is_Valid_UTF_8 (Text) then
            Result := Make_Result (Invalid_Request, "configuration is not valid UTF-8", "qm.config.encoding");
            return;
         end if;
         External_Formats.Parse (External_Formats.Toml, Text, Store, 1, Parse);
      end;

      if Parse.Status /= External_Parsers.Parsed then
         Result := Make_Result
           (Invalid_Request,
            "invalid TOML configuration at line" & Parse.Line'Image,
            "qm.config.syntax");
         return;
      end if;

      for Index in 1 .. External_Store.Count (Store) loop
         if not Is_Allowed (External_Store.Key_At (Store, Index)) then
            Result := Make_Result
              (Invalid_Request,
               "unknown configuration key: " & External_Store.Key_At (Store, Index),
               "qm.config.unknown-key");
            return;
         end if;
      end loop;

      declare
         Value : constant String := External_Reader.Get_String
           (Store, "coordinator.database", To_String (Item.Coordinator_Database));
      begin
         if Value'Length = 0 then
            Result := Make_Result
              (Invalid_Request, "coordinator.database must not be empty", "qm.config.empty-path");
            return;
         end if;
         Item.Coordinator_Database := To_Unbounded_String (Normalize_Path (Value));
      end;

      declare
         Value : constant String := External_Reader.Get_String (Store, "quality.database", "");
      begin
         Item.Quality_Database :=
           (if Value'Length = 0 then Null_Unbounded_String else To_Unbounded_String (Normalize_Path (Value)));
      end;

      External_Reader.Get_Integer (Store, "scheduler.assessment_workers", Integer_Val, Status);
      if Status = External_Reader.Invalid
        or else (Status = External_Reader.Found and then Integer_Val not in 1 .. 64)
      then
         Result := Make_Result
           (Invalid_Request, "scheduler.assessment_workers must be in 1..64", "qm.config.range");
         return;
      elsif Status = External_Reader.Found then
         Item.Assessment_Workers := Positive (Integer_Val);
      end if;

      External_Reader.Get_Integer (Store, "scheduler.agent_workers", Integer_Val, Status);
      if Status = External_Reader.Invalid
        or else (Status = External_Reader.Found and then Integer_Val not in 1 .. 64)
      then
         Result := Make_Result
           (Invalid_Request, "scheduler.agent_workers must be in 1..64", "qm.config.range");
         return;
      elsif Status = External_Reader.Found then
         Item.Agent_Workers := Positive (Integer_Val);
      end if;

      External_Reader.Get_Integer (Store, "scheduler.maximum_task_seconds", Integer_Val, Status);
      if Status = External_Reader.Invalid
        or else (Status = External_Reader.Found and then Integer_Val not in 1 .. 86_400)
      then
         Result := Make_Result
           (Invalid_Request, "scheduler.maximum_task_seconds must be in 1..86400", "qm.config.range");
         return;
      elsif Status = External_Reader.Found then
         Item.Maximum_Task_Seconds := Positive (Integer_Val);
      end if;

      External_Reader.Get_Integer (Store, "scheduler.remediation_attempts", Integer_Val, Status);
      if Status = External_Reader.Invalid
        or else (Status = External_Reader.Found and then Integer_Val not in 1 .. 10)
      then
         Result := Make_Result
           (Invalid_Request, "scheduler.remediation_attempts must be in 1..10", "qm.config.range");
         return;
      elsif Status = External_Reader.Found then
         Item.Remediation_Attempts := Positive (Integer_Val);
      end if;

      External_Reader.Get_Boolean (Store, "autonomy.dry_run", Bool_Val, Status);
      if Status = External_Reader.Invalid then
         Result := Make_Result
           (Invalid_Request, "autonomy.dry_run must be a boolean", "qm.config.type");
         return;
      elsif Status = External_Reader.Found then
         Item.Dry_Run := Bool_Val;
      end if;

      Result := Make_Result (Success);
   exception
      when others =>
         Result := Make_Result
           (Integrity_Error, "configuration validation failed unexpectedly", "qm.config.internal");
   end Load;
end Quality_Manager.Config;
