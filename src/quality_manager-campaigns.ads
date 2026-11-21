with Ada.Strings.Unbounded;
with Quality_Manager.Results;
with Quality_Manager.Scheduler;

package Quality_Manager.Campaigns is
   Campaign_Error : exception;

   type Context is limited private;

   procedure Initialize
     (Item  : out Context;
      Store : Quality_Manager.Scheduler.Store_Access);

   procedure Create
     (Item            : in out Context;
      Definition_Path : String;
      Result          : out Quality_Manager.Results.Operation_Result);
   procedure Start
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   procedure Pause
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   procedure Resume
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   procedure Cancel
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);
   procedure Reconcile
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);

   procedure Update_Target
     (Item          : in out Context;
      Campaign_Id   : String;
      Project_Id    : Positive;
      Indicator     : String;
      Assessment_Id : Positive;
      Outcome       : String;
      Result        : out Quality_Manager.Results.Operation_Result);

   procedure Update_Target
     (Item                 : in out Context;
      Campaign_Id          : String;
      Project_Id           : Positive;
      Indicator            : String;
      Assessment_Id        : Positive;
      Outcome              : String;
      Applicability_Valid  : Boolean;
      Result               : out Quality_Manager.Results.Operation_Result);

   procedure Record_Execution
     (Item : in out Context; Campaign_Id : String;
      Result : out Quality_Manager.Results.Operation_Result);

   function Progress
     (Item        : in out Context;
      Campaign_Id : String;
      Result      : out Quality_Manager.Results.Operation_Result) return String;

   procedure Find_Shared_Work
     (Item               : in out Context;
      Global_Remediation : String;
      Work_Id            : out Ada.Strings.Unbounded.Unbounded_String;
      Found              : out Boolean;
      Result             : out Quality_Manager.Results.Operation_Result);

   procedure Create (Definition_Path : String);
   procedure Start (Campaign_Id : String);
   procedure Pause (Campaign_Id : String);
   procedure Resume (Campaign_Id : String);
   procedure Reconcile (Campaign_Id : String);

private
   type Context is limited record
      Database : Quality_Manager.Scheduler.Store_Access;
   end record;
end Quality_Manager.Campaigns;
