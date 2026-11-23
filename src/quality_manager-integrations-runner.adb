with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Hostkit.Process;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;

package body Quality_Manager.Integrations.Runner is
   use type Jsonlib.Documents.Value_Kind;
   use type Quality_Manager.Results.Result_Kind;
   use Quality_Manager.Results;

   Schema_Version : constant Positive := 1;
   Output_Limit   : constant Positive := 16 * 1_024 * 1_024;

   function Image (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   procedure Normalize_Error (Result : in out JSON_CLI.Response);

   procedure Initialize
     (Item              : out Adapter;
      Executable        : String;
      Working_Directory : String := "") is
      Path : Hostkit.UString;
   begin
      Item.Executable := To_Unbounded_String (Executable);
      Item.Working_Directory := To_Unbounded_String (Working_Directory);
      if Hostkit.Process.Environment_Value ("PATH", Path) then
         Item.Environment.Append (To_Unbounded_String ("PATH=" & To_String (Path)));
      end if;
   end Initialize;

   procedure Invoke
     (Item          : Adapter;
      Arguments     : Processes.String_Vectors.Vector;
      Expected_Kind : String;
      Result        : out JSON_CLI.Response;
      Deadline      : Natural := 60) is
      Args : Processes.String_Vectors.Vector := Arguments;
   begin
      Args.Append (To_Unbounded_String ("--format"));
      Args.Append (To_Unbounded_String ("json"));
      JSON_CLI.Execute
        (Executable          => To_String (Item.Executable),
         Arguments           => Args,
         Working_Directory   => To_String (Item.Working_Directory),
         Environment         => Item.Environment,
         Contract            => JSON_CLI.Model_Runner_Contract,
         Schema_Version      => Schema_Version,
         Timeout_Seconds     => Deadline,
         Output_Limit        => Output_Limit,
         Result              => Result,
         Discriminator_Name  => "kind",
         Discriminator_Value => Expected_Kind);
      Normalize_Error (Result);
   end Invoke;

   procedure Capabilities (Item : Adapter; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("work"));
      Args.Append (To_Unbounded_String ("capabilities"));
      Invoke (Item, Args, "work-capabilities", Result);
      if Result.Status.Kind = Success then
         Validate_Capabilities (Result, Result.Status);
      end if;
   end Capabilities;

   procedure Inspect
     (Item         : Adapter;
      Project_Path : String;
      Task_Id      : String;
      Result       : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("work"));
      Args.Append (To_Unbounded_String ("inspect"));
      Args.Append (To_Unbounded_String ("--project"));
      Args.Append (To_Unbounded_String (Project_Path));
      Args.Append (To_Unbounded_String ("--task"));
      Args.Append (To_Unbounded_String (Task_Id));
      Invoke (Item, Args, "work-operation", Result);
   end Inspect;

   procedure Execute
     (Item    : Adapter;
      Request : Execution_Request;
      Result  : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("work"));
      Args.Append (To_Unbounded_String ("execute"));
      Args.Append (To_Unbounded_String ("--project"));
      Args.Append (Request.Project_Path);
      Args.Append (To_Unbounded_String ("--task"));
      Args.Append (Request.Task_Id);
      Args.Append (To_Unbounded_String ("--operation-id"));
      Args.Append (Request.Operation_Id);
      Args.Append (To_Unbounded_String ("--expected-task-revision"));
      Args.Append (Request.Expected_Task_Revision);
      Args.Append (To_Unbounded_String ("--expected-project-identity"));
      Args.Append (Request.Expected_Project_Identity);
      Args.Append (To_Unbounded_String ("--expected-source-fingerprint"));
      Args.Append (Request.Expected_Source_Fingerprint);
      Args.Append (To_Unbounded_String ("--execution-policy"));
      Args.Append (Request.Execution_Policy);
      Args.Append (To_Unbounded_String ("--timeout-seconds"));
      Args.Append (To_Unbounded_String (Image (Request.Timeout_Seconds)));
      Args.Append (To_Unbounded_String ("--noninteractive"));
      Invoke (Item, Args, "work-operation", Result, Request.Timeout_Seconds + 30);
   end Execute;

   procedure Operation_Command
     (Item         : Adapter;
      Command      : String;
      Project_Path : String;
      Operation_Id : String;
      Expected_Kind : String;
      Result       : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("work"));
      Args.Append (To_Unbounded_String (Command));
      Args.Append (To_Unbounded_String ("--project"));
      Args.Append (To_Unbounded_String (Project_Path));
      Args.Append (To_Unbounded_String ("--operation-id"));
      Args.Append (To_Unbounded_String (Operation_Id));
      Invoke (Item, Args, Expected_Kind, Result);
   end Operation_Command;

   procedure Status
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out JSON_CLI.Response) is
   begin
      Operation_Command (Item, "status", Project_Path, Operation_Id, "work-operation", Result);
   end Status;

   procedure Cancel
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out JSON_CLI.Response) is
   begin
      Operation_Command (Item, "cancel", Project_Path, Operation_Id, "work-cancellation", Result);
   end Cancel;

   procedure Recover
     (Item         : Adapter;
      Project_Path : String;
      Result       : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("work"));
      Args.Append (To_Unbounded_String ("recover"));
      Args.Append (To_Unbounded_String ("--project"));
      Args.Append (To_Unbounded_String (Project_Path));
      Invoke (Item, Args, "work-recovery", Result);
   end Recover;

   procedure Integrate
     (Item         : Adapter;
      Project_Path : String;
      Operation_Id : String;
      Result       : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("work"));
      Args.Append (To_Unbounded_String ("integrate"));
      Args.Append (To_Unbounded_String ("--project"));
      Args.Append (To_Unbounded_String (Project_Path));
      Args.Append (To_Unbounded_String ("--operation-id"));
      Args.Append (To_Unbounded_String (Operation_Id));
      Args.Append (To_Unbounded_String ("--authorization"));
      Args.Append (To_Unbounded_String ("conflict-free"));
      Invoke (Item, Args, "work-operation", Result);
   end Integrate;

   procedure Parse
     (Text     : String;
      Document : in out Jsonlib.Documents.Document;
      Result   : out Operation_Result) is
      Error : Jsonlib.Errors.Error_Info;
   begin
      Jsonlib.Parsers.Parse
        (Text,
         Document,
         Error,
         (Max_Depth => 64,
          Max_Length => Output_Limit,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Incompatible_Contract,
            "invalid model_runner JSON: " & Jsonlib.Errors.Identifier (Error.Code),
            "qm.runner.json");
      else
         Result := Make_Result (Success);
      end if;
   end Parse;

   procedure Normalize_Error (Result : in out JSON_CLI.Response) is
      Document : Jsonlib.Documents.Document;
      Checked  : Operation_Result;
   begin
      if Result.Status.Kind in Success | Negative_Result
        or else Length (Result.Document) = 0
      then
         return;
      end if;
      Parse (To_String (Result.Document), Document, Checked);
      if Checked.Kind /= Success then
         return;
      end if;
      declare
         Root       : constant Jsonlib.Documents.Node := Document.Root;
         Kind_Node  : constant Jsonlib.Documents.Node := Document.Member (Root, "kind");
         Code_Node  : constant Jsonlib.Documents.Node := Document.Member (Root, "error_code");
         Detail_Node : constant Jsonlib.Documents.Node := Document.Member (Root, "diagnostic");

         function Valid_Error_Document return Boolean is
         begin
            if not Jsonlib.Documents.Is_Present (Kind_Node) then
               return False;
            elsif not Jsonlib.Documents.Is_Present (Code_Node) then
               return False;
            elsif not Jsonlib.Documents.Is_Present (Detail_Node) then
               return False;
            elsif Document.Kind (Kind_Node) /= Jsonlib.Documents.String_Value then
               return False;
            elsif Document.Kind (Code_Node) /= Jsonlib.Documents.String_Value then
               return False;
            elsif Document.Kind (Detail_Node) /= Jsonlib.Documents.String_Value then
               return False;
            else
               return Document.As_String (Kind_Node) = "error";
            end if;
         end Valid_Error_Document;

         function Kind_For (Code : String; Default : Result_Kind) return Result_Kind is
         begin
            if Code = "MR-FRAMEWORK-0011" then return Not_Found;
            elsif Code in "MR-FRAMEWORK-0009" | "MR-FRAMEWORK-0024" then return Not_Ready;
            elsif Code in "MR-FRAMEWORK-0010" | "MR-FRAMEWORK-0021" | "MR-FRAMEWORK-0031" then
               return Temporarily_Unavailable;
            elsif Code = "MR-FRAMEWORK-0012" then return Stale_Evidence;
            elsif Code in "MR-FRAMEWORK-0013" | "MR-FRAMEWORK-0014" then return Integrity_Error;
            elsif Code in "MR-FRAMEWORK-0027" | "MR-FRAMEWORK-0029" |
                          "MR-FRAMEWORK-0030" | "MR-FRAMEWORK-0032"
            then
               return Authorization_Required;
            elsif Code = "MR-FRAMEWORK-0033" then return Negative_Result;
            else return Default;
            end if;
         end Kind_For;
      begin
         if not Valid_Error_Document then
            return;
         end if;
         declare
            Code   : constant String := Document.As_String (Code_Node);
            Detail : constant String := Document.As_String (Detail_Node);
            Kind   : constant Result_Kind := Kind_For (Code, Result.Status.Kind);
         begin
            Result.Status := Make_Result (Kind, Detail, Code);
         end;
      end;
   exception
      when others =>  --  AQ: audited exception boundary
         null;
   end Normalize_Error;

   function Has_Boolean
     (Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Name     : String;
      Value    : Boolean) return Boolean is
      Node : constant Jsonlib.Documents.Node := Document.Member (Root, Name);
   begin
      return Jsonlib.Documents.Is_Present (Node)
        and then Document.Kind (Node) = Jsonlib.Documents.Boolean_Value
        and then Document.As_Boolean (Node) = Value;
   end Has_Boolean;

   function Has_Command
     (Document : Jsonlib.Documents.Document;
      Commands : Jsonlib.Documents.Node;
      Expected : String) return Boolean is
   begin
      for Index in 1 .. Document.Length (Commands) loop
         declare
            Node : constant Jsonlib.Documents.Node := Document.Element (Commands, Index);
         begin
            if Document.Kind (Node) = Jsonlib.Documents.String_Value
              and then Document.As_String (Node) = Expected
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Has_Command;

   function Has_Required_Commands
     (Document : Jsonlib.Documents.Document;
      Commands : Jsonlib.Documents.Node) return Boolean is
   begin
      return Has_Command (Document, Commands, "inspect")
        and then Has_Command (Document, Commands, "execute")
        and then Has_Command (Document, Commands, "status")
        and then Has_Command (Document, Commands, "cancel")
        and then Has_Command (Document, Commands, "recover")
        and then Has_Command (Document, Commands, "integrate");
   end Has_Required_Commands;

   procedure Validate_Capabilities
     (Response : JSON_CLI.Response;
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
   begin
      if Response.Status.Kind /= Success then
         Result := Response.Status;
         return;
      end if;
      Parse (To_String (Response.Document), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      declare
         Root     : constant Jsonlib.Documents.Node := Document.Root;
         Commands : constant Jsonlib.Documents.Node := Document.Member (Root, "commands");
      begin
         if not Has_Boolean (Document, Root, "noninteractive", True)
           or else not Has_Boolean (Document, Root, "idempotent_operations", True)
           or else not Has_Boolean (Document, Root, "operation_lookup", True)
           or else not Has_Boolean (Document, Root, "workspace_isolation", True)
           or else not Has_Boolean (Document, Root, "semantic_conflict_resolution", False)
           or else not Jsonlib.Documents.Is_Present (Commands)
           or else Document.Kind (Commands) /= Jsonlib.Documents.Array_Value
         then
            Result := Make_Result
              (Incompatible_Contract,
               "model_runner lacks required autonomous work capabilities",
               "qm.runner.capabilities");
            return;
         end if;
         if not Has_Required_Commands (Document, Commands) then
            Result := Make_Result
              (Incompatible_Contract,
               "model_runner lacks one or more required work commands",
               "qm.runner.command-missing");
            return;
         end if;
      end;
      Result := Make_Result (Success);
   exception
      when others =>  --  AQ: audited exception boundary
         Result := Make_Result
           (Incompatible_Contract, "invalid model_runner capabilities document", "qm.runner.capabilities");
   end Validate_Capabilities;

   function Required_String
     (Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Unbounded_String) return Boolean is
      Node : constant Jsonlib.Documents.Node := Document.Member (Root, Name);
   begin
      if not Jsonlib.Documents.Is_Present (Node)
        or else Document.Kind (Node) /= Jsonlib.Documents.String_Value
      then
         Value := Null_Unbounded_String;
         return False;
      end if;
      Value := To_Unbounded_String (Document.As_String (Node));
      return True;
   end Required_String;

   procedure Read_Snapshot_Field
     (Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Name     : String;
      Value    : out Unbounded_String;
      Complete : in out Boolean) is
   begin
      if not Required_String (Document, Root, Name, Value) then
         Complete := False;
      end if;
   end Read_Snapshot_Field;

   procedure Read_Snapshot_Fields
     (Document : Jsonlib.Documents.Document;
      Root     : Jsonlib.Documents.Node;
      Snapshot : in out Task_Snapshot;
      State    : out Unbounded_String;
      Complete : out Boolean) is
   begin
      Complete := True;
      Read_Snapshot_Field (Document, Root, "operation_id", Snapshot.Operation_Id, Complete);
      Read_Snapshot_Field (Document, Root, "project_identity", Snapshot.Project_Identity, Complete);
      Read_Snapshot_Field (Document, Root, "source_fingerprint", Snapshot.Source_Fingerprint, Complete);
      Read_Snapshot_Field (Document, Root, "task_id", Snapshot.Task_Id, Complete);
      Read_Snapshot_Field (Document, Root, "task_revision", Snapshot.Task_Revision, Complete);
      Read_Snapshot_Field
        (Document, Root, "effective_task_revision", Snapshot.Effective_Task_Revision, Complete);
      Read_Snapshot_Field (Document, Root, "execution_policy", Snapshot.Execution_Policy, Complete);
      Read_Snapshot_Field
        (Document, Root, "execution_generation", Snapshot.Execution_Generation, Complete);
      Read_Snapshot_Field (Document, Root, "execution_state", State, Complete);
      Read_Snapshot_Field (Document, Root, "native_task_state", Snapshot.Native_Task_State, Complete);
      Read_Snapshot_Field (Document, Root, "core_state", Snapshot.Core_State, Complete);
      Read_Snapshot_Field (Document, Root, "workspace_id", Snapshot.Workspace_Id, Complete);
      Read_Snapshot_Field (Document, Root, "workspace_state", Snapshot.Workspace_State, Complete);
      Read_Snapshot_Field (Document, Root, "result", Snapshot.Native_Result, Complete);
      Read_Snapshot_Field (Document, Root, "audit_reference", Snapshot.Audit_Reference, Complete);
   end Read_Snapshot_Fields;

   procedure Decode_State
     (Text   : String;
      State  : out Execution_State;
      Result : out Operation_Result) is
   begin
      if Text = "not_ready" then State := Not_Ready_State;
      elsif Text = "ready" then State := Ready_State;
      elsif Text = "executing" then State := Executing_State;
      elsif Text = "blocked" then State := Blocked_State;
      elsif Text = "awaiting_integration" then State := Awaiting_Integration_State;
      elsif Text = "verifying" then State := Verifying_State;
      elsif Text = "completed" then State := Completed_State;
      elsif Text = "failed" then State := Failed_State;
      elsif Text = "cancelled" then State := Cancelled_State;
      else
         Result := Make_Result
           (Incompatible_Contract,
            "unknown model_runner execution state: " & Text,
            "qm.runner.state-unknown");
         return;
      end if;
      Result := Make_Result (Success);
   end Decode_State;

   procedure Decode_Snapshot
     (Response : JSON_CLI.Response;
      Snapshot : out Task_Snapshot;
      Result   : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      State    : Unbounded_String;
      Ready    : Jsonlib.Documents.Node;
      Complete : Boolean;
   begin
      Snapshot := (others => <>);
      if Response.Status.Kind not in Success | Negative_Result then
         Result := Response.Status;
         return;
      end if;
      Parse (To_String (Response.Document), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      declare
         Root : constant Jsonlib.Documents.Node := Document.Root;
      begin
         Ready := Document.Member (Root, "ready");
         Read_Snapshot_Fields (Document, Root, Snapshot, State, Complete);
         if not Jsonlib.Documents.Is_Present (Ready) then
            Complete := False;
         elsif Document.Kind (Ready) /= Jsonlib.Documents.Boolean_Value then
            Complete := False;
         end if;
         if not Complete then
            Result := Make_Result
              (Incompatible_Contract, "model_runner work snapshot is incomplete", "qm.runner.snapshot");
            return;
         end if;
         Snapshot.Ready := Document.As_Boolean (Ready);
      end;

      Decode_State (To_String (State), Snapshot.State, Result);
   exception
      when others =>  --  AQ: audited exception boundary
         Result := Make_Result
           (Incompatible_Contract, "invalid model_runner work snapshot", "qm.runner.snapshot");
   end Decode_Snapshot;

   procedure Validate_Execution
     (Snapshot : Task_Snapshot;
      Request  : Execution_Request;
      Result   : out Operation_Result) is
   begin
      if Snapshot.Operation_Id /= Request.Operation_Id then
         Result := Make_Result (Integrity_Error, "operation identity mismatch", "qm.runner.operation");
      elsif Snapshot.Task_Id /= Request.Task_Id then
         Result := Make_Result (Integrity_Error, "native task identity mismatch", "qm.runner.task");
      elsif Snapshot.Task_Revision /= Request.Expected_Task_Revision then
         Result := Make_Result (Stale_Evidence, "native task revision changed", "qm.runner.task-revision");
      elsif Snapshot.Project_Identity /= Request.Expected_Project_Identity then
         Result := Make_Result (Integrity_Error, "project identity mismatch", "qm.runner.project");
      elsif Snapshot.Source_Fingerprint /= Request.Expected_Source_Fingerprint then
         Result := Make_Result (Stale_Evidence, "source fingerprint changed", "qm.runner.source");
      elsif Snapshot.Execution_Policy /= Request.Execution_Policy then
         Result := Make_Result (Authorization_Required, "execution policy changed", "qm.runner.policy");
      else
         Result := Make_Result (Success);
      end if;
   end Validate_Execution;
end Quality_Manager.Integrations.Runner;
