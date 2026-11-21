with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Results;

package Quality_Manager.Integrations.Runner is
   type Adapter is private;

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

   procedure Initialize
     (Item              : out Adapter;
      Executable        : String;
      Working_Directory : String := "");

   procedure Capabilities
     (Item   : Adapter;
      Result : out Quality_Manager.Integrations.JSON_CLI.Response);

   procedure Inspect
     (Item         : Adapter;
      Project_Path : String;
      Task_Id      : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);

   procedure Execute
     (Item    : Adapter;
      Request : Execution_Request;
      Result  : out Quality_Manager.Integrations.JSON_CLI.Response);

   procedure Status
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);

   procedure Cancel
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);

   procedure Recover
     (Item         : Adapter;
      Project_Path : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);

   procedure Integrate
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out Quality_Manager.Integrations.JSON_CLI.Response);

   procedure Validate_Capabilities
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Result   : out Quality_Manager.Results.Operation_Result);

   procedure Decode_Snapshot
     (Response : Quality_Manager.Integrations.JSON_CLI.Response;
      Snapshot : out Task_Snapshot;
      Result   : out Quality_Manager.Results.Operation_Result);

   procedure Validate_Execution
     (Snapshot : Task_Snapshot;
      Request  : Execution_Request;
      Result   : out Quality_Manager.Results.Operation_Result);

private
   type Adapter is record
      Executable        : Ada.Strings.Unbounded.Unbounded_String;
      Working_Directory : Ada.Strings.Unbounded.Unbounded_String;
      Environment       : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
   end record;
end Quality_Manager.Integrations.Runner;
