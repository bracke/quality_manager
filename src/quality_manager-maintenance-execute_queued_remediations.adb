separate (Quality_Manager.Maintenance)
procedure Execute_Queued_Remediations
  (Item   : in out Context;
   Now    : Interfaces.Unsigned_64;
   Result : out Operation_Result) is
   Work_Id  : Unbounded_String;
   Resource : Quality_Manager.Scheduler.Work_Resource;
   Found    : Boolean;
   Snapshot : Quality_Manager.Integrations.Runner.Task_Snapshot;
   Local    : Operation_Result;
   Expires  : Interfaces.Unsigned_64;
begin
   Result := Make_Result (Success);
   if Interfaces.Unsigned_64 (Item.Maximum_Task_Seconds) + 60
     > Interfaces.Unsigned_64'Last - Now
   then
      Result := Make_Result
        (Integrity_Error, "execution lease expiration is out of range", "qm.maintenance.lease-range");
      return;
   end if;
   Expires := Now + Interfaces.Unsigned_64 (Item.Maximum_Task_Seconds) + 60;
   loop
      Renew_Coordinator_Lease (Item, Local);
      if Local.Kind /= Success then
         Result := Local;
         return;
      end if;
      Quality_Manager.Scheduler.Take_Next (Item.Queue.all, Work_Id, Resource, Found);
      exit when not Found;
      if Resource not in Quality_Manager.Scheduler.Agent_Resource |
                         Quality_Manager.Scheduler.Integration_Resource
      then
         Quality_Manager.Scheduler.Complete (Item.Queue.all, To_String (Work_Id));
         Result := Make_Result
           (Integrity_Error, "remediation selected a non-agent resource", "qm.maintenance.agent-resource");
         return;
      end if;
      if Resource = Quality_Manager.Scheduler.Agent_Resource then
         Quality_Manager.Dispatch.Execute_Persisted
           (Item.Database.all, Item.Runner, To_String (Work_Id),
            "coordinator:" & Quality_Manager.Storage.Identity (Item.Database.all),
            Now, Expires, Item.Maximum_Task_Seconds, Snapshot, Local,
            Maximum_Attempts => Item.Maximum_Attempts);
      else
         Quality_Manager.Dispatch.Integrate_Persisted
           (Item.Database.all, Item.Runner, To_String (Work_Id),
            "coordinator:" & Quality_Manager.Storage.Identity (Item.Database.all),
            Now, Expires, Snapshot, Local);
      end if;
      Quality_Manager.Scheduler.Complete (Item.Queue.all, To_String (Work_Id));
      if Local.Kind not in Success | Not_Ready | Temporarily_Unavailable then
         declare
            Work : Quality_Manager.Storage.Schema.Work_Item;
         begin
            Quality_Manager.Storage.Decoding.Read_Work
              (Item.Database.all, To_String (Work_Id), Work, Result);
            if Result.Kind /= Success then
               return;
            elsif Work.State in Quality_Manager.Model.Executing |
                                     Quality_Manager.Model.Awaiting_Integration
            then
               Stop_Work : declare
                  Target : constant Quality_Manager.Model.Work_State :=
                    (if Local.Kind in Authorization_Required | Integrity_Error | Incompatible_Contract
                     then Quality_Manager.Model.Needs_Intervention
                     else Quality_Manager.Model.Blocked);
               begin
                  Quality_Manager.Storage.Transition_Work
                    (Item.Database.all, To_String (Work_Id), Work.State, Target,
                     "event:" & To_String (Work_Id) & ":maintenance:execution-stop",
                     "native-execution", Message (Local), Result);
                  if Result.Kind /= Success then
                     return;
                  end if;
               end Stop_Work;
            end if;
         end;
      end if;
   end loop;
   Result := Make_Result (Success);
end Execute_Queued_Remediations;

