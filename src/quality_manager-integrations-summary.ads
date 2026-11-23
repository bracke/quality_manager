with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;

--  Adapts read-only Ada Quality Summary reports.
package Quality_Manager.Integrations.Summary is
   --  Public contract for this Quality Manager unit.
   type Adapter is private;
   --  Adapter domain value.
   procedure Initialize (Item : out Adapter; Executable, Database_Path : String);
   --  Perform Initialize.
   --  @param Item Item.
   --  @param Executable Executable.
   --  @param Database_Path Database Path.
   procedure Read_Portfolio (Item : Adapter; Result : out JSON_CLI.Response);
   --  Perform Read Portfolio.
   --  @param Item Item.
   --  @param Result Result.
   procedure Read_Problems (Item : Adapter; Result : out JSON_CLI.Response);
   --  Perform Read Problems.
   --  @param Item Item.
   --  @param Result Result.
   procedure Read_Regressions (Item : Adapter; Result : out JSON_CLI.Response);
   --  Perform Read Regressions.
   --  @param Item Item.
   --  @param Result Result.
   procedure Read_Indicators (Item : Adapter; Result : out JSON_CLI.Response);
   --  Perform Read Indicators.
   --  @param Item Item.
   --  @param Result Result.
   procedure Read_Trends (Item : Adapter; Result : out JSON_CLI.Response);
   --  Perform Read Trends.
   --  @param Item Item.
   --  @param Result Result.
   procedure Read_Project_Status (Item : Adapter; Project : String; Result : out JSON_CLI.Response);
   --  Perform Read Project Status.
   --  @param Item Item.
   --  @param Project Project.
   --  @param Result Result.
private
   type Adapter is record
      Executable    : Ada.Strings.Unbounded.Unbounded_String;
      Database_Path : Ada.Strings.Unbounded.Unbounded_String;
      Environment   : Processes.String_Vectors.Vector;
   end record;
end Quality_Manager.Integrations.Summary;
