with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Results;

package Quality_Manager.Integrations.JSON_CLI is
   type Exit_Contract is (Ada_Quality_Contract, Summary_Contract, Improve_Contract);

   type Response is record
      Status      : Quality_Manager.Results.Operation_Result;
      Exit_Status : Integer := -1;
      Document    : Ada.Strings.Unbounded.Unbounded_String;
      Diagnostics : Ada.Strings.Unbounded.Unbounded_String;
   end record;

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
end Quality_Manager.Integrations.JSON_CLI;
