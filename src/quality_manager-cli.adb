with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Quality_Manager.Results; use Quality_Manager.Results;

package body Quality_Manager.CLI is
   Default_Config : constant String := "config/quality-manager.toml";

   function Usage return String is
     ("Usage: quality-manager [--config PATH] [--format terminal|json|markdown] COMMAND"
      & ASCII.LF & ASCII.LF
      & "Commands:" & ASCII.LF
      & "  doctor    validate the read-only coordinator foundation" & ASCII.LF
      & "  maintenance [--project ID|PATH] [--dry-run]" & ASCII.LF
      & "            run one durable maintenance coordination cycle" & ASCII.LF
      & "  daemon [--once] [--project ID|PATH] [--dry-run]" & ASCII.LF
      & "            continuously schedule maintenance work" & ASCII.LF
      & "  help      show this help" & ASCII.LF
      & "  version   show the application version");

   procedure Parse
     (Arguments : Argument_Vectors.Vector;
      Item      : out Options;
      Result    : out Operation_Result) is
      Seen_Command : Boolean := False;
      Seen_Config  : Boolean := False;
      Seen_Format  : Boolean := False;
      Seen_Project : Boolean := False;
      Index        : Positive := Arguments.First_Index;

      procedure Fail (Message, Code : String) is
      begin
         Result := Make_Result (Invalid_Request, Message, Code);
      end Fail;

      procedure Set_Command (Command : Command_Kind) is
      begin
         if Seen_Command then
            Fail ("more than one command was supplied", "qm.cli.duplicate-command");
         else
            Item.Command := Command;
            Seen_Command := True;
         end if;
      end Set_Command;

      procedure Set_Format (Value : String) is
      begin
         if Seen_Format then
            Fail ("--format may be supplied only once", "qm.cli.duplicate-option");
         elsif Value = "terminal" then
            Item.Format := Terminal_Output;
            Seen_Format := True;
         elsif Value = "json" then
            Item.Format := JSON_Output;
            Seen_Format := True;
         elsif Value = "markdown" then
            Item.Format := Markdown_Output;
            Seen_Format := True;
         else
            Fail ("unsupported output format: " & Value, "qm.cli.invalid-format");
         end if;
      end Set_Format;

      procedure Set_Config (Value : String) is
      begin
         if Seen_Config then
            Fail ("--config may be supplied only once", "qm.cli.duplicate-option");
         elsif Value'Length = 0 then
            Fail ("--config requires a path", "qm.cli.missing-value");
         else
            Item.Config_Path := To_Unbounded_String (Value);
            Item.Config_Explicit := True;
            Seen_Config := True;
         end if;
      end Set_Config;
   begin
      Item :=
        (Command         => Help_Command,
         Format          => Terminal_Output,
         Config_Path     => To_Unbounded_String (Default_Config),
         Config_Explicit => False,
         Project_Selector => Null_Unbounded_String,
         Dry_Run         => False,
         Once            => False);
      Result := Make_Result (Success);

      if Arguments.Is_Empty then
         return;
      end if;

      while Index <= Arguments.Last_Index loop
         declare
            Argument : constant String := Arguments (Index);
         begin
            if Argument = "--config" then
               if Index = Arguments.Last_Index then
                  Fail ("--config requires a path", "qm.cli.missing-value");
               else
                  Index := Index + 1;
                  Set_Config (Arguments (Index));
               end if;
            elsif Argument'Length > 9 and then Argument (Argument'First .. Argument'First + 8) = "--config=" then
               Set_Config (Argument (Argument'First + 9 .. Argument'Last));
            elsif Argument = "--format" then
               if Index = Arguments.Last_Index then
                  Fail ("--format requires a value", "qm.cli.missing-value");
               else
                  Index := Index + 1;
                  Set_Format (Arguments (Index));
               end if;
            elsif Argument'Length > 9 and then Argument (Argument'First .. Argument'First + 8) = "--format=" then
               Set_Format (Argument (Argument'First + 9 .. Argument'Last));
            elsif Argument = "--project" then
               if Seen_Project then
                  Fail ("--project may be supplied only once", "qm.cli.duplicate-option");
               elsif Index = Arguments.Last_Index then
                  Fail ("--project requires a selector", "qm.cli.missing-value");
               else
                  Index := Index + 1;
                  Item.Project_Selector := To_Unbounded_String (Arguments (Index));
                  Seen_Project := True;
               end if;
            elsif Argument = "--dry-run" then
               Item.Dry_Run := True;
            elsif Argument = "--once" then
               Item.Once := True;
            elsif Argument = "--help" or else Argument = "-h" or else Argument = "help" then
               Set_Command (Help_Command);
            elsif Argument = "--version" or else Argument = "version" then
               Set_Command (Version_Command);
            elsif Argument = "doctor" then
               Set_Command (Doctor_Command);
            elsif Argument = "maintenance" then
               Set_Command (Maintenance_Command);
            elsif Argument = "daemon" then
               Set_Command (Daemon_Command);
            else
               Fail ("unknown argument: " & Argument, "qm.cli.unknown-argument");
            end if;
         end;
         exit when Result.Kind /= Success;
         Index := Index + 1;
      end loop;
      if Result.Kind = Success and then Item.Once and then Item.Command /= Daemon_Command then
         Fail ("--once is valid only with daemon", "qm.cli.option-scope");
      elsif Result.Kind = Success
        and then Length (Item.Project_Selector) > 0
        and then Item.Command not in Maintenance_Command | Daemon_Command
      then
         Fail ("--project requires maintenance or daemon", "qm.cli.option-scope");
      end if;
   exception
      when others =>
         Result := Make_Result
           (Invalid_Request, "invalid command line", "qm.cli.invalid");
   end Parse;
end Quality_Manager.CLI;
