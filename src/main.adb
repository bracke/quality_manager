with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Quality_Manager;
with Quality_Manager.CLI;
with Quality_Manager.Config;
with Quality_Manager.Reporting;
with Quality_Manager.Results;

procedure Main is
   use type Quality_Manager.Results.Result_Kind;

   Arguments : Quality_Manager.CLI.Argument_Vectors.Vector;
   Options   : Quality_Manager.CLI.Options;
   Settings  : Quality_Manager.Config.Settings;
   Result    : Quality_Manager.Results.Operation_Result;
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
         Ada.Text_IO.Put_Line (Quality_Manager.Reporting.Doctor (Settings, Options.Format));
   end case;
end Main;
