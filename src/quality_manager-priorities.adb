with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Quality_Manager.Priorities is
   use type Interfaces.Unsigned_64;

   function Before (Left, Right : Candidate) return Boolean is
   begin
      if Left.Class /= Right.Class then
         return Priority_Class'Pos (Left.Class) < Priority_Class'Pos (Right.Class);
      elsif Left.Eligible_At /= Right.Eligible_At then
         return Left.Eligible_At < Right.Eligible_At;
      else
         return To_String (Left.Work_Id) < To_String (Right.Work_Id);
      end if;
   end Before;

   function From_Persisted_Priority (Value : Natural) return Priority_Class is
   begin
      case Value is
         when 0 .. 99       => return Long_Standing_Deficiency;
         when 100 .. 199    => return Campaign_Work;
         when 200 .. 299    => return New_Regression;
         when 300 .. 399    => return Security_Or_Correctness;
         when 400 .. 499    => return Release_Blocker;
         when others        => return Critical_Regression;
      end case;
   end From_Persisted_Priority;
end Quality_Manager.Priorities;
