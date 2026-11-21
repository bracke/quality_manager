with Ada.Strings.Unbounded;
with Interfaces;

package Quality_Manager.Identities is
   subtype Identifier_Text is Ada.Strings.Unbounded.Unbounded_String;

   type Project_Key is record
      Quality_Database_Id : Identifier_Text;
      Quality_Project_Id  : Positive;
      Canonical_Path      : Identifier_Text;
   end record;

   type Assessment_Key is record
      Project : Project_Key;
      Run_Id  : Positive;
   end record;

   type Improve_Task_Key is record
      Plan_Id  : Identifier_Text;
      Revision : Positive;
      Task_Id  : Identifier_Text;
   end record;

   type Native_Task_Key is record
      Project : Project_Key;
      Task_Id : Identifier_Text;
   end record;

   type Operation_Id is new Interfaces.Unsigned_64;
   type Attempt_Id is new Interfaces.Unsigned_64;

   function Equal (Left, Right : Project_Key) return Boolean;
end Quality_Manager.Identities;
