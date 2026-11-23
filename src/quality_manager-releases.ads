with Ada.Strings.Unbounded;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Results;
with Quality_Manager.Scheduler;
with Quality_Manager.Verification;

--  Qualifies immutable release candidates and exports evidence.
package Quality_Manager.Releases is
   --  Public contract for this Quality Manager unit.
   Release_Error : exception;
   --  Raised for Release Error.

   type Context is limited private;
   --  Context domain value.

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
   --  Check Results record.
   --  @field Candidate_Commit Candidate Commit.
   --  @field Source_Fingerprint Source Fingerprint.
   --  @field Release_Config_Digest Release Config Digest.
   --  @field Clean_Build Clean Build.
   --  @field Reproducible_Build Reproducible Build.
   --  @field AUnit_Passed AUnit Passed.
   --  @field Proof_Applicable Proof Applicable.
   --  @field GNATprove_Passed GNATprove Passed.
   --  @field Coverage_Basis_Points Coverage Basis Points.
   --  @field Release_Checks_Passed Release Checks Passed.

   type Evidence_References is record
      Improve_Audit       : Ada.Strings.Unbounded.Unbounded_String;
      Native_Audit        : Ada.Strings.Unbounded.Unbounded_String;
      Regression_Evidence : Ada.Strings.Unbounded.Unbounded_String;
      Authorization_Audit : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Evidence References record.
   --  @field Improve_Audit Improve Audit.
   --  @field Native_Audit Native Audit.
   --  @field Regression_Evidence Regression Evidence.
   --  @field Authorization_Audit Authorization Audit.

   type Qualification_Decision is record
      Qualified : Boolean := False;
      Diagnostic : Ada.Strings.Unbounded.Unbounded_String;
      Bundle_Digest : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Qualification Decision record.
   --  @field Qualified Qualified.
   --  @field Diagnostic Diagnostic.
   --  @field Bundle_Digest Bundle Digest.

   procedure Initialize
     (Item  : out Context;
      Store : Quality_Manager.Scheduler.Store_Access);
   --  Perform Initialize.
   --  @param Item Item.
   --  @param Store Store.

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
   --  Perform Create.
   --  @param Item Item.
   --  @param Project Project.
   --  @param Candidate_Commit Candidate Commit.
   --  @param Source_Fingerprint Source Fingerprint.
   --  @param Policy_Digest Policy Digest.
   --  @param Toolchain_Fingerprint Toolchain Fingerprint.
   --  @param Release_Config_Digest Release Config Digest.
   --  @param Release_Id Release Id.
   --  @param Result Result.

   procedure New_Generation
     (Item                  : in out Context;
      Release_Id            : String;
      Candidate_Commit      : String;
      Source_Fingerprint    : String;
      Policy_Digest         : String;
      Toolchain_Fingerprint : String;
      Release_Config_Digest : String;
      Result                : out Quality_Manager.Results.Operation_Result);
   --  Perform New Generation.
   --  @param Item Item.
   --  @param Release_Id Release Id.
   --  @param Candidate_Commit Candidate Commit.
   --  @param Source_Fingerprint Source Fingerprint.
   --  @param Policy_Digest Policy Digest.
   --  @param Toolchain_Fingerprint Toolchain Fingerprint.
   --  @param Release_Config_Digest Release Config Digest.
   --  @param Result Result.

   procedure Evaluate
     (Item       : in out Context;
      Release_Id : String;
      Assessment : Quality_Manager.Verification.Assessment_Evidence;
      Checks     : Check_Results;
      References : Evidence_References;
      Decision   : out Qualification_Decision;
      Result     : out Quality_Manager.Results.Operation_Result);
   --  Perform Evaluate.
   --  @param Item Item.
   --  @param Release_Id Release Id.
   --  @param Assessment Assessment.
   --  @param Checks Checks.
   --  @param References References.
   --  @param Decision Decision.
   --  @param Result Result.

   procedure Qualify_With_Tools
     (Item             : in out Context;
      Quality          : Quality_Manager.Integrations.Quality.Adapter;
      Release_Id       : String;
      Alire_Executable : String;
      Git_Executable   : String;
      Decision         : out Qualification_Decision;
      Result           : out Quality_Manager.Results.Operation_Result);
   --  Perform Qualify With Tools.
   --  @param Item Item.
   --  @param Quality Quality.
   --  @param Release_Id Release Id.
   --  @param Alire_Executable Alire Executable.
   --  @param Git_Executable Git Executable.
   --  @param Decision Decision.
   --  @param Result Result.

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
   --  Perform Run Local Checks.
   --  @param Item Item.
   --  @param Operation Operation.
   --  @param Project_Path Project Path.
   --  @param Candidate_Commit Candidate Commit.
   --  @param Source_Fingerprint Source Fingerprint.
   --  @param Release_Config_Digest Release Config Digest.
   --  @param Coverage_Basis_Points Coverage Basis Points.
   --  @param Proof_Applicable Proof Applicable.
   --  @param Checks Checks.
   --  @param Result Result.

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
   --  Perform Run Local Checks With Tools.
   --  @param Item Item.
   --  @param Operation Operation.
   --  @param Project_Path Project Path.
   --  @param Candidate_Commit Candidate Commit.
   --  @param Source_Fingerprint Source Fingerprint.
   --  @param Release_Config_Digest Release Config Digest.
   --  @param Coverage_Basis_Points Coverage Basis Points.
   --  @param Proof_Applicable Proof Applicable.
   --  @param Alire_Executable Alire Executable.
   --  @param Git_Executable Git Executable.
   --  @param Checks Checks.
   --  @param Result Result.

   procedure Invalidate_If_Changed
     (Item                 : in out Context;
      Release_Id           : String;
      Current_Commit       : String;
      Current_Source       : String;
      Invalidated          : out Boolean;
      Result               : out Quality_Manager.Results.Operation_Result);
   --  Perform Invalidate If Changed.
   --  @param Item Item.
   --  @param Release_Id Release Id.
   --  @param Current_Commit Current Commit.
   --  @param Current_Source Current Source.
   --  @param Invalidated Invalidated.
   --  @param Result Result.

   procedure Export_Evidence
     (Item        : in out Context;
      Release_Id  : String;
      Output_Path : String;
      Result      : out Quality_Manager.Results.Operation_Result);
   --  Perform Export Evidence.
   --  @param Item Item.
   --  @param Release_Id Release Id.
   --  @param Output_Path Output Path.
   --  @param Result Result.

   procedure Create (Project_Selector : String; Profile : String);
   --  Perform Create.
   --  @param Project_Selector Project Selector.
   --  @param Profile Profile.
   procedure Create_Configured
     (Project_Selector : String;
      Profile          : String;
      Config_Path      : String;
      Config_Required  : Boolean);
   --  Perform Create Configured.
   --  @param Project_Selector Project Selector.
   --  @param Profile Profile.
   --  @param Config_Path Config Path.
   --  @param Config_Required Config Required.
   procedure Qualify (Release_Id : String);
   --  Perform Qualify.
   --  @param Release_Id Release Id.
   procedure Qualify_Configured
     (Release_Id      : String;
      Config_Path     : String;
      Config_Required : Boolean);
   --  Perform Qualify Configured.
   --  @param Release_Id Release Id.
   --  @param Config_Path Config Path.
   --  @param Config_Required Config Required.
   procedure Export_Evidence (Release_Id : String; Output_Path : String);
   --  Perform Export Evidence.
   --  @param Release_Id Release Id.
   --  @param Output_Path Output Path.
   procedure Export_Evidence_Configured
     (Release_Id      : String;
      Output_Path     : String;
      Config_Path     : String;
      Config_Required : Boolean);
   --  Perform Export Evidence Configured.
   --  @param Release_Id Release Id.
   --  @param Output_Path Output Path.
   --  @param Config_Path Config Path.
   --  @param Config_Required Config Required.

private
   type Context is limited record
      Database : Quality_Manager.Scheduler.Store_Access;
   end record;
end Quality_Manager.Releases;
