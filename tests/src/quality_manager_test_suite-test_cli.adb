separate (Quality_Manager_Test_Suite)
procedure Test_CLI (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Args    : Quality_Manager.CLI.Argument_Vectors.Vector;
   Options : Quality_Manager.CLI.Options;
   Result  : Quality_Manager.Results.Operation_Result;
begin
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "empty command line selects help");

   Args.Append ("--config=");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty inline config path rejected");

   Args.Clear;
   Args.Append ("--config");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing option value rejected");

   Args.Clear;
   Args.Append ("--config");
   Args.Append ("");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty separate config path rejected");

   Args.Clear;
   Args.Append ("--format=json");
   Args.Append ("--format");
   Args.Append ("terminal");
   Args.Append ("doctor");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate option rejected");

   Args.Clear;
   Args.Append ("maintenance");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Options.Command = Quality_Manager.CLI.Maintenance_Command,
      "one-shot maintenance command is accepted");

   Args.Clear;
   Args.Append ("--once");
   Args.Append ("maintenance");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "daemon-only option scope is enforced");

   Args.Clear;
   Args.Append ("doctor");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "doctor accepted");
   Assert (Options.Command = Quality_Manager.CLI.Doctor_Command, "doctor selected");

   Args.Clear;
   Args.Append ("release-create");
   Args.Append ("7");
   Args.Append ("release");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Options.Command = Quality_Manager.CLI.Release_Create_Command
      and then To_String (Options.Primary_Value) = "7"
      and then To_String (Options.Secondary_Value) = "release",
      "release creation retains its exact operands");

   Args.Clear;
   Args.Append ("reconcile-assessment");
   Args.Append ("123");
   Args.Append ("4");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert
     (Result.Kind = Quality_Manager.Results.Success
      and then Options.Command = Quality_Manager.CLI.Reconcile_Assessment_Command
      and then To_String (Options.Primary_Value) = "123"
      and then To_String (Options.Secondary_Value) = "4",
      "assessment reconciliation retains operation and run identities");

   Args.Clear;
   Args.Append ("campaign-start");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing workflow operand rejected");

   Args.Clear;
   Args.Append ("status");
   Args.Append ("unexpected");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "read-only view rejects operands");

   Args.Clear;
   Args.Append ("doctor");
   Args.Append ("version");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate command is rejected");

   Args.Clear;
   Args.Append ("release-export");
   Args.Append ("release-1");
   Args.Append ("evidence.json");
   Args.Append ("extra");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "excess operands are rejected");

   for Format in Quality_Manager.CLI.Output_Format loop
      declare
         Name : constant String :=
           (case Format is
               when Quality_Manager.CLI.Terminal_Output => "terminal",
               when Quality_Manager.CLI.JSON_Output => "json",
               when Quality_Manager.CLI.Markdown_Output => "markdown");
      begin
         Args.Clear;
         Args.Append ("--format=" & Name);
         Args.Append ("doctor");
         Quality_Manager.CLI.Parse (Args, Options, Result);
         Assert (Result.Kind = Quality_Manager.Results.Success, "supported output format is accepted");
      end;
   end loop;

   Args.Clear;
   Args.Append ("--format=xml");
   Args.Append ("doctor");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "unknown output format is rejected");

   Args.Clear;
   Args.Append ("--format");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing format value is rejected");

   Args.Clear;
   Args.Append ("--config=/tmp/one.toml");
   Args.Append ("--config");
   Args.Append ("/tmp/two.toml");
   Args.Append ("doctor");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate config is rejected");

   Args.Clear;
   Args.Append ("--project");
   Args.Append ("one");
   Args.Append ("--project");
   Args.Append ("two");
   Args.Append ("maintenance");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "duplicate project selector is rejected");

   Args.Clear;
   Args.Append ("--project");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "missing project selector is rejected");

   Args.Clear;
   Args.Append ("--project");
   Args.Append ("");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "empty project selector is rejected");

   Args.Clear;
   Args.Append ("--project");
   Args.Append ("one");
   Args.Append ("doctor");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "project selector scope is enforced");

   Args.Clear;
   Args.Append ("operand");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "operand before command is rejected");

   Args.Clear;
   Args.Append ("--unknown");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "unknown option is rejected");

   Args.Clear;
   Args.Append ("--help");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "help flag is accepted");

   Args.Clear;
   Args.Append ("--version");
   Quality_Manager.CLI.Parse (Args, Options, Result);
   Assert (Result.Kind = Quality_Manager.Results.Success, "version flag is accepted");
end Test_CLI;

