with Quality_Manager.CLI;
with Quality_Manager.Config;
with Quality_Manager.Results;
with Quality_Manager.Storage;

package Quality_Manager.Reporting is
   type Operational_View is
     (Overall_Status,
      Queue_Status,
      Approval_Status,
      Workflow_History,
      Event_Stream,
      Recovery_Status);

   function Doctor
     (Item   : Quality_Manager.Config.Settings;
      Format : Quality_Manager.CLI.Output_Format;
      Runner : Quality_Manager.Results.Operation_Result) return String;

   function Operational
     (Store  : in out Quality_Manager.Storage.Store;
      View   : Operational_View;
      Format : Quality_Manager.CLI.Output_Format;
      Result : out Quality_Manager.Results.Operation_Result) return String;
end Quality_Manager.Reporting;
