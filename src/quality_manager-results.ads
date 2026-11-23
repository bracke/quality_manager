with Ada.Strings.Bounded;
with Quality_Manager.Identities;

--  Defines normalized integration results and diagnostics.
package Quality_Manager.Results is
   --  Public contract for this Quality Manager unit.
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
   --  Result Kind values.
   --  @enum Success Success.
   --  @enum Negative_Result Negative Result.
   --  @enum Invalid_Request Invalid Request.
   --  @enum Not_Found Not Found.
   --  @enum Not_Ready Not Ready.
   --  @enum Authorization_Required Authorization Required.
   --  @enum Stale_Evidence Stale Evidence.
   --  @enum Incompatible_Contract Incompatible Contract.
   --  @enum Temporarily_Unavailable Temporarily Unavailable.
   --  @enum Execution_Error Execution Error.
   --  @enum Integrity_Error Integrity Error.
   --  @enum Interrupted Interrupted.

   Maximum_Diagnostic_Length : constant := 2_048;
   --  Maximum Diagnostic Length.

   package Diagnostic_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Maximum_Diagnostic_Length);
   --  Diagnostic Strings container.

   subtype Diagnostic_Text is Diagnostic_Strings.Bounded_String;
   --  Diagnostic Text domain value.

   type Operation_Result is record
      Kind              : Result_Kind := Success;
      Upstream_Code     : Diagnostic_Text;
      Diagnostic        : Diagnostic_Text;
      Has_Operation_Id  : Boolean := False;
      Operation         : Quality_Manager.Identities.Operation_Id := 0;
   end record;
   --  Operation Result record.
   --  @field Kind Kind.
   --  @field Upstream_Code Upstream Code.
   --  @field Diagnostic Diagnostic.
   --  @field Has_Operation_Id Has Operation Id.
   --  @field Operation Operation.

   function Make_Result
     (Kind          : Result_Kind;
      Diagnostic    : String := "";
      Upstream_Code : String := "") return Operation_Result;
   --  Return Make Result.
   --  @param Kind Kind.
   --  @param Diagnostic Diagnostic.
   --  @param Upstream_Code Upstream Code.
   --  @return Make Result result.

   function Message (Item : Operation_Result) return String;
   --  Return Message.
   --  @param Item Item.
   --  @return Message result.
end Quality_Manager.Results;
