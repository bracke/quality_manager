with Ada.Strings.Unbounded;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Results;
with Quality_Manager.Scheduler;
with Quality_Manager.Verification;

package Quality_Manager.Releases is
   Release_Error : exception;

   type Context is limited private;

   type Check_Results is record
      Candidate_Commit       : Ada.Strings.Unbounded.Unbounded_String;
      Source_Fingerprint     : Ada.Strings.Unbounded.Unbounded_String;
      Release_Config_Digest  : Ada.Strings.Unbounded.Unbounded_String;
      Clean_Build            : Boolean := False;
      Reproducible_Build     : Boolean := False;
      AUnit_Passed           : Boolean := False;
      Proof_Applicable       : Boolean := False;
      GNATprove_Passed       : Boolean := False;
      Coverage_Basis_Points  : Natural := 0;
      Release_Checks_Passed  : Boolean := False;
   end record;

   type Evidence_References is record
      Improve_Audit       : Ada.Strings.Unbounded.Unbounded_String;
      Native_Audit        : Ada.Strings.Unbounded.Unbounded_String;
      Regression_Evidence : Ada.Strings.Unbounded.Unbounded_String;
      Authorization_Audit : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Qualification_Decision is record
      Qualified : Boolean := False;
      Diagnostic : Ada.Strings.Unbounded.Unbounded_String;
      Bundle_Digest : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   procedure Initialize
     (Item  : out Context;
      Store : Quality_Manager.Scheduler.Store_Access);

   procedure Create
     (Item                  : in out Context;
      Project               : Quality_Manager.Identities.Project_Key;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Policy_Digest         : String;
      Toolchain_Fingerprint : String;
      Release_Config_Digest : String;
      Release_Id            : out Ada.Strings.Unbounded.Unbounded_String;
      Result                : out Quality_Manager.Results.Operation_Result);

   procedure New_Generation
     (Item                  : in out Context;
      Release_Id            : String;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Policy_Digest         : String;
      Toolchain_Fingerprint : String;
      Release_Config_Digest : String;
      Result                : out Quality_Manager.Results.Operation_Result);

   procedure Evaluate
     (Item       : in out Context;
      Release_Id : String;
      Assessment : Quality_Manager.Verification.Assessment_Evidence;
      Checks     : Check_Results;
      References : Evidence_References;
      Decision   : out Qualification_Decision;
      Result     : out Quality_Manager.Results.Operation_Result);

   procedure Qualify_With_Tools
     (Item             : in out Context;
      Quality          : Quality_Manager.Integrations.Quality.Adapter;
      Release_Id       : String;
      Alire_Executable : String;
      Git_Executable   : String;
      Decision         : out Qualification_Decision;
      Result           : out Quality_Manager.Results.Operation_Result);

   procedure Run_Local_Checks
     (Item                  : in out Context;
      Operation             : Quality_Manager.Identities.Operation_Id;
      Project_Path          : String;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Release_Config_Digest : String;
      Coverage_Basis_Points : Natural;
      Proof_Applicable      : Boolean;
      Checks                : out Check_Results;
      Result                : out Quality_Manager.Results.Operation_Result);

   procedure Run_Local_Checks_With_Tools
     (Item                  : in out Context;
      Operation             : Quality_Manager.Identities.Operation_Id;
      Project_Path          : String;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Release_Config_Digest : String;
      Coverage_Basis_Points : Natural;
      Proof_Applicable      : Boolean;
      Alire_Executable      : String;
      Git_Executable        : String;
      Checks                : out Check_Results;
      Result                : out Quality_Manager.Results.Operation_Result);

   procedure Invalidate_If_Changed
     (Item                 : in out Context;
      Release_Id           : String;
      Current_Commit       : String;
      Current_Source       : String;
      Invalidated          : out Boolean;
      Result               : out Quality_Manager.Results.Operation_Result);

   procedure Export_Evidence
     (Item        : in out Context;
      Release_Id  : String;
      Output_Path : String;
      Result      : out Quality_Manager.Results.Operation_Result);

   procedure Create (Project_Selector : String; Profile : String);
   procedure Create_Configured
     (Project_Selector : String;
      Profile          : String;
      Config_Path      : String;
      Config_Required  : Boolean);
   procedure Qualify (Release_Id : String);
   procedure Qualify_Configured
     (Release_Id      : String;
      Config_Path     : String;
      Config_Required : Boolean);
   procedure Export_Evidence (Release_Id : String; Output_Path : String);
   procedure Export_Evidence_Configured
     (Release_Id      : String;
      Output_Path     : String;
      Config_Path     : String;
      Config_Required : Boolean);

private
   type Context is limited record
      Database : Quality_Manager.Scheduler.Store_Access;
   end record;
end Quality_Manager.Releases;
