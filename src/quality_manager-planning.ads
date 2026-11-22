with Quality_Manager.Identities;
with Quality_Manager.Integrations.Improve;
with Quality_Manager.Model;
with Quality_Manager.Results;
with Quality_Manager.Storage;

package Quality_Manager.Planning is
   procedure Generate_Or_Reconcile
     (Store            : in out Quality_Manager.Storage.Store;
      Planner          : Quality_Manager.Integrations.Improve.Adapter;
      Project          : Quality_Manager.Identities.Project_Key;
      Assessment_Run   : Positive;
      Candidate_Source : String;
      Policy_Digest    : String;
      Workflow         : Quality_Manager.Model.Workflow_Kind;
      Stable_Id        : String;
      Result           : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Planning;
