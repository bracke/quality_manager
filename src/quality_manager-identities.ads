with Ada.Strings.Unbounded;
with Interfaces;

--  Defines qualified durable identities and canonical digests.
package Quality_Manager.Identities is
   --  Public contract for this Quality Manager unit.
   subtype Identifier_Text is Ada.Strings.Unbounded.Unbounded_String;
   --  Identifier Text domain value.

   type Project_Key is record
      Quality_Database_Id : Identifier_Text;
      Quality_Project_Id  : Positive;
      Canonical_Path      : Identifier_Text;
   end record;
   --  Project Key record.
   --  @field Quality_Database_Id Quality Database Id.
   --  @field Quality_Project_Id Quality Project Id.
   --  @field Canonical_Path Canonical Path.

   type Assessment_Key is record
      Project : Project_Key;
      Run_Id  : Positive;
   end record;
   --  Assessment Key record.
   --  @field Project Project.
   --  @field Run_Id Run Id.

   type Improve_Task_Key is record
      Plan_Id  : Identifier_Text;
      Revision : Positive;
      Task_Id  : Identifier_Text;
   end record;
   --  Improve Task Key record.
   --  @field Plan_Id Plan Id.
   --  @field Revision Revision.
   --  @field Task_Id Task Id.

   type Native_Task_Key is record
      Project : Project_Key;
      Task_Id : Identifier_Text;
   end record;
   --  Native Task Key record.
   --  @field Project Project.
   --  @field Task_Id Task Id.

   type Operation_Id is new Interfaces.Unsigned_64;
   --  Operation Id domain value.
   type Attempt_Id is new Interfaces.Unsigned_64;
   --  Attempt Id domain value.

   type Field_Kind is (Text_Field, Number_Field);
   --  Field Kind values.
   --  @enum Text_Field Text Field.
   --  @enum Number_Field Number Field.
   type Identity_Field (Kind : Field_Kind := Text_Field) is record
      case Kind is
         when Text_Field =>
            Text : Identifier_Text;
         when Number_Field =>
            Number : Interfaces.Unsigned_64;
      end case;
   end record;
   --  Identity Field record.
   --  @field Kind Field representation discriminator.
   --  @field Text Text field value.
   --  @field Number Numeric field value.

   type Identity_Field_Array is array (Positive range <>) of Identity_Field;
   --  Identity Field Array domain value.

   function Equal (Left, Right : Project_Key) return Boolean;
   --  Return Equal.
   --  @param Left Left.
   --  @param Right Right.
   --  @return Equal result.

   function Text_Value (Value : String) return Identity_Field;
   --  Return Text Value.
   --  @param Value Value.
   --  @return Text Value result.
   function Number_Value (Value : Interfaces.Unsigned_64) return Identity_Field;
   --  Return Number Value.
   --  @param Value Value.
   --  @return Number Value result.

   function Canonical_Digest (Fields : Identity_Field_Array) return String;
   --  Return Canonical Digest.
   --  @param Fields Fields.
   --  @return Canonical Digest result.

   function Operation_Identity
     (Purpose   : String;
      Stable_Id : String) return Operation_Id;
   --  Return Operation Identity.
   --  @param Purpose Purpose.
   --  @param Stable_Id Stable Id.
   --  @return Operation Identity result.

   function Work_Identity
     (Project                 : Project_Key;
      Assessment_Run         : Positive;
      Normalized_Finding_Set : String;
      Workflow_Scope         : String) return String;
   --  Return Work Identity.
   --  @param Project Project.
   --  @param Assessment_Run Assessment Run.
   --  @param Normalized_Finding_Set Normalized Finding Set.
   --  @param Workflow_Scope Workflow Scope.
   --  @return Work Identity result.

   function Global_Remediation_Identity
     (Project                 : Project_Key;
      Assessment_Run         : Positive;
      Normalized_Finding_Set : String) return String;
   --  Return Global Remediation Identity.
   --  @param Project Project.
   --  @param Assessment_Run Assessment Run.
   --  @param Normalized_Finding_Set Normalized Finding Set.
   --  @return Global Remediation Identity result.

   function Dispatch_Identity
     (Work_Identity : String;
      Plan_Id       : String;
      Plan_Revision : Positive;
      Task_Id       : String) return String;
   --  Return Dispatch Identity.
   --  @param Work_Identity Work Identity.
   --  @param Plan_Id Plan Id.
   --  @param Plan_Revision Plan Revision.
   --  @param Task_Id Task Id.
   --  @return Dispatch Identity result.

   function Execution_Identity
     (Dispatch_Identity : String;
      Attempt_Number    : Positive) return String;
   --  Return Execution Identity.
   --  @param Dispatch_Identity Dispatch Identity.
   --  @param Attempt_Number Attempt Number.
   --  @return Execution Identity result.
end Quality_Manager.Identities;
