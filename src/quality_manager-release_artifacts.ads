with Quality_Manager.Results;

--  Creates independently verifiable release evidence signatures and SBOMs.
package Quality_Manager.Release_Artifacts is
   procedure Generate_Keypair
     (Private_Key_Path : String;
      Public_Key_Path  : String;
      Result           : out Quality_Manager.Results.Operation_Result);

   procedure Sign
     (Artifact_Path    : String;
      Private_Key_Path : String;
      Result           : out Quality_Manager.Results.Operation_Result);

   procedure Verify
     (Artifact_Path   : String;
      Public_Key_Path : String;
      Result          : out Quality_Manager.Results.Operation_Result);

   procedure Generate_SBOM
     (Manifest_Path : String;
      Output_Path   : String;
      Result        : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Release_Artifacts;
