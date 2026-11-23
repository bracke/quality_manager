separate (Quality_Manager.Releases)
procedure Export_Evidence_Configured
  (Release_Id      : String;
   Output_Path     : String;
   Config_Path     : String;
   Config_Required : Boolean) is
   Settings : Quality_Manager.Config.Settings;
   Store : aliased Quality_Manager.Storage.Store;
   Item : Context;
   Result, Close_Result : Operation_Result;
begin
   Quality_Manager.Config.Load (Config_Path, Config_Required, Settings, Result);
   if Result.Kind = Success then
      Quality_Manager.Storage.Open (Store, To_String (Settings.Coordinator_Database), True, Result);
   end if;
   if Result.Kind = Success then
      Initialize (Item, Store'Unchecked_Access);
      Export_Evidence (Item, Release_Id, Output_Path, Result);
   end if;
   Quality_Manager.Storage.Close (Store, Close_Result);
   if Result.Kind = Success and then Close_Result.Kind /= Success then Result := Close_Result; end if;
   if Result.Kind /= Success then raise Release_Error with Message (Result); end if;
end Export_Evidence_Configured;

