with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Quality_Manager.Config;
with Quality_Manager.Schemas;

package body Quality_Manager.Integrations.JSON_CLI is
   use type Quality_Manager.Results.Result_Kind;
   use Quality_Manager.Results;

   function Exit_Result (Contract : Exit_Contract; Code : Integer) return Operation_Result is
   begin
      case Contract is
         when Ada_Quality_Contract =>
            case Code is
               when 0      => return Make_Result (Success);
               when 1      => return Make_Result (Negative_Result, "quality assessment found violations");
               when 2      => return Make_Result (Invalid_Request, "Ada Quality rejected the request");
               when 3      => return Make_Result (Stale_Evidence, "quality evidence is incomplete or unavailable");
               when 4      => return Make_Result (Integrity_Error, "Ada Quality database or evidence failure");
               when others => return Make_Result (Execution_Error, "unknown Ada Quality exit status");
            end case;
         when Summary_Contract =>
            case Code is
               when 0      => return Make_Result (Success);
               when 1      => return Make_Result (Negative_Result, "Summary fail-on condition holds");
               when 2      => return Make_Result (Invalid_Request, "Summary rejected the request");
               when 3      => return Make_Result (Execution_Error, "Summary reporting failed");
               when 4      => return Make_Result (Integrity_Error, "Summary database failure");
               when others => return Make_Result (Execution_Error, "unknown Summary exit status");
            end case;
         when Improve_Contract =>
            case Code is
               when 0      => return Make_Result (Success);
               when 1      => return Make_Result (Negative_Result, "Improve reports unresolved work");
               when 2      => return Make_Result (Invalid_Request, "Improve rejected the request");
               when 3      => return Make_Result (Temporarily_Unavailable, "Improve dependency is unavailable");
               when 4      => return Make_Result (Execution_Error, "Improve operation failed");
               when 130    => return Make_Result (Interrupted, "Improve operation was interrupted");
               when others => return Make_Result (Execution_Error, "unknown Improve exit status");
            end case;
         when Model_Runner_Contract =>
            case Code is
               when 0      => return Make_Result (Success);
               when 2      => return Make_Result (Invalid_Request, "model_runner rejected the request");
               when 3      => return Make_Result (Execution_Error, "model_runner model execution failed");
               when 4      => return Make_Result (Incompatible_Contract, "model_runner operation is unsupported");
               when 5      => return Make_Result (Temporarily_Unavailable, "model_runner resource is unavailable");
               when 6      => return Make_Result (Negative_Result, "model_runner native work did not succeed");
               when 7      => return Make_Result (Interrupted, "model_runner operation was interrupted");
               when 8      => return Make_Result (Execution_Error, "model_runner internal operation failed");
               when others => return Make_Result (Execution_Error, "unknown model_runner exit status");
            end case;
      end case;
   end Exit_Result;

   procedure Execute
     (Executable        : String;
      Arguments         : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Working_Directory : String;
      Environment       : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
      Contract          : Exit_Contract;
      Schema_Version    : Positive;
      Timeout_Seconds   : Natural;
      Output_Limit      : Positive;
      Result            : out Response;
      Discriminator_Name  : String := "";
      Discriminator_Value : String := "") is
      Request : Quality_Manager.Integrations.Processes.Request;
      Process : Quality_Manager.Integrations.Processes.Execution_Result;
      JSON_Status : Operation_Result;
   begin
      Request.Executable := To_Unbounded_String (Executable);
      Request.Arguments := Arguments;
      Request.Working_Directory := To_Unbounded_String (Working_Directory);
      Request.Environment := Environment;
      Request.Timeout_Seconds := Timeout_Seconds;
      Request.Output_Limit := Output_Limit;
      Quality_Manager.Integrations.Processes.Execute (Request, Process);
      Result :=
        (Status => Make_Result (Execution_Error, "process did not start"),
         Exit_Status => Process.Exit_Status,
         Document => Process.Standard_Output,
         Diagnostics => Process.Error_Output);
      if not Process.Started then
         return;
      elsif Process.Output_Exceeded then
         Result.Status := Make_Result (Execution_Error, "process output limit exceeded", "qm.process.output-limit");
         return;
      elsif Process.Cancelled then
         Result.Status := Make_Result (Interrupted, "process cancelled", "qm.process.cancelled");
         return;
      elsif Process.Timed_Out then
         Result.Status := Make_Result (Temporarily_Unavailable, "process deadline exceeded", "qm.process.timeout");
         return;
      elsif not Quality_Manager.Config.Is_Valid_UTF_8 (To_String (Process.Standard_Output))
        or else not Quality_Manager.Config.Is_Valid_UTF_8 (To_String (Process.Error_Output))
      then
         Result.Status := Make_Result (Incompatible_Contract, "process output is not valid UTF-8", "qm.process.utf8");
         return;
      end if;

      Result.Status := Exit_Result (Contract, Process.Exit_Status);
      if Result.Status.Kind not in Success | Negative_Result | Stale_Evidence then
         return;
      end if;
      Quality_Manager.Schemas.Validate_Versioned_JSON
        (To_String (Process.Standard_Output), Schema_Version, JSON_Status,
         Discriminator_Name, Discriminator_Value);
      if JSON_Status.Kind /= Success then
         Result.Status := JSON_Status;
      end if;
   end Execute;
end Quality_Manager.Integrations.JSON_CLI;
