with Quality_Manager.Results;

package Quality_Manager.Schemas is
   procedure Validate_Versioned_JSON
     (Text             : String;
      Expected_Version : Positive;
      Result           : out Quality_Manager.Results.Operation_Result;
      Discriminator_Name  : String := "";
      Discriminator_Value : String := "");
end Quality_Manager.Schemas;
