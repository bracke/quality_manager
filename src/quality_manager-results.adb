package body Quality_Manager.Results is
   use Diagnostic_Strings;

   function Bounded (Item : String) return Diagnostic_Text is
   begin
      if Item'Length <= Maximum_Diagnostic_Length then
         return To_Bounded_String (Item);
      else
         return To_Bounded_String
           (Item (Item'First .. Item'First + Maximum_Diagnostic_Length - 1));
      end if;
   end Bounded;

   function Make_Result
     (Kind          : Result_Kind;
      Diagnostic    : String := "";
      Upstream_Code : String := "") return Operation_Result is
   begin
      return
        (Kind              => Kind,
         Upstream_Code     => Bounded (Upstream_Code),
         Diagnostic        => Bounded (Diagnostic),
         Has_Operation_Id  => False,
         Operation         => 0);
   end Make_Result;

   function Message (Item : Operation_Result) return String is
     (To_String (Item.Diagnostic));
end Quality_Manager.Results;
