with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Quality_Manager.Results;

package Quality_Manager.CLI is
   package Argument_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   type Command_Kind is (Help_Command, Version_Command, Doctor_Command);
   type Output_Format is (Terminal_Output, JSON_Output, Markdown_Output);

   type Options is record
      Command          : Command_Kind := Help_Command;
      Format           : Output_Format := Terminal_Output;
      Config_Path      : Ada.Strings.Unbounded.Unbounded_String;
      Config_Explicit  : Boolean := False;
   end record;

   procedure Parse
     (Arguments : Argument_Vectors.Vector;
      Item      : out Options;
      Result    : out Quality_Manager.Results.Operation_Result);

   function Usage return String;
end Quality_Manager.CLI;
