with Ada.Strings.Unbounded;
with Quality_Manager.Integrations.Summary;
with Quality_Manager.Results;
with Quality_Manager.Scheduler;

--  Coordinates versioned multi-project quality improvement campaigns.
package Quality_Manager.Campaigns is
   --  Public contract for this Quality Manager unit.
   Campaign_Error : exception;
   --  Raised for Campaign Error.

   type Context is limited private;
   --  Context domain value.

   procedure Initialize
     (Item  : out Context;
      Store : Quality_Manager.Scheduler.Store_Access);
   --  Perform Initialize.
   --  @param Item Item.
   --  @param Store Store.

   procedure Create
     (Item            : in out Context;
      Definition_Path : String;
      Result          : out Quality_Manager.Results.Operation_Result);
   --  Perform Create.
   --  @param Item Item.
   --  @param Definition_Path Definition Path.
   --  @param Result Result.
   procedure Start
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Start.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Result Result.
   procedure Pause
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Pause.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Result Result.
   procedure Resume
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Resume.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Result Result.
   procedure Cancel
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Cancel.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Result Result.
   procedure Reconcile
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Reconcile.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Result Result.
   procedure Reconcile
     (Item        : in out Context;
      Summary     : Quality_Manager.Integrations.Summary.Adapter;
      Campaign_Id : String;
      Result      : out Quality_Manager.Results.Operation_Result);
   --  Perform Reconcile.
   --  @param Item Item.
   --  @param Summary Summary.
   --  @param Campaign_Id Campaign Id.
   --  @param Result Result.

   procedure Update_Target
     (Item          : in out Context;
      Campaign_Id   : String;
      Project_Id    : Positive;
      Indicator     : String;
      Assessment_Id : Positive;
      Outcome       : String;
      Result        : out Quality_Manager.Results.Operation_Result);
   --  Perform Update Target.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Project_Id Project Id.
   --  @param Indicator Indicator.
   --  @param Assessment_Id Assessment Id.
   --  @param Outcome Outcome.
   --  @param Result Result.

   procedure Update_Target
     (Item                 : in out Context;
      Campaign_Id          : String;
      Project_Id           : Positive;
      Indicator            : String;
      Assessment_Id        : Positive;
      Outcome              : String;
      Applicability_Valid  : Boolean;
      Result               : out Quality_Manager.Results.Operation_Result);
   --  Perform Update Target.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Project_Id Project Id.
   --  @param Indicator Indicator.
   --  @param Assessment_Id Assessment Id.
   --  @param Outcome Outcome.
   --  @param Applicability_Valid Applicability Valid.
   --  @param Result Result.

   procedure Record_Execution
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Record Execution.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Result Result.

   function Progress
     (Item        : in out Context;
      Campaign_Id : String;
      Result      : out Quality_Manager.Results.Operation_Result) return String;
   --  Return Progress.
   --  @param Item Item.
   --  @param Campaign_Id Campaign Id.
   --  @param Result Result.
   --  @return Progress result.

   procedure Find_Shared_Work
     (Item               : in out Context;
      Global_Remediation : String;
      Work_Id            : out Ada.Strings.Unbounded.Unbounded_String;
      Found              : out Boolean;
      Result             : out Quality_Manager.Results.Operation_Result);
   --  Perform Find Shared Work.
   --  @param Item Item.
   --  @param Global_Remediation Global Remediation.
   --  @param Work_Id Work Id.
   --  @param Found Found.
   --  @param Result Result.

   procedure Create (Definition_Path : String);
   --  Perform Create.
   --  @param Definition_Path Definition Path.
   procedure Start (Campaign_Id : String);
   --  Perform Start.
   --  @param Campaign_Id Campaign Id.
   procedure Pause (Campaign_Id : String);
   --  Perform Pause.
   --  @param Campaign_Id Campaign Id.
   procedure Resume (Campaign_Id : String);
   --  Perform Resume.
   --  @param Campaign_Id Campaign Id.
   procedure Reconcile (Campaign_Id : String);
   --  Perform Reconcile.
   --  @param Campaign_Id Campaign Id.

private
   type Context is limited record
      Database : Quality_Manager.Scheduler.Store_Access;
   end record;
end Quality_Manager.Campaigns;
