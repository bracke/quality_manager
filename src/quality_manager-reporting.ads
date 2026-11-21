with Quality_Manager.CLI;
with Quality_Manager.Config;
with Quality_Manager.Results;

package Quality_Manager.Reporting is
   function Doctor
     (Item   : Quality_Manager.Config.Settings;
      Format : Quality_Manager.CLI.Output_Format;
      Runner : Quality_Manager.Results.Operation_Result) return String;
end Quality_Manager.Reporting;
