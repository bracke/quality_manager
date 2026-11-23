with Quality_Manager.Results;
with Quality_Manager.Storage;

--  Applies durable, content-bound authorization decisions.
package Quality_Manager.Approvals is
   --  Public contract for this Quality Manager unit.
   --  Public contract for this Quality Manager unit.
   procedure Apply_Decision
     (Store            : in out Quality_Manager.Storage.Store;
      Definition_Path  : String;
      Expected_Approve : Boolean;
      Result           : out Quality_Manager.Results.Operation_Result);
   --  Perform Apply Decision.
   --  @param Store Store.
   --  @param Definition_Path Definition Path.
   --  @param Expected_Approve Expected Approve.
   --  @param Result Result.
end Quality_Manager.Approvals;
