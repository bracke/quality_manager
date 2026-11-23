with Ada.Strings.Unbounded;
with Interfaces;

--  Orders durable work by risk, workflow, age, and identity.
package Quality_Manager.Priorities is
   --  Public contract for this Quality Manager unit.
   type Priority_Class is
     (Critical_Regression,
      Release_Blocker,
      Security_Or_Correctness,
      New_Regression,
      Campaign_Work,
      Long_Standing_Deficiency);
   --  Priority Class values.
   --  @enum Critical_Regression Critical Regression.
   --  @enum Release_Blocker Release Blocker.
   --  @enum Security_Or_Correctness Security Or Correctness.
   --  @enum New_Regression New Regression.
   --  @enum Campaign_Work Campaign Work.
   --  @enum Long_Standing_Deficiency Long Standing Deficiency.

   type Candidate is record
      Work_Id     : Ada.Strings.Unbounded.Unbounded_String;
      Class       : Priority_Class := Long_Standing_Deficiency;
      Eligible_At : Interfaces.Unsigned_64 := 0;
   end record;
   --  Candidate record.
   --  @field Work_Id Work Id.
   --  @field Class Class.
   --  @field Eligible_At Eligible At.

   function Before (Left, Right : Candidate) return Boolean;
   --  Return Before.
   --  @param Left Left.
   --  @param Right Right.
   --  @return Before result.
   function From_Persisted_Priority (Value : Natural) return Priority_Class;
   --  Return From Persisted Priority.
   --  @param Value Value.
   --  @return From Persisted Priority result.
end Quality_Manager.Priorities;
