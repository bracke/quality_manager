with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Results;

--  Adapts Ada Quality inventory, assessment, and comparison operations.
package Quality_Manager.Integrations.Quality is
   --  Public contract for this Quality Manager unit.
   type Adapter is private;
   --  Adapter domain value.

   procedure Initialize
     (Item              : out Adapter;
      Executable        : String;
      Database_Path     : String;
      Working_Directory : String := "";
      Policy_Path       : String := "");
   --  Perform Initialize.
   --  @param Item Item.
   --  @param Executable Executable.
   --  @param Database_Path Database Path.
   --  @param Working_Directory Working Directory.
   --  @param Policy_Path Policy Path.

   procedure Resolve_Database_Identity
     (Item     : Adapter;
      Identity : out Ada.Strings.Unbounded.Unbounded_String;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Resolve Database Identity.
   --  @param Item Item.
   --  @param Identity Identity.
   --  @param Result Result.

   procedure List_Projects (Item : Adapter; Result : out JSON_CLI.Response);
   --  Perform List Projects.
   --  @param Item Item.
   --  @param Result Result.
   procedure Inspect_Project (Item : Adapter; Project : String; Result : out JSON_CLI.Response);
   --  Perform Inspect Project.
   --  @param Item Item.
   --  @param Project Project.
   --  @param Result Result.
   procedure Plan_Check
     (Item : Adapter; Project, Profile : String; Reuse_Unchanged : Boolean; Result : out JSON_CLI.Response);
   --  Perform Plan Check.
   --  @param Item Item.
   --  @param Project Project.
   --  @param Profile Profile.
   --  @param Reuse_Unchanged Reuse Unchanged.
   --  @param Result Result.
   procedure Run_Check
     (Item : Adapter; Project, Profile : String; Reuse_Unchanged : Boolean; Result : out JSON_CLI.Response);
   --  Perform Run Check.
   --  @param Item Item.
   --  @param Project Project.
   --  @param Profile Profile.
   --  @param Reuse_Unchanged Reuse Unchanged.
   --  @param Result Result.
   procedure Read_Assessment (Item : Adapter; Run : Positive; Result : out JSON_CLI.Response);
   --  Perform Read Assessment.
   --  @param Item Item.
   --  @param Run Run.
   --  @param Result Result.
   procedure Compare (Item : Adapter; Baseline, Current : Positive; Result : out JSON_CLI.Response);
   --  Perform Compare.
   --  @param Item Item.
   --  @param Baseline Baseline.
   --  @param Current Current.
   --  @param Result Result.
   procedure Check_Environment (Item : Adapter; Project : String; Result : out JSON_CLI.Response);
   --  Perform Check Environment.
   --  @param Item Item.
   --  @param Project Project.
   --  @param Result Result.

private
   type Adapter is record
      Executable        : Ada.Strings.Unbounded.Unbounded_String;
      Database_Path     : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Path       : Ada.Strings.Unbounded.Unbounded_String;
      Working_Directory : Ada.Strings.Unbounded.Unbounded_String;
      Environment       : Processes.String_Vectors.Vector;
   end record;
end Quality_Manager.Integrations.Quality;
