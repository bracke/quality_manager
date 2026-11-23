separate (Quality_Manager.Maintenance)
procedure Run_Configured_Cycle
  (Project_Selector : String;
   Dry_Run          : Boolean;
   Config_Path      : String;
   Config_Required  : Boolean) is
   Settings  : Quality_Manager.Config.Settings;
   Store     : aliased Quality_Manager.Storage.Store;
   Scheduler : aliased Quality_Manager.Scheduler.Scheduler_Type;
   Quality   : Quality_Manager.Integrations.Quality.Adapter;
   Planner   : Quality_Manager.Integrations.Improve.Adapter;
   Runner    : Quality_Manager.Integrations.Runner.Adapter;
   Item      : Context;
   Result    : Operation_Result;
   Close_Result : Operation_Result;
   Lease_Result : Operation_Result;
   Lease_Owner : constant String := "quality-manager:"
     & Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
         (Database.UUIDs.UUID_To_String (Database.UUIDs.Generate_UUID));
   Lease_Generation : Interfaces.Unsigned_64 := 0;
   Lease_Held : Boolean := False;
   Effective_Dry_Run : Boolean := False;
   procedure Acquire_Coordinator is
      Now      : constant Interfaces.Unsigned_64 := Unix_Now;
      Duration : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Settings.Maximum_Task_Seconds) + 300;
   begin
      if Duration > Interfaces.Unsigned_64'Last - Now then
         Result := Make_Result
           (Integrity_Error, "coordinator lease expiration is out of range",
            "qm.maintenance.coordinator-lease");
      else
         Quality_Manager.Storage.Acquire_Exclusive_Lease
           (Store, "active-coordinator", Lease_Owner, Now, Now + Duration,
            Lease_Generation, Result);
         Lease_Held := Result.Kind = Success;
      end if;
   end Acquire_Coordinator;

   procedure Configure_Context is
   begin
      Quality_Manager.Scheduler.Initialize (Scheduler);
      Quality_Manager.Scheduler.Configure
        (Scheduler, Store'Unchecked_Access, Settings.Assessment_Workers, Settings.Agent_Workers);
      Quality_Manager.Integrations.Quality.Initialize
        (Quality, To_String (Settings.Ada_Quality_Executable), To_String (Settings.Quality_Database),
         Policy_Path => To_String (Settings.Quality_Policy));
      Quality_Manager.Integrations.Improve.Initialize
        (Planner, To_String (Settings.Improve_Executable), To_String (Settings.Improve_Config),
         To_String (Settings.Quality_Database), To_String (Settings.Improve_State));
      Quality_Manager.Integrations.Runner.Initialize
        (Runner, To_String (Settings.Model_Runner_Executable));
      Initialize
        (Item, Store'Unchecked_Access, Scheduler'Unchecked_Access, Quality, Planner, Runner,
         Settings.Maximum_Task_Seconds, Settings.Remediation_Attempts);
      Configure_Coordinator_Lease
        (Item, Lease_Owner, Lease_Generation, Settings.Maximum_Task_Seconds + 300);
   end Configure_Context;

   procedure Release_Coordinator is
   begin
      if not Lease_Held then
         return;
      end if;
      Quality_Manager.Storage.Release_Lease
        (Store, "active-coordinator", Lease_Owner, Item.Lease_Generation, Lease_Result);
      if Result.Kind = Success and then Lease_Result.Kind /= Success then
         Result := Lease_Result;
      end if;
      Lease_Held := False;
   end Release_Coordinator;

   procedure Close_Resources is
   begin
      Quality_Manager.Scheduler.Shutdown (Scheduler);
      Quality_Manager.Storage.Close (Store, Result => Close_Result);
      if Result.Kind = Success and then Close_Result.Kind /= Success then
         Result := Close_Result;
      end if;
   end Close_Resources;

   procedure Emergency_Cleanup is
   begin
      if Lease_Held and then Quality_Manager.Storage.Is_Open (Store) then
         Quality_Manager.Storage.Release_Lease
           (Store, "active-coordinator", Lease_Owner,
            (if Item.Lease_Generation = 0 then Lease_Generation else Item.Lease_Generation),
            Lease_Result);
      end if;
      Quality_Manager.Scheduler.Shutdown (Scheduler);
      if Quality_Manager.Storage.Is_Open (Store) then
         Quality_Manager.Storage.Close (Store, Result => Close_Result);
      end if;
   end Emergency_Cleanup;
begin
   Quality_Manager.Config.Load (Config_Path, Config_Required, Settings, Result);
   if Result.Kind = Success then
      Effective_Dry_Run := Dry_Run or else Settings.Dry_Run;
   end if;
   if Result.Kind = Success and then not Effective_Dry_Run then
      Quality_Manager.Storage.Open
        (Store, To_String (Settings.Coordinator_Database), True, Result);
   end if;
   if Result.Kind = Success and then not Effective_Dry_Run then
      Acquire_Coordinator;
   end if;
   if Result.Kind = Success then
      Configure_Context;
      Run_Cycle (Item, Project_Selector, Effective_Dry_Run, Result);
   end if;
   Release_Coordinator;
   Close_Resources;
   if Result.Kind /= Success then
      raise Maintenance_Error with Message (Result);
   end if;
exception
   when Maintenance_Error =>
      raise;
   when others =>  --  AQ: audited exception boundary
      Emergency_Cleanup;
      raise Maintenance_Error with "configured maintenance cycle failed unexpectedly";
end Run_Configured_Cycle;

