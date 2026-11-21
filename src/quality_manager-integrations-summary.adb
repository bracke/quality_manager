with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Hostkit.Process;

package body Quality_Manager.Integrations.Summary is
   procedure Initialize (Item : out Adapter; Executable, Database_Path : String) is
      Path : Hostkit.UString;
   begin
      Item.Executable := To_Unbounded_String (Executable);
      Item.Database_Path := To_Unbounded_String (Database_Path);
      if Hostkit.Process.Environment_Value ("PATH", Path) then
         Item.Environment.Append (To_Unbounded_String ("PATH=" & To_String (Path)));
      end if;
   end Initialize;

   procedure Invoke (Item : Adapter; Command : String; Extra : String; Result : out JSON_CLI.Response) is
      Args : Processes.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("--database")); Args.Append (Item.Database_Path);
      Args.Append (To_Unbounded_String ("--format")); Args.Append (To_Unbounded_String ("json"));
      Args.Append (To_Unbounded_String (Command));
      if Extra /= "" then Args.Append (To_Unbounded_String (Extra)); end if;
      JSON_CLI.Execute
        (To_String (Item.Executable), Args, "", Item.Environment, JSON_CLI.Summary_Contract,
         1, 300, 16 * 1_024 * 1_024, Result, "report_type", Command);
   end Invoke;
   procedure Read_Portfolio (Item : Adapter; Result : out JSON_CLI.Response) is
   begin Invoke (Item, "summary", "", Result); end Read_Portfolio;
   procedure Read_Problems (Item : Adapter; Result : out JSON_CLI.Response) is
   begin Invoke (Item, "problems", "", Result); end Read_Problems;
   procedure Read_Regressions (Item : Adapter; Result : out JSON_CLI.Response) is
   begin Invoke (Item, "regressions", "", Result); end Read_Regressions;
   procedure Read_Indicators (Item : Adapter; Result : out JSON_CLI.Response) is
   begin Invoke (Item, "indicators", "", Result); end Read_Indicators;
   procedure Read_Trends (Item : Adapter; Result : out JSON_CLI.Response) is
   begin Invoke (Item, "trends", "", Result); end Read_Trends;
   procedure Read_Project_Status (Item : Adapter; Project : String; Result : out JSON_CLI.Response) is
   begin Invoke (Item, "project", Project, Result); end Read_Project_Status;
end Quality_Manager.Integrations.Summary;
