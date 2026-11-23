with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Results;

--  Adapts durable headless model_runner work operations.
package Quality_Manager.Integrations.Runner is
   --  Public contract for this Quality Manager unit.
   type Adapter is private;
   --  Adapter domain value.

   type Execution_State is
     (Not_Ready_State,
      Ready_State,
      Executing_State,
      Blocked_State,
      Awaiting_Integration_State,
      Verifying_State,
      Completed_State,
      Failed_State,
      Cancelled_State);
   --  Execution State values.
   --  @enum Not_Ready_State Not Ready State.
   --  @enum Ready_State Ready State.
   --  @enum Executing_State Executing State.
   --  @enum Blocked_State Blocked State.
   --  @enum Awaiting_Integration_State Awaiting Integration State.
   --  @enum Verifying_State Verifying State.
   --  @enum Completed_State Completed State.
   --  @enum Failed_State Failed State.
   --  @enum Cancelled_State Cancelled State.

   type Execution_Request is record
      Project_Path                : Ada.Strings.Unbounded.Unbounded_String;
      Task_Id                     : Ada.Strings.Unbounded.Unbounded_String;
      Operation_Id                : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Task_Revision      : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Project_Identity   : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Source_Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
      Execution_Policy            : Ada.Strings.Unbounded.Unbounded_String;
      Timeout_Seconds              : Positive := 3_600;
   end record;
   --  Execution Request record.
   --  @field Project_Path Project Path.
   --  @field Task_Id Task Id.
   --  @field Operation_Id Operation Id.
   --  @field Expected_Task_Revision Expected Task Revision.
   --  @field Expected_Project_Identity Expected Project Identity.
   --  @field Expected_Source_Fingerprint Expected Source Fingerprint.
   --  @field Execution_Policy Execution Policy.
   --  @field Timeout_Seconds Timeout Seconds.

   type Task_Snapshot is record
      Operation_Id              : Ada.Strings.Unbounded.Unbounded_String;
      Project_Identity          : Ada.Strings.Unbounded.Unbounded_String;
      Source_Fingerprint        : Ada.Strings.Unbounded.Unbounded_String;
      Task_Id                   : Ada.Strings.Unbounded.Unbounded_String;
      Task_Revision             : Ada.Strings.Unbounded.Unbounded_String;
      Effective_Task_Revision   : Ada.Strings.Unbounded.Unbounded_String;
      Execution_Policy          : Ada.Strings.Unbounded.Unbounded_String;
      Execution_Generation      : Ada.Strings.Unbounded.Unbounded_String;
      State                     : Execution_State := Not_Ready_State;
      Native_Task_State         : Ada.Strings.Unbounded.Unbounded_String;
      Core_State                : Ada.Strings.Unbounded.Unbounded_String;
      Ready                     : Boolean := False;
      Workspace_Id              : Ada.Strings.Unbounded.Unbounded_String;
      Workspace_State           : Ada.Strings.Unbounded.Unbounded_String;
      Native_Result             : Ada.Strings.Unbounded.Unbounded_String;
      Audit_Reference           : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Task Snapshot record.
   --  @field Operation_Id Operation Id.
   --  @field Project_Identity Project Identity.
   --  @field Source_Fingerprint Source Fingerprint.
   --  @field Task_Id Task Id.
   --  @field Task_Revision Task Revision.
   --  @field Effective_Task_Revision Effective Task Revision.
   --  @field Execution_Policy Execution Policy.
   --  @field Execution_Generation Execution Generation.
   --  @field State State.
   --  @field Native_Task_State Native Task State.
   --  @field Core_State Core State.
   --  @field Ready Ready.
   --  @field Workspace_Id Workspace Id.
   --  @field Workspace_State Workspace State.
   --  @field Native_Result Native Result.
   --  @field Audit_Reference Audit Reference.

   procedure Initialize
     (Item              : out Adapter;
      Executable        : String;
      Working_Directory : String := "");
   --  Perform Initialize.
   --  @param Item Item.
   --  @param Executable Executable.
   --  @param Working_Directory Working Directory.

   procedure Capabilities
     (Item   : Adapter;
      Result : out Quality_Manager.Integrations.JSON_CLI.Response);
   --  Perform Capabilities.
   --  @param Item Item.
   --  @param Result Result.

   procedure Inspect
     (Item         : Adapter;
      Project_Path : String;
      Task_Id      : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);
   --  Perform Inspect.
   --  @param Item Item.
   --  @param Project_Path Project Path.
   --  @param Task_Id Task Id.
   --  @param Result Result.

   procedure Execute
     (Item    : Adapter;
      Request : Execution_Request;
      Result  : out Quality_Manager.Integrations.JSON_CLI.Response);
   --  Perform Execute.
   --  @param Item Item.
   --  @param Request Request.
   --  @param Result Result.

   procedure Status
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);
   --  Perform Status.
   --  @param Item Item.
   --  @param Project_Path Project Path.
   --  @param Operation_Id Operation Id.
   --  @param Result Result.

   procedure Cancel
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);
   --  Perform Cancel.
   --  @param Item Item.
   --  @param Project_Path Project Path.
   --  @param Operation_Id Operation Id.
   --  @param Result Result.

   procedure Recover
     (Item         : Adapter;
      Project_Path : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);
   --  Perform Recover.
   --  @param Item Item.
   --  @param Project_Path Project Path.
   --  @param Result Result.

   procedure Integrate
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);
   --  Perform Integrate.
   --  @param Item Item.
   --  @param Project_Path Project Path.
   --  @param Operation_Id Operation Id.
   --  @param Result Result.

   procedure Validate_Capabilities
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Validate Capabilities.
   --  @param Response Response.
   --  @param Result Result.

   procedure Decode_Snapshot
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Snapshot : out Task_Snapshot;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Decode Snapshot.
   --  @param Response Response.
   --  @param Snapshot Snapshot.
   --  @param Result Result.

   procedure Validate_Execution
     (Snapshot : Task_Snapshot;
      Request  : Execution_Request;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Validate Execution.
   --  @param Snapshot Snapshot.
   --  @param Request Request.
   --  @param Result Result.

private
   type Adapter is record
      Executable        : Ada.Strings.Unbounded.Unbounded_String;
      Working_Directory : Ada.Strings.Unbounded.Unbounded_String;
      Environment       : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
   end record;
end Quality_Manager.Integrations.Runner;
