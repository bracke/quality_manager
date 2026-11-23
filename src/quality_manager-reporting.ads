with Quality_Manager.CLI;
with Quality_Manager.Config;
with Quality_Manager.Results;
with Quality_Manager.Storage;

--  Renders operational coordinator status and history.
package Quality_Manager.Reporting is
   --  Public contract for this Quality Manager unit.
   type Operational_View is
     (Overall_Status,
      Queue_Status,
      Approval_Status,
      Workflow_History,
      Event_Stream,
      Recovery_Status);
   --  Operational View values.
   --  @enum Overall_Status Overall Status.
   --  @enum Queue_Status Queue Status.
   --  @enum Approval_Status Approval Status.
   --  @enum Workflow_History Workflow History.
   --  @enum Event_Stream Event Stream.
   --  @enum Recovery_Status Recovery Status.

   function Doctor
     (Item   : Quality_Manager.Config.Settings;
      Format : Quality_Manager.CLI.Output_Format;
      Runner : Quality_Manager.Results.Operation_Result) return String;
   --  Return Doctor.
   --  @param Item Item.
   --  @param Format Format.
   --  @param Runner Runner.
   --  @return Doctor result.

   function Operational
     (Store  : in out Quality_Manager.Storage.Store;
      View   : Operational_View;
      Format : Quality_Manager.CLI.Output_Format;
      Result : out Quality_Manager.Results.Operation_Result) return String;
   --  Return Operational.
   --  @param Store Store.
   --  @param View View.
   --  @param Format Format.
   --  @param Result Result.
   --  @return Operational result.
end Quality_Manager.Reporting;
