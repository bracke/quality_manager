with Ada.Strings.Unbounded;
with Interfaces;

package Quality_Manager.Priorities is
   type Priority_Class is
     (Critical_Regression,
      Release_Blocker,
      Security_Or_Correctness,
      New_Regression,
      Campaign_Work,
      Long_Standing_Deficiency);

   type Candidate is record
      Work_Id     : Ada.Strings.Unbounded.Unbounded_String;
      Class       : Priority_Class := Long_Standing_Deficiency;
      Eligible_At : Interfaces.Unsigned_64 := 0;
   end record;

   function Before (Left, Right : Candidate) return Boolean;
   function From_Persisted_Priority (Value : Natural) return Priority_Class;
end Quality_Manager.Priorities;
