with Quality_Manager.Results;
with Quality_Manager.Storage;

package Quality_Manager.Approvals is
   procedure Apply_Decision
     (Store            : in out Quality_Manager.Storage.Store;
      Definition_Path  : String;
      Expected_Approve : Boolean;
      Result           : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Approvals;
