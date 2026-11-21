with Quality_Manager.Results;

package Quality_Manager.Schemas is
   procedure Validate_Versioned_JSON
     (Text             : String;
      Expected_Version : Positive;
      Result           : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Schemas;
