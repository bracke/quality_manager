with Quality_Manager.Results;
with Quality_Manager.Storage.Schema;

package Quality_Manager.Storage.Records is
   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Project;
      Result : out Quality_Manager.Results.Operation_Result);

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Work_Item;
      Result : out Quality_Manager.Results.Operation_Result);

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Dispatch;
      Result : out Quality_Manager.Results.Operation_Result);

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Approval;
      Result : out Quality_Manager.Results.Operation_Result);

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Quality_Manager.Storage.Schema.Verification;
      Result : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Storage.Records;
