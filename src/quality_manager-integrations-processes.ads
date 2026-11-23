with Ada.Strings.Unbounded;
with Hostkit;

--  Provides bounded, shell-free external process execution.
package Quality_Manager.Integrations.Processes is
   --  Public contract for this Quality Manager unit.
   package String_Vectors renames Hostkit.String_Vectors;

   type Cancellation_Check is access function return Boolean;
   --  Cancellation Check domain value.
   --  @return True when execution cancellation has been requested.

   type Request is record
      Executable        : Ada.Strings.Unbounded.Unbounded_String;
      Arguments         : String_Vectors.Vector;
      Working_Directory : Ada.Strings.Unbounded.Unbounded_String;
      Environment       : String_Vectors.Vector;
      Timeout_Seconds   : Natural := 60;
      Output_Limit      : Positive := 4 * 1_024 * 1_024;
      Cancelled         : Cancellation_Check := null;
   end record;
   --  Request record.
   --  @field Executable Executable.
   --  @field Arguments Arguments.
   --  @field Working_Directory Working Directory.
   --  @field Environment Environment.
   --  @field Timeout_Seconds Timeout Seconds.
   --  @field Output_Limit Output Limit.
   --  @field Cancelled Cancelled.

   type Execution_Result is record
      Started         : Boolean := False;
      Timed_Out       : Boolean := False;
      Cancelled       : Boolean := False;
      Output_Exceeded : Boolean := False;
      Exit_Status     : Integer := -1;
      Standard_Output : Ada.Strings.Unbounded.Unbounded_String;
      Error_Output    : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Execution Result record.
   --  @field Started Started.
   --  @field Timed_Out Timed Out.
   --  @field Cancelled Cancelled.
   --  @field Output_Exceeded Output Exceeded.
   --  @field Exit_Status Exit Status.
   --  @field Standard_Output Standard Output.
   --  @field Error_Output Error Output.

   procedure Execute (Value : Request; Result : out Execution_Result);
   --  Perform Execute.
   --  @param Value Value.
   --  @param Result Result.
end Quality_Manager.Integrations.Processes;
