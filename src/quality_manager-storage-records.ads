with Quality_Manager.Results;
with Quality_Manager.Storage.Schema;

--  Persists typed coordinator domain records.
package Quality_Manager.Storage.Records is
   --  Public contract for this Quality Manager unit.
   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Project;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Cycle;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Work_Item;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Dispatch;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Attempt;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Approval;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Verification;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Campaign;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Campaign_Target;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Release;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Save.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.
end Quality_Manager.Storage.Records;
