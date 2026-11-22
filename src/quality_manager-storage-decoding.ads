with Quality_Manager.Results;
with Quality_Manager.Storage.Schema;

package Quality_Manager.Storage.Decoding is
   procedure Read_Work
     (Item    : in out Quality_Manager.Storage.Store;
      Work_Id : String;
      Value   : out Quality_Manager.Storage.Schema.Work_Item;
      Result  : out Quality_Manager.Results.Operation_Result);

   procedure Read_Active_Dispatch
     (Item                : in out Quality_Manager.Storage.Store;
      Logical_Remediation : String;
      Value               : out Quality_Manager.Storage.Schema.Dispatch;
      Result              : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Storage.Decoding;
