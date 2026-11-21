with Ada.Strings.Bounded;
with Quality_Manager.Identities;

package Quality_Manager.Results is
   type Result_Kind is
     (Success,
      Negative_Result,
      Invalid_Request,
      Not_Found,
      Not_Ready,
      Authorization_Required,
      Stale_Evidence,
      Incompatible_Contract,
      Temporarily_Unavailable,
      Execution_Error,
      Integrity_Error,
      Interrupted);

   Maximum_Diagnostic_Length : constant := 2_048;

   package Diagnostic_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Maximum_Diagnostic_Length);

   subtype Diagnostic_Text is Diagnostic_Strings.Bounded_String;

   type Operation_Result is record
      Kind              : Result_Kind := Success;
      Upstream_Code     : Diagnostic_Text;
      Diagnostic        : Diagnostic_Text;
      Has_Operation_Id  : Boolean := False;
      Operation         : Quality_Manager.Identities.Operation_Id := 0;
   end record;

   function Make_Result
     (Kind          : Result_Kind;
      Diagnostic    : String := "";
      Upstream_Code : String := "") return Operation_Result;

   function Message (Item : Operation_Result) return String;
end Quality_Manager.Results;
