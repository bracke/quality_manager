with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.JSON_CLI;
with Quality_Manager.Integrations.Processes;

package Quality_Manager.Integrations.Summary is
   type Adapter is private;
   procedure Initialize (Item : out Adapter; Executable, Database_Path : String);
   procedure Read_Portfolio (Item : Adapter; Result : out JSON_CLI.Response);
   procedure Read_Problems (Item : Adapter; Result : out JSON_CLI.Response);
   procedure Read_Regressions (Item : Adapter; Result : out JSON_CLI.Response);
   procedure Read_Indicators (Item : Adapter; Result : out JSON_CLI.Response);
   procedure Read_Trends (Item : Adapter; Result : out JSON_CLI.Response);
   procedure Read_Project_Status (Item : Adapter; Project : String; Result : out JSON_CLI.Response);
private
   type Adapter is record
      Executable    : Ada.Strings.Unbounded.Unbounded_String;
      Database_Path : Ada.Strings.Unbounded.Unbounded_String;
      Environment   : Processes.String_Vectors.Vector;
   end record;
end Quality_Manager.Integrations.Summary;
