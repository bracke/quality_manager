with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Quality_Manager.Results;

--  Defines strict command-line parsing and output selection.
package Quality_Manager.CLI is
   --  Public contract for this Quality Manager unit.
   package Argument_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);
   --  Argument Vectors container.

   type Command_Kind is
     (Help_Command,
      Version_Command,
      Doctor_Command,
      Maintenance_Command,
      Daemon_Command,
      Status_Command,
      Queue_Command,
      Approvals_Command,
      History_Command,
      Events_Command,
      Recover_Command,
      Reconcile_Assessment_Command,
      Campaign_Create_Command,
      Campaign_Start_Command,
      Campaign_Pause_Command,
      Campaign_Resume_Command,
      Campaign_Reconcile_Command,
      Release_Create_Command,
      Release_Qualify_Command,
      Release_Export_Command,
      Release_Keygen_Command,
      Release_Sign_Command,
      Release_Verify_Command,
      Release_SBOM_Command,
      Approve_Command,
      Reject_Command);
   --  Command Kind values.
   --  @enum Help_Command Help Command.
   --  @enum Version_Command Version Command.
   --  @enum Doctor_Command Doctor Command.
   --  @enum Maintenance_Command Maintenance Command.
   --  @enum Daemon_Command Daemon Command.
   --  @enum Status_Command Status Command.
   --  @enum Queue_Command Queue Command.
   --  @enum Approvals_Command Approvals Command.
   --  @enum History_Command History Command.
   --  @enum Events_Command Events Command.
   --  @enum Recover_Command Recover Command.
   --  @enum Reconcile_Assessment_Command Reconcile Assessment Command.
   --  @enum Campaign_Create_Command Campaign Create Command.
   --  @enum Campaign_Start_Command Campaign Start Command.
   --  @enum Campaign_Pause_Command Campaign Pause Command.
   --  @enum Campaign_Resume_Command Campaign Resume Command.
   --  @enum Campaign_Reconcile_Command Campaign Reconcile Command.
   --  @enum Release_Create_Command Release Create Command.
   --  @enum Release_Qualify_Command Release Qualify Command.
   --  @enum Release_Export_Command Release Export Command.
   --  @enum Release_Keygen_Command Generate a detached-signing keypair.
   --  @enum Release_Sign_Command Sign a release artifact.
   --  @enum Release_Verify_Command Verify a release artifact.
   --  @enum Release_SBOM_Command Generate a CycloneDX SBOM.
   --  @enum Approve_Command Approve Command.
   --  @enum Reject_Command Reject Command.
   type Output_Format is (Terminal_Output, JSON_Output, Markdown_Output);
   --  Output Format values.
   --  @enum Terminal_Output Terminal Output.
   --  @enum JSON_Output JSON Output.
   --  @enum Markdown_Output Markdown Output.

   type Options is record
      Command          : Command_Kind := Help_Command;
      Format           : Output_Format := Terminal_Output;
      Config_Path      : Ada.Strings.Unbounded.Unbounded_String;
      Config_Explicit  : Boolean := False;
      Project_Selector : Ada.Strings.Unbounded.Unbounded_String;
      Primary_Value    : Ada.Strings.Unbounded.Unbounded_String;
      Secondary_Value  : Ada.Strings.Unbounded.Unbounded_String;
      Dry_Run          : Boolean := False;
      Once             : Boolean := False;
   end record;
   --  Options record.
   --  @field Command Command.
   --  @field Format Format.
   --  @field Config_Path Config Path.
   --  @field Config_Explicit Config Explicit.
   --  @field Project_Selector Project Selector.
   --  @field Primary_Value Primary Value.
   --  @field Secondary_Value Secondary Value.
   --  @field Dry_Run Dry Run.
   --  @field Once Once.

   procedure Parse
     (Arguments : Argument_Vectors.Vector;
      Item      : out Options;
      Result    : out Quality_Manager.Results.Operation_Result);
   --  Perform Parse.
   --  @param Arguments Arguments.
   --  @param Item Item.
   --  @param Result Result.

   function Usage return String;
   --  Return Usage.
   --  @return Usage result.
end Quality_Manager.CLI;
