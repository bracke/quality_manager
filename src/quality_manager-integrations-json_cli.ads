with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Results;

--  Executes and validates versioned JSON command contracts.
package Quality_Manager.Integrations.JSON_CLI is
   --  Public contract for this Quality Manager unit.
   type Exit_Contract is
     (Ada_Quality_Contract,
      Summary_Contract,
      Improve_Contract,
      Model_Runner_Contract);
   --  Exit Contract values.
   --  @enum Ada_Quality_Contract Ada Quality Contract.
   --  @enum Summary_Contract Summary Contract.
   --  @enum Improve_Contract Improve Contract.
   --  @enum Model_Runner_Contract Model Runner Contract.

   type Response is record
      Status      : Quality_Manager.Results.Operation_Result;
      Exit_Status : Integer := -1;
      Document    : Ada.Strings.Unbounded.Unbounded_String;
      Diagnostics : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Response record.
   --  @field Status Status.
   --  @field Exit_Status Exit Status.
   --  @field Document Document.
   --  @field Diagnostics Diagnostics.

   procedure Execute
     (Executable       : String;
      Arguments        : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Working_Directory : String;
      Environment      : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Contract         : Exit_Contract;
      Schema_Version   : Positive;
      Timeout_Seconds  : Natural;
      Output_Limit     : Positive;
      Result           : out Response;
      Discriminator_Name  : String := "";
      Discriminator_Value : String := "");
   --  Perform Execute.
   --  @param Executable Executable.
   --  @param Arguments Arguments.
   --  @param Working_Directory Working Directory.
   --  @param Environment Environment.
   --  @param Contract Contract.
   --  @param Schema_Version Schema Version.
   --  @param Timeout_Seconds Timeout Seconds.
   --  @param Output_Limit Output Limit.
   --  @param Result Result.
   --  @param Discriminator_Name Discriminator Name.
   --  @param Discriminator_Value Discriminator Value.
end Quality_Manager.Integrations.JSON_CLI;
