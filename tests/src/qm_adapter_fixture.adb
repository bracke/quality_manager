with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

procedure QM_Adapter_Fixture is
   Status : Integer := 0;
   Numeric_Mode : Boolean := False;
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      begin
         Status := Integer'Value (Ada.Command_Line.Argument (1));
         Numeric_Mode := True;
      exception
         when Constraint_Error => Numeric_Mode := False;
      end;
   end if;
   if not Numeric_Mode then
      declare
         Invocation : Unbounded_String;
         Command     : Unbounded_String;
         Kind        : Unbounded_String;
         Database_Path : Unbounded_String;
         Has_State  : Boolean := False;
         Is_Database_Statistics : Boolean := False;
         Index      : Positive := 1;
      begin
         while Index <= Ada.Command_Line.Argument_Count loop
            declare
               Argument : constant String := Ada.Command_Line.Argument (Index);
            begin
               if Argument = "--state" then Has_State := True; end if;
               if Argument = "--database" then
                  Database_Path := To_Unbounded_String (Ada.Command_Line.Argument (Index + 1));
                  Index := Index + 2;
               elsif Argument in "--format" | "--config" | "--state" then
                  Index := Index + 2;
               else
                  if Length (Command) = 0 then
                     Command := To_Unbounded_String (Argument);
                  end if;
                  if Length (Invocation) > 0 then Append (Invocation, " "); end if;
                  Append (Invocation, Argument);
                  Index := Index + 1;
               end if;
            end;
         end loop;
         declare
            Text : constant String := To_String (Invocation);
         begin
            if Ada.Strings.Fixed.Index (Text, "project ") = 1 then
               Kind := To_Unbounded_String ("project-list");
            elsif Ada.Strings.Fixed.Index (Text, "check ") = 1
              and then Ada.Strings.Fixed.Index (Text, "--dry-run") > 0
            then
               Kind := To_Unbounded_String ("check-plan");
            elsif Ada.Strings.Fixed.Index (Text, "assessment diff ") = 1 then
               Kind := To_Unbounded_String ("assessment-comparison");
            elsif Ada.Strings.Fixed.Index (Text, "doctor ") = 1 then
               Kind := To_Unbounded_String ("doctor-report");
            elsif Text = "database stats" then
               Kind := To_Unbounded_String ("database-statistics");
               Is_Database_Statistics := True;
            elsif Text = "work capabilities" then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""work-capabilities""," &
                  """noninteractive"":true,""idempotent_operations"":true," &
                  """operation_lookup"":true,""workspace_isolation"":true," &
                  """semantic_conflict_resolution"":false,""commands"":" &
                  "[""inspect"",""execute"",""status"",""cancel"",""recover"",""integrate""]}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "work cancel ") = 1 then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""work-cancellation""," &
                  """operation_id"":""qm-execution-1"",""task_id"":""TASK-001""," &
                  """result"":""requested""}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "work recover ") = 1 then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""work-recovery""," &
                  """project_identity"":""project-identity"",""result"":""reconciled""}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            elsif Ada.Strings.Fixed.Index (Text, "work status ") = 1
              and then Ada.Strings.Fixed.Index (Text, "missing-operation") > 0
            then
               Ada.Text_IO.Put
                 ("{""schema_version"":1,""kind"":""error""," &
                  """error_code"":""MR-FRAMEWORK-0011"",""diagnostic"":""missing-operation""}");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (2));
               return;
            elsif Ada.Strings.Fixed.Index (Text, "work inspect ") = 1
              or else Ada.Strings.Fixed.Index (Text, "work execute ") = 1
              or else Ada.Strings.Fixed.Index (Text, "work status ") = 1
              or else Ada.Strings.Fixed.Index (Text, "work integrate ") = 1
            then
               declare
                  Operation : constant String :=
                    (if Ada.Strings.Fixed.Index (Text, "qm-execution-2") > 0 then "qm-execution-2"
                     elsif Ada.Strings.Fixed.Index (Text, "qm-execution-3") > 0 then "qm-execution-3"
                     else "qm-execution-1");
                  Is_Execute : constant Boolean := Ada.Strings.Fixed.Index (Text, "work execute ") = 1;
                  Is_Integrate : constant Boolean := Ada.Strings.Fixed.Index (Text, "work integrate ") = 1;
                  Running : constant Boolean := Operation = "qm-execution-2" and then Is_Execute;
                  Incompatible : constant Boolean := Operation = "qm-execution-3";
                  Audit : constant String := (if Is_Execute then "execute-audit" else "status-audit");
               begin
                  Ada.Text_IO.Put
                    ("{""schema_version"":1,""kind"":""work-operation""," &
                     """operation_id"":""" & Operation & """,""project_identity"":""project-identity""," &
                     """source_fingerprint"":""" &
                     (if Is_Integrate then "integrated-source" else "source-fingerprint") &
                     """,""task_id"":""TASK-001""," &
                     """task_revision"":""task-revision"",""effective_task_revision"":""effective-revision""," &
                     """execution_policy"":""policy-fingerprint"",""execution_generation"":""1""," &
                     """execution_state"":""" &
                     (if Incompatible then "incompatible"
                      elsif Running then "executing"
                      elsif Is_Integrate then "completed" else "awaiting_integration") &
                     """,""native_task_state"":""" & (if Running then "running" else "verification") &
                     """,""core_state"":""" & (if Running then "running" else "verification") &
                     """,""ready"":false,""readiness_reasons"":[]," &
                     """workspace_id"":""" & (if Is_Integrate then "" else "workspace-1") &
                     """,""workspace_state"":""" & (if Is_Integrate then "integrated" else "active") &
                     """," &
                     """result"":""success"",""diagnostics"":[],""audit_reference"":""" & Audit & """," &
                     """invocation"":""" & To_String (Invocation) & """}");
               end;
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
               return;
            end if;
         end;
         Ada.Text_IO.Put
           ("{""schema_version"":" & (if Has_State or else Is_Database_Statistics then "2" else "1")
            & ",""command"":""" & To_String (Command) & """"
            & ",""report_type"":""" & To_String (Command) & """"
            & ",""kind"":""" & To_String (Kind) & """"
            & (if Is_Database_Statistics and then To_String (Database_Path) = "quality.db"
               then ",""database_identity"":""123e4567-e89b-12d3-a456-426614174000"""
               elsif Is_Database_Statistics and then To_String (Database_Path) = "invalid-identity.db"
               then ",""database_identity"":""not-a-uuid"""
               else "")
            & ",""invocation"":""" & To_String (Invocation) & """}");
      end;
   elsif Ada.Command_Line.Argument_Count >= 2 and then Ada.Command_Line.Argument (2) = "invalid-utf8" then
      Ada.Text_IO.Put (Character'Val (16#C3#) & Character'Val (16#28#));
   elsif Ada.Command_Line.Argument_Count >= 2 then
      Ada.Text_IO.Put (Ada.Command_Line.Argument (2));
   end if;
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
end QM_Adapter_Fixture;
