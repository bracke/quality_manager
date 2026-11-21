with Quality_Manager.CLI;
with Quality_Manager.Config;

package Quality_Manager.Reporting is
   function Doctor
     (Item   : Quality_Manager.Config.Settings;
      Format : Quality_Manager.CLI.Output_Format) return String;
end Quality_Manager.Reporting;
