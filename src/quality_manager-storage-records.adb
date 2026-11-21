with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Jsonlib.Serializers;
with Quality_Manager.Identities;
with Quality_Manager.Transitions;

package body Quality_Manager.Storage.Records is
   use Quality_Manager.Storage.Schema;

   function Q (Value : String) return String is
     ('"' & Jsonlib.Serializers.Escape (Value) & '"');

   function N (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Project_Identity (Value : Quality_Manager.Identities.Project_Key) return String is
     (Quality_Manager.Identities.Canonical_Digest
        ([Quality_Manager.Identities.Text_Value (To_String (Value.Quality_Database_Id)),
          Quality_Manager.Identities.Number_Value (Interfaces.Unsigned_64 (Value.Quality_Project_Id)),
          Quality_Manager.Identities.Text_Value (To_String (Value.Canonical_Path))]));

   function Project_JSON (Value : Quality_Manager.Identities.Project_Key) return String is
     ("{""quality_database_id"":" & Q (To_String (Value.Quality_Database_Id))
      & ",""quality_project_id"":" & N (Value.Quality_Project_Id)
      & ",""canonical_path"":" & Q (To_String (Value.Canonical_Path)) & "}");

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Project;
      Result : out Quality_Manager.Results.Operation_Result) is
      Entity : constant Stored_Entity :=
        (Internal_Id => 1,
         Kind => Project_Record,
         Entity_Key => To_Unbounded_String ("project:" & Project_Identity (Value.Key)),
         State => To_Unbounded_String (if Value.Enabled then "ENABLED" else "DISABLED"),
         Payload => To_Unbounded_String
           ("{""project"":" & Project_JSON (Value.Key)
            & ",""last_assessment_run"":" & N (Value.Last_Assessment_Run)
            & ",""last_source_fingerprint"":" & Q (To_String (Value.Last_Source_Fingerprint)) & "}"),
         Terminal => False,
         Generation => 1);
   begin
      Quality_Manager.Storage.Put (Item, Entity, Result);
   end Save;

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Work_Item;
      Result : out Quality_Manager.Results.Operation_Result) is
      Entity : constant Stored_Entity :=
        (Internal_Id => 1,
         Kind => Work_Item_Record,
         Entity_Key => Value.Work_Id,
         State => To_Unbounded_String (Quality_Manager.Model.Work_State'Image (Value.State)),
         Payload => To_Unbounded_String
           ("{""global_remediation"":" & Q (To_String (Value.Global_Remediation))
            & ",""project"":" & Project_JSON (Value.Project)
            & ",""origin"":" & Q (Quality_Manager.Model.Workflow_Kind'Image (Value.Origin))
            & ",""findings"":" & Q (To_String (Value.Finding_Identities))
            & ",""priority"":" & N (Value.Priority)
            & ",""plan_id"":" & Q (To_String (Value.Improve_Plan_Id))
            & ",""plan_revision"":" & N (Value.Improve_Revision)
            & ",""task_id"":" & Q (To_String (Value.Improve_Task_Id))
            & ",""outcome"":" & Q (Quality_Manager.Model.Outcome_Kind'Image (Value.Outcome)) & "}"),
         Terminal => Quality_Manager.Transitions.Is_Terminal (Value.State),
         Generation => 1);
   begin
      Quality_Manager.Storage.Put (Item, Entity, Result);
   end Save;

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Dispatch;
      Result : out Quality_Manager.Results.Operation_Result) is
      Key : constant String :=
        (if Value.Active
         then "active-dispatch:" & To_String (Value.Logical_Remediation)
         else "dispatch:" & To_String (Value.Dispatch_Id));
      Entity : constant Stored_Entity :=
        (Internal_Id => 1,
         Kind => Dispatch_Record,
         Entity_Key => To_Unbounded_String (Key),
         State => To_Unbounded_String (Quality_Manager.Model.Work_State'Image (Value.State)),
         Payload => To_Unbounded_String
           ("{""dispatch_id"":" & Q (To_String (Value.Dispatch_Id))
            & ",""work_id"":" & Q (To_String (Value.Work_Id))
            & ",""plan_id"":" & Q (To_String (Value.Improve_Task.Plan_Id))
            & ",""plan_revision"":" & N (Value.Improve_Task.Revision)
            & ",""improve_task_id"":" & Q (To_String (Value.Improve_Task.Task_Id))
            & ",""native_task_id"":" & Q (To_String (Value.Native_Task_Id))
            & ",""authorization_id"":" & Q (To_String (Value.Authorization_Id)) & "}"),
         Terminal => not Value.Active,
         Generation => 1);
   begin
      Quality_Manager.Storage.Put (Item, Entity, Result);
   end Save;

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Approval;
      Result : out Quality_Manager.Results.Operation_Result) is
      Entity : constant Stored_Entity :=
        (Internal_Id => 1,
         Kind => Approval_Record,
         Entity_Key => To_Unbounded_String ("approval:" & To_String (Value.Approval_Id)),
         State => To_Unbounded_String ("APPROVED"),
         Payload => To_Unbounded_String
           ("{""project"":" & Project_JSON (Value.Project)
            & ",""plan_id"":" & Q (To_String (Value.Plan_Id))
            & ",""plan_revision"":" & N (Value.Plan_Revision)
            & ",""content_digest"":" & Q (To_String (Value.Content_Digest))
            & ",""action"":" & Q (To_String (Value.Authorized_Action))
            & ",""policy_digest"":" & Q (To_String (Value.Policy_Digest))
            & ",""approver"":" & Q (To_String (Value.Approver)) & "}"),
         Terminal => True,
         Generation => 1);
   begin
      Quality_Manager.Storage.Put (Item, Entity, Result);
   end Save;

   procedure Save
     (Item   : in out Quality_Manager.Storage.Store;
      Value  : Verification;
      Result : out Quality_Manager.Results.Operation_Result) is
      Entity : constant Stored_Entity :=
        (Internal_Id => 1,
         Kind => Verification_Record,
         Entity_Key => To_Unbounded_String ("verification:" & To_String (Value.Composite_Key)),
         State => To_Unbounded_String ("RECORDED"),
         Payload => To_Unbounded_String
           ("{""work_id"":" & Q (To_String (Value.Work_Id))
            & ",""assessment_run"":" & N (Value.Assessment.Run_Id)
            & ",""assessment_project"":" & Project_JSON (Value.Assessment.Project)
            & ",""contract_digest"":" & Q (To_String (Value.Contract_Digest))
            & ",""native_result"":" & Q (To_String (Value.Native_Result))
            & ",""improve_result"":" & Q (To_String (Value.Improve_Result))
            & ",""regression_result"":" & Q (To_String (Value.Regression_Result))
            & ",""source_fingerprint"":" & Q (To_String (Value.Source_Fingerprint))
            & ",""policy_fingerprint"":" & Q (To_String (Value.Policy_Fingerprint))
            & ",""toolchain_fingerprint"":" & Q (To_String (Value.Toolchain_Fingerprint)) & "}"),
         Terminal => True,
         Generation => 1);
   begin
      Quality_Manager.Storage.Put (Item, Entity, Result);
   end Save;
end Quality_Manager.Storage.Records;
