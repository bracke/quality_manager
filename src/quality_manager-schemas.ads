with Quality_Manager.Results;

--  Validates versioned coordinator JSON schemas.
package Quality_Manager.Schemas is
   --  Public contract for this Quality Manager unit.
   procedure Validate_Versioned_JSON
     (Text             : String;
      Expected_Version : Positive;
      Result           : out Quality_Manager.Results.Operation_Result;
      Discriminator_Name  : String := "";
      Discriminator_Value : String := "");
   --  Perform Validate Versioned JSON.
   --  @param Text Text.
   --  @param Expected_Version Expected Version.
   --  @param Result Result.
   --  @param Discriminator_Name Discriminator Name.
   --  @param Discriminator_Value Discriminator Value.
end Quality_Manager.Schemas;
