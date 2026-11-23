with Ada.Strings.Unbounded;
with Quality_Manager.Results;

--  Prepares isolated source copies and computes deterministic build manifests.
package Quality_Manager.Reproducibility is
   procedure Prepare_Clean_Workspace
     (Source    : String;
      Workspace : String;
      Result    : out Quality_Manager.Results.Operation_Result);

   procedure Manifest
     (Root              : String;
      Include_Artifacts : Boolean;
      Digest            : out Ada.Strings.Unbounded.Unbounded_String;
      Artifact_Count    : out Natural;
      Result            : out Quality_Manager.Results.Operation_Result);

   procedure Remove_Workspace
     (Workspace : String;
      Result    : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Reproducibility;
