with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;
with Quality_Manager.Results;

package Quality_Manager.Integrations.Quality is
   type Adapter is private;

   procedure Initialize
     (Item              : out Adapter;
      Executable        : String;
      Database_Path     : String;
      Working_Directory : String := "";
      Policy_Path       : String := "");

   procedure Resolve_Database_Identity
     (Item     : Adapter;
      Identity : out Ada.Strings.Unbounded.Unbounded_String;
      Result   : out Quality_Manager.Results.Operation_Result);

   procedure List_Projects (Item : Adapter; Result : out JSON_CLI.Response);
   procedure Inspect_Project (Item : Adapter; Project : String; Result : out JSON_CLI.Response);
   procedure Plan_Check
     (Item : Adapter; Project, Profile : String; Reuse_Unchanged : Boolean; Result : out JSON_CLI.Response);
   procedure Run_Check
     (Item : Adapter; Project, Profile : String; Reuse_Unchanged : Boolean; Result : out JSON_CLI.Response);
   procedure Read_Assessment (Item : Adapter; Run : Positive; Result : out JSON_CLI.Response);
   procedure Compare (Item : Adapter; Baseline, Current : Positive; Result : out JSON_CLI.Response);
   procedure Check_Environment (Item : Adapter; Project : String; Result : out JSON_CLI.Response);

private
   type Adapter is record
      Executable        : Ada.Strings.Unbounded.Unbounded_String;
      Database_Path     : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Path       : Ada.Strings.Unbounded.Unbounded_String;
      Working_Directory : Ada.Strings.Unbounded.Unbounded_String;
      Environment       : Processes.String_Vectors.Vector;
   end record;
end Quality_Manager.Integrations.Quality;
