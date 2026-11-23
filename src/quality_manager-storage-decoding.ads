with Interfaces;
with Quality_Manager.Results;
with Quality_Manager.Storage.Schema;

--  Decodes typed records from persistent entities.
package Quality_Manager.Storage.Decoding is
   --  Public contract for this Quality Manager unit.
   procedure Read_Work
     (Item    : in out Quality_Manager.Storage.Store;
      Work_Id : String;
      Value   : out Quality_Manager.Storage.Schema.Work_Item;
      Result  : out Quality_Manager.Results.Operation_Result);
   --  Perform Read Work.
   --  @param Item Item.
   --  @param Work_Id Work Id.
   --  @param Value Value.
   --  @param Result Result.

   procedure Read_Active_Dispatch
     (Item                : in out Quality_Manager.Storage.Store;
      Logical_Remediation : String;
      Value               : out Quality_Manager.Storage.Schema.Dispatch;
      Result              : out Quality_Manager.Results.Operation_Result);
   --  Perform Read Active Dispatch.
   --  @param Item Item.
   --  @param Logical_Remediation Logical Remediation.
   --  @param Value Value.
   --  @param Result Result.

   procedure Find_Approval_For_Work
     (Item   : in out Quality_Manager.Storage.Store;
      Work   : Quality_Manager.Storage.Schema.Work_Item;
      Now    : Interfaces.Unsigned_64;
      Value  : out Quality_Manager.Storage.Schema.Approval;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Find Approval For Work.
   --  @param Item Item.
   --  @param Work Work.
   --  @param Now Now.
   --  @param Value Value.
   --  @param Result Result.
end Quality_Manager.Storage.Decoding;
