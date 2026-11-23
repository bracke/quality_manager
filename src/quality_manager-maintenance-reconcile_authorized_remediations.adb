separate (Quality_Manager.Maintenance)
procedure Reconcile_Authorized_Remediations
  (Item             : in out Context;
   Project_Selector : String;
   Now              : Interfaces.Unsigned_64;
   Result           : out Operation_Result) is
   Values    : Quality_Manager.Storage.Entity_Vectors.Vector;
   Work      : Quality_Manager.Storage.Schema.Work_Item;
   Approval  : Quality_Manager.Storage.Schema.Approval;
   Published : Quality_Manager.Storage.Schema.Dispatch;
   Local     : Operation_Result;

   procedure Stop_Work
     (State      : Quality_Manager.Model.Work_State;
      Work_Id    : String;
      Target     : Quality_Manager.Model.Work_State;
      Diagnostic : String) is
   begin
      Quality_Manager.Storage.Transition_Work
        (Item.Database.all, Work_Id, State, Target,
         "event:" & Work_Id & ":maintenance:remediation-stop",
         "autonomous-remediation", Diagnostic, Local);
   end Stop_Work;

   procedure Queue (Value : Quality_Manager.Storage.Schema.Work_Item) is
   begin
      Quality_Manager.Dispatch.Queue_Persisted
        (Item.Database.all, Item.Runner, To_String (Value.Work_Id), Local);
      if Local.Kind = Success then
         Quality_Manager.Scheduler.Enqueue (Item.Queue.all, To_String (Value.Work_Id));
         Local := Quality_Manager.Scheduler.Last_Result (Item.Queue.all);
         if Local.Kind /= Success then
            Result := Local;
         end if;
      elsif Local.Kind = Stale_Evidence then
         Stop_Work
           (Value.State, To_String (Value.Work_Id), Quality_Manager.Model.Blocked, Message (Local));
         if Local.Kind /= Success then
            Result := Local;
         end if;
      elsif Local.Kind not in Not_Ready | Temporarily_Unavailable then
         Stop_Work
           (Value.State, To_String (Value.Work_Id),
            Quality_Manager.Model.Needs_Intervention, Message (Local));
         if Local.Kind /= Success then
            Result := Local;
         end if;
      end if;
   end Queue;

   function Eligible_State (State : String) return Boolean is
   begin
      return State in Quality_Manager.Model.Awaiting_Approval'Image |
                      Quality_Manager.Model.Published'Image |
                      Quality_Manager.Model.Queued'Image |
                      Quality_Manager.Model.Executing'Image |
                      Quality_Manager.Model.Awaiting_Integration'Image;
   end Eligible_State;

   procedure Enqueue_Active
     (Stored : Quality_Manager.Storage.Stored_Entity) is
   begin
      Quality_Manager.Scheduler.Enqueue_Work
        (Item.Queue.all, To_String (Work.Work_Id),
         "quality-project:" & To_String (Work.Project.Quality_Database_Id) & ":"
         & Ada.Strings.Fixed.Trim
             (Positive'Image (Work.Project.Quality_Project_Id), Ada.Strings.Both),
         Quality_Manager.Priorities.From_Persisted_Priority (Work.Priority),
         Stored.Generation,
         (if Work.State = Quality_Manager.Model.Awaiting_Integration
          then Quality_Manager.Scheduler.Integration_Resource
          else Quality_Manager.Scheduler.Agent_Resource));
      Local := Quality_Manager.Scheduler.Last_Result (Item.Queue.all);
      if Local.Kind /= Success then
         Result := Local;
      end if;
   end Enqueue_Active;

   procedure Handle_Awaiting_Approval is
   begin
      Quality_Manager.Storage.Decoding.Find_Approval_For_Work
        (Item.Database.all, Work, Now, Approval, Local);
      if Local.Kind = Success then
         Quality_Manager.Dispatch.Publish_Approved
           (Item.Database.all, Item.Planner, Work, Approval, Now, Published, Local);
         if Local.Kind = Success then
            Work.State := Quality_Manager.Model.Published;
            Queue (Work);
         else
            Stop_Work
              (Work.State, To_String (Work.Work_Id),
               Quality_Manager.Model.Needs_Intervention, Message (Local));
            if Local.Kind /= Success then
               Result := Local;
            end if;
         end if;
      elsif Local.Kind not in Not_Found | Authorization_Required then
         Result := Local;
      end if;
   end Handle_Awaiting_Approval;

   procedure Handle_Work
     (Stored : Quality_Manager.Storage.Stored_Entity) is
   begin
      Quality_Manager.Storage.Decoding.Read_Work
        (Item.Database.all, To_String (Stored.Entity_Key), Work, Local);
      if Local.Kind /= Success then
         Result := Local;
         return;
      elsif not Selected
        (Project_Selector, Work.Project.Quality_Project_Id,
         To_String (Work.Project.Canonical_Path))
      then
         return;
      end if;
      if Work.State = Quality_Manager.Model.Awaiting_Approval then
         Handle_Awaiting_Approval;
      elsif Work.State in Quality_Manager.Model.Published | Quality_Manager.Model.Queued then
         Queue (Work);
      elsif Work.State in Quality_Manager.Model.Executing |
                              Quality_Manager.Model.Awaiting_Integration
      then
         Enqueue_Active (Stored);
      end if;
   end Handle_Work;
begin
   Result := Make_Result (Success);
   Quality_Manager.Storage.List
     (Item.Database.all, Quality_Manager.Storage.Work_Item_Record, Values, 100_000, Result);
   if Result.Kind /= Success then
      return;
   end if;
   for Stored of Values loop
      Renew_Coordinator_Lease (Item, Local);
      if Local.Kind /= Success then
         Result := Local;
         return;
      elsif Eligible_State (To_String (Stored.State)) then
         Handle_Work (Stored);
         if Result.Kind /= Success then
            return;
         end if;
      end if;
   end loop;
   Result := Make_Result (Success);
end Reconcile_Authorized_Remediations;

