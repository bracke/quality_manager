separate (Quality_Manager.Releases)
procedure Qualify_Configured
  (Release_Id      : String;
   Config_Path     : String;
   Config_Required : Boolean) is
   Settings : Quality_Manager.Config.Settings;
   Store    : aliased Quality_Manager.Storage.Store;
   Item     : Context;
   Quality  : Quality_Manager.Integrations.Quality.Adapter;
   Decision   : Qualification_Decision;
   Result, Close_Result : Operation_Result;
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
      Initialize (Item, Store'Unchecked_Access);
      Quality_Manager.Integrations.Quality.Initialize
        (Quality, To_String (Settings.Ada_Quality_Executable),
         To_String (Settings.Quality_Database), Policy_Path => To_String (Settings.Quality_Policy));
      Qualify_With_Tools (Item, Quality, Release_Id, "alr", "git", Decision, Result);
   end if;
   if Quality_Manager.Storage.Is_Open (Store) then
      Quality_Manager.Storage.Close (Store, Close_Result);
      if Result.Kind = Success and then Close_Result.Kind /= Success then
         Result := Close_Result;
      end if;
   end if;
   if Result.Kind /= Success then
      raise Release_Error with Message (Result);
   end if;
end Qualify_Configured;

