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
      & "  status | queue | approvals | history | events | recover" & ASCII.LF
      & "            inspect durable coordinator state" & ASCII.LF
      & "  reconcile-assessment OPERATION RUN" & ASCII.LF
      & "            adopt a confirmed assessment after interrupted invocation" & ASCII.LF
      & "  campaign-create DEFINITION" & ASCII.LF
      & "  campaign-start|campaign-pause|campaign-resume|campaign-reconcile ID" & ASCII.LF
      & "  release-create PROJECT PROFILE" & ASCII.LF
      & "  release-qualify ID" & ASCII.LF
      & "  release-export ID OUTPUT" & ASCII.LF
      & "  approve RECORD | reject RECORD" & ASCII.LF
      & "            apply an exact, versioned authorization record" & ASCII.LF
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
      Value_Count  : Natural := 0;
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

      procedure Add_Value (Value : String) is
      begin
         if not Seen_Command then
            Fail ("a command must precede its operands", "qm.cli.operand-before-command");
         elsif Value_Count = 0 then
            Item.Primary_Value := To_Unbounded_String (Value);
            Value_Count := 1;
         elsif Value_Count = 1 then
            Item.Secondary_Value := To_Unbounded_String (Value);
            Value_Count := 2;
         else
            Fail ("too many command operands", "qm.cli.too-many-operands");
         end if;
      end Add_Value;

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
         Primary_Value   => Null_Unbounded_String,
         Secondary_Value => Null_Unbounded_String,
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
            elsif Argument = "status" then
               Set_Command (Status_Command);
            elsif Argument = "queue" then
               Set_Command (Queue_Command);
            elsif Argument = "approvals" then
               Set_Command (Approvals_Command);
            elsif Argument = "history" then
               Set_Command (History_Command);
            elsif Argument = "events" then
               Set_Command (Events_Command);
            elsif Argument = "recover" then
               Set_Command (Recover_Command);
            elsif Argument = "reconcile-assessment" then
               Set_Command (Reconcile_Assessment_Command);
            elsif Argument = "campaign-create" then
               Set_Command (Campaign_Create_Command);
            elsif Argument = "campaign-start" then
               Set_Command (Campaign_Start_Command);
            elsif Argument = "campaign-pause" then
               Set_Command (Campaign_Pause_Command);
            elsif Argument = "campaign-resume" then
               Set_Command (Campaign_Resume_Command);
            elsif Argument = "campaign-reconcile" then
               Set_Command (Campaign_Reconcile_Command);
            elsif Argument = "release-create" then
               Set_Command (Release_Create_Command);
            elsif Argument = "release-qualify" then
               Set_Command (Release_Qualify_Command);
            elsif Argument = "release-export" then
               Set_Command (Release_Export_Command);
            elsif Argument = "approve" then
               Set_Command (Approve_Command);
            elsif Argument = "reject" then
               Set_Command (Reject_Command);
            elsif Argument'Length > 0 and then Argument (Argument'First) /= '-' then
               Add_Value (Argument);
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
      elsif Result.Kind = Success then
         declare
            Required : constant Natural :=
              (case Item.Command is
                  when Campaign_Create_Command | Campaign_Start_Command | Campaign_Pause_Command
                     | Campaign_Resume_Command | Campaign_Reconcile_Command | Release_Qualify_Command
                     | Approve_Command | Reject_Command => 1,
                  when Release_Create_Command | Release_Export_Command | Reconcile_Assessment_Command => 2,
                  when others => 0);
         begin
            if Value_Count /= Required then
               Fail
                 ("command requires" & Natural'Image (Required) & " operand(s)",
                  "qm.cli.operand-count");
            end if;
         end;
      end if;
   exception
      when others =>  --  AQ: audited exception boundary
         Result := Make_Result
           (Invalid_Request, "invalid command line", "qm.cli.invalid");
   end Parse;
end Quality_Manager.CLI;
