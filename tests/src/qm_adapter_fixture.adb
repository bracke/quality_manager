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
