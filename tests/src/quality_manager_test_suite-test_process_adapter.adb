separate (Quality_Manager_Test_Suite)
procedure Test_Process_Adapter (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Request : Quality_Manager.Integrations.Processes.Request;
   Result  : Quality_Manager.Integrations.Processes.Execution_Result;
begin
   Request.Executable := To_Unbounded_String ("/usr/bin/printf");
   Request.Arguments.Append (To_Unbounded_String ("%s"));
   Request.Arguments.Append (To_Unbounded_String ("literal;not-a-command"));
   Request.Output_Limit := 1_024;
   Quality_Manager.Integrations.Processes.Execute (Request, Result);
   Assert
     (Result.Started and then Result.Exit_Status = 0
      and then To_String (Result.Standard_Output) = "literal;not-a-command",
      "argument vector is executed without shell interpretation");

   Request.Executable := To_Unbounded_String ("/usr/bin/true");
   Request.Arguments.Clear;
   Quality_Manager.Integrations.Processes.Execute (Request, Result);
   Assert
     (Result.Started and then Result.Exit_Status = 0
      and then Length (Result.Standard_Output) = 0,
      "empty process output is represented as an empty value");

   Request.Arguments.Clear;
   Request.Executable := To_Unbounded_String ("/usr/bin/env");
   Request.Environment.Append (To_Unbounded_String ("QM_VISIBLE=yes"));
   Quality_Manager.Integrations.Processes.Execute (Request, Result);
   Assert
     (To_String (Result.Standard_Output) = "QM_VISIBLE=yes" & ASCII.LF,
      "child receives only the explicit environment allowlist");

   Request.Environment.Clear;
   Request.Executable := To_Unbounded_String ("/usr/bin/printf");
   Request.Arguments.Append (To_Unbounded_String ("12345678901234567890"));
   Request.Output_Limit := 8;
   Quality_Manager.Integrations.Processes.Execute (Request, Result);
   Assert
     (Result.Output_Exceeded and then Length (Result.Standard_Output) <= 8,
      "captured output is bounded");

   Request.Executable := To_Unbounded_String ("quality-manager-no-such-executable");
   Request.Arguments.Clear;
   Quality_Manager.Integrations.Processes.Execute (Request, Result);
   Assert (not Result.Started, "missing executable is classified before invocation");
end Test_Process_Adapter;

