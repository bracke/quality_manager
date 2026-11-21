with Ada.Strings.Unbounded;
with Hostkit;

package Quality_Manager.Integrations.Processes is
   package String_Vectors renames Hostkit.String_Vectors;

   type Cancellation_Check is access function return Boolean;

   type Request is record
      Executable        : Ada.Strings.Unbounded.Unbounded_String;
      Arguments         : String_Vectors.Vector;
      Working_Directory : Ada.Strings.Unbounded.Unbounded_String;
      Environment       : String_Vectors.Vector;
      Timeout_Seconds   : Natural := 60;
      Output_Limit      : Positive := 4 * 1_024 * 1_024;
      Cancelled         : Cancellation_Check := null;
   end record;

   type Execution_Result is record
      Started         : Boolean := False;
      Timed_Out       : Boolean := False;
      Cancelled       : Boolean := False;
      Output_Exceeded : Boolean := False;
      Exit_Status     : Integer := -1;
      Standard_Output : Ada.Strings.Unbounded.Unbounded_String;
      Error_Output    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   procedure Execute (Value : Request; Result : out Execution_Result);
end Quality_Manager.Integrations.Processes;
