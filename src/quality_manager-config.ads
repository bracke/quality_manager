with Ada.Strings.Unbounded;
with Quality_Manager.Results;

--  Loads and validates coordinator configuration.
package Quality_Manager.Config is
   --  Public contract for this Quality Manager unit.
   type Settings is record
      Coordinator_Database  : Ada.Strings.Unbounded.Unbounded_String;
      Quality_Database      : Ada.Strings.Unbounded.Unbounded_String;
      Quality_Policy        : Ada.Strings.Unbounded.Unbounded_String;
      Ada_Quality_Executable : Ada.Strings.Unbounded.Unbounded_String;
      Ada_Quality_Summary_Executable : Ada.Strings.Unbounded.Unbounded_String;
      Improve_Executable    : Ada.Strings.Unbounded.Unbounded_String;
      Improve_Config        : Ada.Strings.Unbounded.Unbounded_String;
      Improve_State         : Ada.Strings.Unbounded.Unbounded_String;
      Model_Runner_Executable : Ada.Strings.Unbounded.Unbounded_String;
      Assessment_Workers    : Positive := 4;
      Agent_Workers         : Positive := 1;
      Maximum_Task_Seconds  : Positive := 3_600;
      Remediation_Attempts  : Positive := 2;
      Dry_Run               : Boolean := True;
   end record;
   --  Settings record.
   --  @field Coordinator_Database Coordinator Database.
   --  @field Quality_Database Quality Database.
   --  @field Quality_Policy Quality Policy.
   --  @field Ada_Quality_Executable Ada Quality Executable.
   --  @field Ada_Quality_Summary_Executable Ada Quality Summary Executable.
   --  @field Improve_Executable Improve Executable.
   --  @field Improve_Config Improve Config.
   --  @field Improve_State Improve State.
   --  @field Model_Runner_Executable Model Runner Executable.
   --  @field Assessment_Workers Assessment Workers.
   --  @field Agent_Workers Agent Workers.
   --  @field Maximum_Task_Seconds Maximum Task Seconds.
   --  @field Remediation_Attempts Remediation Attempts.
   --  @field Dry_Run Dry Run.

   function Defaults return Settings;
   --  Return Defaults.
   --  @return Defaults result.

   procedure Load
     (Path     : String;
      Required : Boolean;
      Item     : out Settings;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Load.
   --  @param Path Path.
   --  @param Required Required.
   --  @param Item Item.
   --  @param Result Result.

   function Normalize_Path (Path : String) return String;
   --  Return Normalize Path.
   --  @param Path Path.
   --  @return Normalize Path result.
   function Is_Valid_UTF_8 (Text : String) return Boolean;
   --  Return Is Valid UTF 8.
   --  @param Text Text.
   --  @return Is Valid UTF 8 result.
end Quality_Manager.Config;
