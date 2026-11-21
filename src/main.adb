with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Quality_Manager;
with Quality_Manager.Approvals;
with Quality_Manager.Campaigns;
with Quality_Manager.CLI;
with Quality_Manager.Config;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Runner;
with Quality_Manager.Maintenance;
with Quality_Manager.Releases;
with Quality_Manager.Reporting;
with Quality_Manager.Results;
with Quality_Manager.Storage;

procedure Main is
   use type Quality_Manager.CLI.Command_Kind;
   use type Quality_Manager.Results.Result_Kind;

   Arguments : Quality_Manager.CLI.Argument_Vectors.Vector;
   Options   : Quality_Manager.CLI.Options;
   Settings  : Quality_Manager.Config.Settings;
   Result    : Quality_Manager.Results.Operation_Result;

   procedure Report_Failure is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, Quality_Manager.Results.Message (Result));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Report_Failure;

   function View_For
     (Command : Quality_Manager.CLI.Command_Kind) return Quality_Manager.Reporting.Operational_View is
     (case Command is
         when Quality_Manager.CLI.Status_Command    => Quality_Manager.Reporting.Overall_Status,
         when Quality_Manager.CLI.Queue_Command     => Quality_Manager.Reporting.Queue_Status,
         when Quality_Manager.CLI.Approvals_Command => Quality_Manager.Reporting.Approval_Status,
         when Quality_Manager.CLI.History_Command   => Quality_Manager.Reporting.Workflow_History,
         when Quality_Manager.CLI.Events_Command    => Quality_Manager.Reporting.Event_Stream,
         when Quality_Manager.CLI.Recover_Command   => Quality_Manager.Reporting.Recovery_Status,
         when others => raise Program_Error);
