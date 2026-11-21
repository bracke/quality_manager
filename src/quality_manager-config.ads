with Ada.Strings.Unbounded;
with Quality_Manager.Results;

package Quality_Manager.Config is
   type Settings is record
      Coordinator_Database  : Ada.Strings.Unbounded.Unbounded_String;
      Quality_Database      : Ada.Strings.Unbounded.Unbounded_String;
      Ada_Quality_Executable : Ada.Strings.Unbounded.Unbounded_String;
      Model_Runner_Executable : Ada.Strings.Unbounded.Unbounded_String;
      Assessment_Workers    : Positive := 4;
      Agent_Workers         : Positive := 1;
      Maximum_Task_Seconds  : Positive := 3_600;
      Remediation_Attempts  : Positive := 2;
      Dry_Run               : Boolean := True;
   end record;

   function Defaults return Settings;

   procedure Load
     (Path     : String;
      Required : Boolean;
      Item     : out Settings;
      Result   : out Quality_Manager.Results.Operation_Result);

   function Normalize_Path (Path : String) return String;
   function Is_Valid_UTF_8 (Text : String) return Boolean;
end Quality_Manager.Config;
