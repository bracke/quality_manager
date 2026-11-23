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
      To_Unbounded_String ("quality.policy"),
      To_Unbounded_String ("integrations.ada_quality"),
      To_Unbounded_String ("integrations.ada_quality_summary"),
      To_Unbounded_String ("integrations.improve"),
      To_Unbounded_String ("integrations.improve_config"),
      To_Unbounded_String ("integrations.improve_state"),
      To_Unbounded_String ("integrations.model_runner"),
      To_Unbounded_String ("scheduler.assessment_workers"),
      To_Unbounded_String ("scheduler.agent_workers"),
      To_Unbounded_String ("scheduler.maximum_task_seconds"),
      To_Unbounded_String ("scheduler.remediation_attempts"),
      To_Unbounded_String ("autonomy.dry_run")];

   function Defaults return Settings is
     (Coordinator_Database => To_Unbounded_String ("var/quality-manager.db"),
      Quality_Database     => Null_Unbounded_String,
      Quality_Policy       => Null_Unbounded_String,
      Ada_Quality_Executable => To_Unbounded_String ("ada-quality"),
      Ada_Quality_Summary_Executable => To_Unbounded_String ("ada-quality-summary"),
      Improve_Executable   => To_Unbounded_String ("improve"),
      Improve_Config       => Null_Unbounded_String,
      Improve_State        => To_Unbounded_String ("var/improve.db"),
      Model_Runner_Executable => To_Unbounded_String ("model_runner"),
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

      function Valid_Two_Byte return Boolean is
      begin
         return Available (2) and then Is_Continuation (Byte (1));
      end Valid_Two_Byte;

      function Valid_Three_Byte return Boolean is
      begin
         if not Available (3) then
            return False;
         elsif Byte (0) = 16#E0# then
            return Byte (1) in 16#A0# .. 16#BF# and then Is_Continuation (Byte (2));
         elsif Byte (0) = 16#ED# then
            return Byte (1) in 16#80# .. 16#9F# and then Is_Continuation (Byte (2));
         else
            return Is_Continuation (Byte (1)) and then Is_Continuation (Byte (2));
         end if;
      end Valid_Three_Byte;

      function Valid_Four_Byte return Boolean is
      begin
         if not Available (4) then
            return False;
         elsif Byte (0) = 16#F0# then
            return Byte (1) in 16#90# .. 16#BF#
              and then Is_Continuation (Byte (2))
              and then Is_Continuation (Byte (3));
         elsif Byte (0) = 16#F4# then
            return Byte (1) in 16#80# .. 16#8F#
              and then Is_Continuation (Byte (2))
              and then Is_Continuation (Byte (3));
         else
            return Is_Continuation (Byte (1))
              and then Is_Continuation (Byte (2))
              and then Is_Continuation (Byte (3));
         end if;
      end Valid_Four_Byte;
   begin
      while I <= Text'Last loop
         if Byte (0) <= 16#7F# then
            I := I + 1;
         elsif Byte (0) in 16#C2# .. 16#DF# then
            if not Valid_Two_Byte then
               return False;
            end if;
            I := I + 2;
         elsif Byte (0) in 16#E0# .. 16#EF# then
            if not Valid_Three_Byte then
               return False;
            end if;
            I := I + 3;
         elsif Byte (0) in 16#F0# .. 16#F4# then
            if not Valid_Four_Byte then
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
      when others =>  --  AQ: audited exception boundary
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         Ok := False;
         return "";
   end Read_File;

   procedure Validate_Keys
     (Store  : External_Store.Store;
      Result : in out Operation_Result) is
   begin
      if Result.Kind /= Success then
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
   end Validate_Keys;

   procedure Read_Required_Value
     (Store         : External_Store.Store;
      Name          : String;
      Default       : String;
      Error_Message : String;
      Error_Code    : String;
      Normalize     : Boolean;
      Value         : in out Unbounded_String;
      Result        : in out Operation_Result) is
      Text : Unbounded_String;
   begin
      if Result.Kind /= Success then
         return;
      end if;
      Text := To_Unbounded_String (External_Reader.Get_String (Store, Name, Default));
      if Length (Text) = 0 then
         Result := Make_Result (Invalid_Request, Error_Message, Error_Code);
      elsif Normalize then
         Value := To_Unbounded_String (Normalize_Path (To_String (Text)));
      else
         Value := Text;
      end if;
   end Read_Required_Value;

   procedure Read_Optional_Path
     (Store  : External_Store.Store;
      Name   : String;
      Value  : in out Unbounded_String;
      Result : in out Operation_Result) is
      Text : Unbounded_String;
   begin
      if Result.Kind /= Success then
         return;
      end if;
      Text := To_Unbounded_String (External_Reader.Get_String (Store, Name, ""));
      if Length (Text) = 0 then
         Value := Null_Unbounded_String;
      else
         Value := To_Unbounded_String (Normalize_Path (To_String (Text)));
      end if;
   end Read_Optional_Path;

   procedure Read_Positive
     (Store         : External_Store.Store;
      Name          : String;
      Maximum       : Positive;
      Error_Message : String;
      Value         : in out Positive;
      Result        : in out Operation_Result) is
      Integer_Val : Interfaces.Integer_64;
      Status      : External_Reader.Lookup_Status;
   begin
      if Result.Kind /= Success then
         return;
      end if;
      External_Reader.Get_Integer (Store, Name, Integer_Val, Status);
      if Status = External_Reader.Invalid then
         Result := Make_Result (Invalid_Request, Error_Message, "qm.config.range");
      elsif Status = External_Reader.Found and then Integer_Val not in 1 .. Interfaces.Integer_64 (Maximum) then
         Result := Make_Result (Invalid_Request, Error_Message, "qm.config.range");
      elsif Status = External_Reader.Found then
         Value := Positive (Integer_Val);
      end if;
   end Read_Positive;

   procedure Read_Dry_Run
     (Store  : External_Store.Store;
      Value  : in out Boolean;
      Result : in out Operation_Result) is
      Parsed : Boolean;
      Status : External_Reader.Lookup_Status;
   begin
      if Result.Kind /= Success then
         return;
      end if;
      External_Reader.Get_Boolean (Store, "autonomy.dry_run", Parsed, Status);
      if Status = External_Reader.Invalid then
         Result := Make_Result
           (Invalid_Request, "autonomy.dry_run must be a boolean", "qm.config.type");
      elsif Status = External_Reader.Found then
         Value := Parsed;
      end if;
   end Read_Dry_Run;

   procedure Load
     (Path     : String;
      Required : Boolean;
      Item     : out Settings;
      Result   : out Operation_Result) is
      Store       : External_Store.Store (Capacity => 32, Values_Capacity => 64, Pool => 8_192);
      Parse       : External_Parsers.Parse_Result;
      Read_Ok     : Boolean;
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

      Result := Make_Result (Success);
      Validate_Keys (Store, Result);
      Read_Required_Value
        (Store, "integrations.ada_quality", To_String (Item.Ada_Quality_Executable),
         "integrations.ada_quality must not be empty", "qm.config.empty-executable", False,
         Item.Ada_Quality_Executable, Result);
      Read_Required_Value
        (Store, "integrations.ada_quality_summary", To_String (Item.Ada_Quality_Summary_Executable),
         "integrations.ada_quality_summary must not be empty", "qm.config.empty-executable", False,
         Item.Ada_Quality_Summary_Executable, Result);
      Read_Required_Value
        (Store, "coordinator.database", To_String (Item.Coordinator_Database),
         "coordinator.database must not be empty", "qm.config.empty-path", True,
         Item.Coordinator_Database, Result);
      Read_Optional_Path (Store, "quality.database", Item.Quality_Database, Result);
      Read_Optional_Path (Store, "quality.policy", Item.Quality_Policy, Result);
      Read_Required_Value
        (Store, "integrations.model_runner", To_String (Item.Model_Runner_Executable),
         "integrations.model_runner must not be empty", "qm.config.empty-executable", False,
         Item.Model_Runner_Executable, Result);
      Read_Required_Value
        (Store, "integrations.improve", To_String (Item.Improve_Executable),
         "integrations.improve must not be empty", "qm.config.empty-executable", False,
         Item.Improve_Executable, Result);
      Read_Optional_Path (Store, "integrations.improve_config", Item.Improve_Config, Result);
      Read_Required_Value
        (Store, "integrations.improve_state", To_String (Item.Improve_State),
         "integrations.improve_state must not be empty", "qm.config.empty-path", True,
         Item.Improve_State, Result);
      Read_Positive
        (Store, "scheduler.assessment_workers", 64,
         "scheduler.assessment_workers must be in 1..64", Item.Assessment_Workers, Result);
      Read_Positive
        (Store, "scheduler.agent_workers", 64,
         "scheduler.agent_workers must be in 1..64", Item.Agent_Workers, Result);
      Read_Positive
        (Store, "scheduler.maximum_task_seconds", 86_400,
         "scheduler.maximum_task_seconds must be in 1..86400", Item.Maximum_Task_Seconds, Result);
      Read_Positive
        (Store, "scheduler.remediation_attempts", 10,
         "scheduler.remediation_attempts must be in 1..10", Item.Remediation_Attempts, Result);
      Read_Dry_Run (Store, Item.Dry_Run, Result);
   exception
      when others =>  --  AQ: audited exception boundary
         Result := Make_Result
           (Integrity_Error, "configuration validation failed unexpectedly", "qm.config.internal");
   end Load;
end Quality_Manager.Config;