begin
   for Index in 1 .. Ada.Command_Line.Argument_Count loop
      Arguments.Append (Ada.Command_Line.Argument (Index));
   end loop;

   Quality_Manager.CLI.Parse (Arguments, Options, Result);
   if Result.Kind /= Quality_Manager.Results.Success then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Quality_Manager.Results.Message (Result));
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Quality_Manager.CLI.Usage);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   case Options.Command is
      when Quality_Manager.CLI.Help_Command =>
         Ada.Text_IO.Put_Line (Quality_Manager.CLI.Usage);
      when Quality_Manager.CLI.Version_Command =>
         Ada.Text_IO.Put_Line (Quality_Manager.Application_Name & " " & Quality_Manager.Version);
      when Quality_Manager.CLI.Doctor_Command =>
         Quality_Manager.Config.Load
           (To_String (Options.Config_Path), Options.Config_Explicit, Settings, Result);
         if Result.Kind /= Quality_Manager.Results.Success then
            Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Quality_Manager.Results.Message (Result));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
         declare
            Runner   : Quality_Manager.Integrations.Runner.Adapter;
            Response : Quality_Manager.Integrations.JSON_CLI.Response;
         begin
            Quality_Manager.Integrations.Runner.Initialize
              (Runner, To_String (Settings.Model_Runner_Executable));
            Quality_Manager.Integrations.Runner.Capabilities (Runner, Response);
            Ada.Text_IO.Put_Line
              (Quality_Manager.Reporting.Doctor (Settings, Options.Format, Response.Status));
            if Response.Status.Kind /= Quality_Manager.Results.Success then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
         end;
      when Quality_Manager.CLI.Maintenance_Command =>
         begin
            Quality_Manager.Maintenance.Run_Cycle
              (To_String (Options.Project_Selector), Options.Dry_Run);
         exception
            when Error : Quality_Manager.Maintenance.Maintenance_Error =>
               Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (Error));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end;
      when Quality_Manager.CLI.Daemon_Command =>
         loop
            begin
               Quality_Manager.Maintenance.Run_Cycle
                 (To_String (Options.Project_Selector), Options.Dry_Run);
            exception
               when Error : Quality_Manager.Maintenance.Maintenance_Error =>
                  Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (Error));
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  exit;
            end;
            exit when Options.Once;
            delay 60.0;
         end loop;
      when Quality_Manager.CLI.Status_Command
         | Quality_Manager.CLI.Queue_Command
         | Quality_Manager.CLI.Approvals_Command
         | Quality_Manager.CLI.History_Command
         | Quality_Manager.CLI.Events_Command
         | Quality_Manager.CLI.Recover_Command =>
         Quality_Manager.Config.Load
           (To_String (Options.Config_Path), Options.Config_Explicit, Settings, Result);
         if Result.Kind /= Quality_Manager.Results.Success then
            Report_Failure;
            return;
         end if;
         declare
            Store        : Quality_Manager.Storage.Store;
            Close_Result : Quality_Manager.Results.Operation_Result;
            Output       : Unbounded_String;
         begin
            Quality_Manager.Storage.Open
              (Store, To_String (Settings.Coordinator_Database), False, Result);
            if Result.Kind = Quality_Manager.Results.Success then
               Output := To_Unbounded_String
                 (Quality_Manager.Reporting.Operational
                    (Store, View_For (Options.Command), Options.Format, Result));
            end if;
            if Quality_Manager.Storage.Is_Open (Store) then
               Quality_Manager.Storage.Close (Store, Close_Result);
               if Result.Kind = Quality_Manager.Results.Success
                 and then Close_Result.Kind /= Quality_Manager.Results.Success
               then
                  Result := Close_Result;
               end if;
            end if;
            if Result.Kind = Quality_Manager.Results.Success then
               Ada.Text_IO.Put_Line (To_String (Output));
            else
               Report_Failure;
            end if;
         end;
      when Quality_Manager.CLI.Campaign_Create_Command
         | Quality_Manager.CLI.Campaign_Start_Command
         | Quality_Manager.CLI.Campaign_Pause_Command
         | Quality_Manager.CLI.Campaign_Resume_Command
         | Quality_Manager.CLI.Campaign_Reconcile_Command =>
         begin
            case Options.Command is
               when Quality_Manager.CLI.Campaign_Create_Command =>
                  Quality_Manager.Campaigns.Create (To_String (Options.Primary_Value));
               when Quality_Manager.CLI.Campaign_Start_Command =>
                  Quality_Manager.Campaigns.Start (To_String (Options.Primary_Value));
               when Quality_Manager.CLI.Campaign_Pause_Command =>
                  Quality_Manager.Campaigns.Pause (To_String (Options.Primary_Value));
               when Quality_Manager.CLI.Campaign_Resume_Command =>
                  Quality_Manager.Campaigns.Resume (To_String (Options.Primary_Value));
               when Quality_Manager.CLI.Campaign_Reconcile_Command =>
                  Quality_Manager.Campaigns.Reconcile (To_String (Options.Primary_Value));
               when others => null;
            end case;
         exception
            when Error : Quality_Manager.Campaigns.Campaign_Error =>
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (Error));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end;
      when Quality_Manager.CLI.Release_Create_Command
         | Quality_Manager.CLI.Release_Qualify_Command
         | Quality_Manager.CLI.Release_Export_Command =>
         begin
            case Options.Command is
               when Quality_Manager.CLI.Release_Create_Command =>
                  Quality_Manager.Releases.Create
                    (To_String (Options.Primary_Value), To_String (Options.Secondary_Value));
               when Quality_Manager.CLI.Release_Qualify_Command =>
                  Quality_Manager.Releases.Qualify (To_String (Options.Primary_Value));
               when Quality_Manager.CLI.Release_Export_Command =>
                  Quality_Manager.Releases.Export_Evidence
                    (To_String (Options.Primary_Value), To_String (Options.Secondary_Value));
               when others => null;
            end case;
         exception
            when Error : Quality_Manager.Releases.Release_Error =>
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (Error));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end;
      when Quality_Manager.CLI.Approve_Command | Quality_Manager.CLI.Reject_Command =>
         Quality_Manager.Config.Load
           (To_String (Options.Config_Path), Options.Config_Explicit, Settings, Result);
         if Result.Kind /= Quality_Manager.Results.Success then
            Report_Failure;
            return;
         end if;
         declare
            Store        : Quality_Manager.Storage.Store;
            Close_Result : Quality_Manager.Results.Operation_Result;
         begin
            Quality_Manager.Storage.Open
              (Store, To_String (Settings.Coordinator_Database), True, Result);
            if Result.Kind = Quality_Manager.Results.Success then
               Quality_Manager.Approvals.Apply_Decision
                 (Store, To_String (Options.Primary_Value),
                  Options.Command = Quality_Manager.CLI.Approve_Command, Result);
            end if;
            if Quality_Manager.Storage.Is_Open (Store) then
               Quality_Manager.Storage.Close (Store, Close_Result);
               if Result.Kind = Quality_Manager.Results.Success
                 and then Close_Result.Kind /= Quality_Manager.Results.Success
               then
                  Result := Close_Result;
               end if;
            end if;
            if Result.Kind /= Quality_Manager.Results.Success then
               Report_Failure;
            end if;
         end;
   end case;
end Main;
