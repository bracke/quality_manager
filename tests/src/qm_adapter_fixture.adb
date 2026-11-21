with Ada.Command_Line;
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
         Has_State  : Boolean := False;
         Index      : Positive := 1;
      begin
         while Index <= Ada.Command_Line.Argument_Count loop
            declare
               Argument : constant String := Ada.Command_Line.Argument (Index);
            begin
               if Argument = "--state" then Has_State := True; end if;
               if Argument in "--database" | "--format" | "--config" | "--state" then
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
         Ada.Text_IO.Put
           ("{""schema_version"":" & (if Has_State then "2" else "1")
            & ",""command"":""" & To_String (Command) & """"
            & ",""report_type"":""" & To_String (Command) & """"
            & ",""invocation"":""" & To_String (Invocation) & """}");
      end;
   elsif Ada.Command_Line.Argument_Count >= 2 and then Ada.Command_Line.Argument (2) = "invalid-utf8" then
      Ada.Text_IO.Put (Character'Val (16#C3#) & Character'Val (16#28#));
   elsif Ada.Command_Line.Argument_Count >= 2 then
      Ada.Text_IO.Put (Ada.Command_Line.Argument (2));
   end if;
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
end QM_Adapter_Fixture;
