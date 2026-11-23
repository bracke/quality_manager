with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;

--  Adapts Improve planning, publication, recovery, and verification.
package Quality_Manager.Integrations.Improve is
   --  Public contract for this Quality Manager unit.
   type Adapter is private;
   --  Adapter domain value.
   procedure Initialize
     (Item : out Adapter; Executable, Config_Path, Quality_Database, State_Database : String);
   --  Perform Initialize.
   --  @param Item Item.
   --  @param Executable Executable.
   --  @param Config_Path Config Path.
   --  @param Quality_Database Quality Database.
   --  @param State_Database State Database.
   procedure Generate_Plan
     (Item    : Adapter;
      Project : String;
      Run     : Natural;
      Result  : out JSON_CLI.Response);
   --  Perform Generate Plan.
   --  @param Item Item.
   --  @param Project Project.
   --  @param Run Run.
   --  @param Result Result.
   procedure Read_Plan
     (Item : Adapter; Plan_Id : String; Revision : Natural; Result : out JSON_CLI.Response);
   --  Perform Read Plan.
   --  @param Item Item.
   --  @param Plan_Id Plan Id.
   --  @param Revision Revision.
   --  @param Result Result.
   procedure Inspect_Approval
     (Item : Adapter; Plan_Id : String; Revision : Positive; Result : out JSON_CLI.Response);
   --  Perform Inspect Approval.
   --  @param Item Item.
   --  @param Plan_Id Plan Id.
   --  @param Revision Revision.
   --  @param Result Result.
   procedure Approve_Exact_Revision
     (Item : Adapter; Plan_Id : String; Revision : Positive; Content_SHA256 : String;
      Result : out JSON_CLI.Response);
   --  Perform Approve Exact Revision.
   --  @param Item Item.
   --  @param Plan_Id Plan Id.
   --  @param Revision Revision.
   --  @param Content_SHA256 Content SHA256.
   --  @param Result Result.
   procedure Preflight_Publication
     (Item : Adapter; Plan_Id : String; Revision : Positive; Task_Id : String;
      Result : out JSON_CLI.Response);
   --  Perform Preflight Publication.
   --  @param Item Item.
   --  @param Plan_Id Plan Id.
   --  @param Revision Revision.
   --  @param Task_Id Task Id.
   --  @param Result Result.
   procedure Publish_Task
     (Item : Adapter; Plan_Id : String; Revision : Positive; Task_Id : String;
      Result : out JSON_CLI.Response);
   --  Perform Publish Task.
   --  @param Item Item.
   --  @param Plan_Id Plan Id.
   --  @param Revision Revision.
   --  @param Task_Id Task Id.
   --  @param Result Result.
   procedure Read_Task_State
     (Item : Adapter; Task_Id : String; Revision : Natural; Result : out JSON_CLI.Response);
   --  Perform Read Task State.
   --  @param Item Item.
   --  @param Task_Id Task Id.
   --  @param Revision Revision.
   --  @param Result Result.
   procedure Read_Plan_State (Item : Adapter; Plan_Id : String; Result : out JSON_CLI.Response);
   --  Perform Read Plan State.
   --  @param Item Item.
   --  @param Plan_Id Plan Id.
   --  @param Result Result.
   procedure Verify_Task
     (Item : Adapter; Task_Id : String; Revision, Run : Positive; Result : out JSON_CLI.Response);
   --  Perform Verify Task.
   --  @param Item Item.
   --  @param Task_Id Task Id.
   --  @param Revision Revision.
   --  @param Run Run.
   --  @param Result Result.
   procedure Verify_Project
     (Item : Adapter; Project : String; Revision, Run : Positive; Result : out JSON_CLI.Response);
   --  Perform Verify Project.
   --  @param Item Item.
   --  @param Project Project.
   --  @param Revision Revision.
   --  @param Run Run.
   --  @param Result Result.
   procedure Recover_Publication (Item : Adapter; Result : out JSON_CLI.Response);
   --  Perform Recover Publication.
   --  @param Item Item.
   --  @param Result Result.
   procedure Export_Audit (Item : Adapter; Plan_Id : String; Result : out JSON_CLI.Response);
   --  Perform Export Audit.
   --  @param Item Item.
   --  @param Plan_Id Plan Id.
   --  @param Result Result.
private
   type Adapter is record
      Executable       : Ada.Strings.Unbounded.Unbounded_String;
      Config_Path      : Ada.Strings.Unbounded.Unbounded_String;
      Quality_Database : Ada.Strings.Unbounded.Unbounded_String;
      State_Database   : Ada.Strings.Unbounded.Unbounded_String;
      Environment      : Processes.String_Vectors.Vector;
   end record;
end Quality_Manager.Integrations.Improve;
