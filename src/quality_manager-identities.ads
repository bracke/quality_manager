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

   type Field_Kind is (Text_Field, Number_Field);
   type Identity_Field (Kind : Field_Kind := Text_Field) is record
      case Kind is
         when Text_Field =>
            Text : Identifier_Text;
         when Number_Field =>
            Number : Interfaces.Unsigned_64;
      end case;
   end record;

   type Identity_Field_Array is array (Positive range <>) of Identity_Field;

   function Equal (Left, Right : Project_Key) return Boolean;

   function Text_Value (Value : String) return Identity_Field;
   function Number_Value (Value : Interfaces.Unsigned_64) return Identity_Field;

   function Canonical_Digest (Fields : Identity_Field_Array) return String;

   function Operation_Identity
     (Purpose   : String;
      Stable_Id : String) return Operation_Id;

   function Work_Identity
     (Project                 : Project_Key;
      Assessment_Run         : Positive;
      Normalized_Finding_Set : String;
      Workflow_Scope         : String) return String;

   function Global_Remediation_Identity
     (Project                 : Project_Key;
      Assessment_Run         : Positive;
      Normalized_Finding_Set : String) return String;

   function Dispatch_Identity
     (Work_Identity : String;
      Plan_Id       : String;
      Plan_Revision : Positive;
      Task_Id       : String) return String;

   function Execution_Identity
     (Dispatch_Identity : String;
      Attempt_Number    : Positive) return String;
end Quality_Manager.Identities;
