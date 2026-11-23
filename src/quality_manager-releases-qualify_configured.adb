separate (Quality_Manager.Releases)
procedure Qualify_Configured
  (Release_Id      : String;
   Config_Path     : String;
   Config_Required : Boolean) is
   Settings : Quality_Manager.Config.Settings;
   Store    : aliased Quality_Manager.Storage.Store;
   Item     : Context;
   Scheduler : aliased Quality_Manager.Scheduler.Scheduler_Type;
   Quality  : Quality_Manager.Integrations.Quality.Adapter;
   Planner  : Quality_Manager.Integrations.Improve.Adapter;
   Runner   : Quality_Manager.Integrations.Runner.Adapter;
   Maintenance_Item : Quality_Manager.Maintenance.Context;
   Decision   : Qualification_Decision;
   Result, Close_Result, Lease_Result : Operation_Result;
   Lease_Owner : constant String := "quality-manager:release:"
     & Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
         (Database.UUIDs.UUID_To_String (Database.UUIDs.Generate_UUID));
   Lease_Generation : Interfaces.Unsigned_64 := 0;
   Lease_Held : Boolean := False;

   function Unix_Now return Interfaces.Unsigned_64 is
      Value : constant Long_Long_Integer := Long_Long_Integer
        (Ada.Calendar.Conversions.To_Unix_Time_64 (Ada.Calendar.Clock));
   begin
      return (if Value < 0 then 0 else Interfaces.Unsigned_64 (Value));
   end Unix_Now;

   procedure Release_Coordinator is
   begin
      if Lease_Held and then Quality_Manager.Storage.Is_Open (Store) then
         Quality_Manager.Storage.Release_Lease
           (Store, "active-coordinator", Lease_Owner, Lease_Generation, Lease_Result);
         if Result.Kind = Success and then Lease_Result.Kind /= Success then
            Result := Lease_Result;
         end if;
         Lease_Held := False;
      end if;
   end Release_Coordinator;

   procedure Close_Resources is
   begin
      Quality_Manager.Scheduler.Shutdown (Scheduler);
      if Quality_Manager.Storage.Is_Open (Store) then
         Quality_Manager.Storage.Close (Store, Close_Result);
         if Result.Kind = Success and then Close_Result.Kind /= Success then
            Result := Close_Result;
         end if;
      end if;
   end Close_Resources;
begin
   if Release_Id = "" then
      Result := Make_Result (Invalid_Request, "release identity is required", "qm.release.identity");
   else
      Quality_Manager.Config.Load (Config_Path, Config_Required, Settings, Result);
   end if;
   if Result.Kind = Success and then Length (Settings.Quality_Database) = 0 then
      Result := Make_Result
        (Invalid_Request, "release qualification requires an Ada Quality database",
         "qm.release.quality-database");
   end if;
   if Result.Kind = Success then
      Quality_Manager.Storage.Open
        (Store, To_String (Settings.Coordinator_Database), True, Result);
   end if;
   if Result.Kind = Success then
      declare
         Now : constant Interfaces.Unsigned_64 := Unix_Now;
         Duration : constant Interfaces.Unsigned_64 :=
           Interfaces.Unsigned_64 (Settings.Maximum_Task_Seconds) + 300;
      begin
         if Duration > Interfaces.Unsigned_64'Last - Now then
            Result := Make_Result
              (Integrity_Error, "coordinator lease expiration is out of range",
               "qm.release.coordinator-lease");
         else
            Quality_Manager.Storage.Acquire_Exclusive_Lease
              (Store, "active-coordinator", Lease_Owner, Now, Now + Duration,
               Lease_Generation, Result);
            Lease_Held := Result.Kind = Success;
         end if;
      end;
   end if;
   if Result.Kind = Success then
      Initialize (Item, Store'Unchecked_Access);
      Quality_Manager.Scheduler.Initialize (Scheduler);
      Quality_Manager.Scheduler.Configure
        (Scheduler, Store'Unchecked_Access, Settings.Assessment_Workers, Settings.Agent_Workers);
      Quality_Manager.Integrations.Quality.Initialize
        (Quality, To_String (Settings.Ada_Quality_Executable),
         To_String (Settings.Quality_Database), Policy_Path => To_String (Settings.Quality_Policy));
      Quality_Manager.Integrations.Improve.Initialize
        (Planner, To_String (Settings.Improve_Executable), To_String (Settings.Improve_Config),
         To_String (Settings.Quality_Database), To_String (Settings.Improve_State));
      Quality_Manager.Integrations.Runner.Initialize
        (Runner, To_String (Settings.Model_Runner_Executable));
      Quality_Manager.Maintenance.Initialize
        (Maintenance_Item, Store'Unchecked_Access, Scheduler'Unchecked_Access,
         Quality, Planner, Runner, Settings.Maximum_Task_Seconds, Settings.Remediation_Attempts);
      Quality_Manager.Maintenance.Configure_Coordinator_Lease
        (Maintenance_Item, Lease_Owner, Lease_Generation, Settings.Maximum_Task_Seconds + 300);
      if Settings.Dry_Run then
         Qualify_With_Tools (Item, Quality, Release_Id, "alr", "git", Decision, Result);
      else
         Qualify_With_Remediation
           (Item, Maintenance_Item, Quality, Release_Id, "alr", "git",
            Settings.Remediation_Attempts, Decision, Result);
         Lease_Generation :=
           Quality_Manager.Maintenance.Coordinator_Lease_Generation (Maintenance_Item);
      end if;
   end if;
   Release_Coordinator;
   Close_Resources;
   if Result.Kind /= Success then
      raise Release_Error with Message (Result);
   end if;
exception
   when Release_Error =>
      raise;
   when others =>  --  AQ: audited exception boundary
      Release_Coordinator;
      Close_Resources;
      raise Release_Error with "configured release qualification failed unexpectedly";
end Qualify_Configured;

