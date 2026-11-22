with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;

package Quality_Manager.Integrations.Improve is
   type Adapter is private;
   procedure Initialize
     (Item : out Adapter; Executable, Config_Path, Quality_Database, State_Database : String);
   procedure Generate_Plan
     (Item    : Adapter;
      Project : String;
      Run     : Natural;
      Result  : out JSON_CLI.Response);
   procedure Read_Plan
     (Item : Adapter; Plan_Id : String; Revision : Natural; Result : out JSON_CLI.Response);
   procedure Inspect_Approval
     (Item : Adapter; Plan_Id : String; Revision : Positive; Result : out JSON_CLI.Response);
   procedure Approve_Exact_Revision
     (Item : Adapter; Plan_Id : String; Revision : Positive; Content_SHA256 : String;
      Result : out JSON_CLI.Response);
   procedure Preflight_Publication
     (Item : Adapter; Plan_Id : String; Revision : Positive; Task_Id : String;
      Result : out JSON_CLI.Response);
   procedure Publish_Task
     (Item : Adapter; Plan_Id : String; Revision : Positive; Task_Id : String;
      Result : out JSON_CLI.Response);
   procedure Read_Task_State
     (Item : Adapter; Task_Id : String; Revision : Natural; Result : out JSON_CLI.Response);
   procedure Read_Plan_State (Item : Adapter; Plan_Id : String; Result : out JSON_CLI.Response);
   procedure Verify_Task
     (Item : Adapter; Task_Id : String; Revision, Run : Positive; Result : out JSON_CLI.Response);
   procedure Verify_Project
     (Item : Adapter; Project : String; Revision, Run : Positive; Result : out JSON_CLI.Response);
   procedure Recover_Publication (Item : Adapter; Result : out JSON_CLI.Response);
   procedure Export_Audit (Item : Adapter; Plan_Id : String; Result : out JSON_CLI.Response);
private
   type Adapter is record
      Executable       : Ada.Strings.Unbounded.Unbounded_String;
      Config_Path      : Ada.Strings.Unbounded.Unbounded_String;
      Quality_Database : Ada.Strings.Unbounded.Unbounded_String;
      State_Database   : Ada.Strings.Unbounded.Unbounded_String;
      Environment      : Processes.String_Vectors.Vector;
   end record;
end Quality_Manager.Integrations.Improve;
