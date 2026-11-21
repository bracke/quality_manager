with Quality_Manager.Results; use Quality_Manager.Results;

package body Quality_Manager.Storage.Migrations is
   function Can_Migrate (From_Version, To_Version : Natural) return Boolean is
     (From_Version = Initial_Schema.From_Version
      and then To_Version = Initial_Schema.To_Version);

   function Validate_Current (Found_Version : Natural) return Operation_Result is
   begin
      if Found_Version = Quality_Manager.Storage.Current_Schema_Version then
         return Make_Result (Success);
      elsif Found_Version > Quality_Manager.Storage.Current_Schema_Version then
         return Make_Result
           (Incompatible_Contract,
            "coordinator database schema is newer than this application",
            "qm.storage.schema-newer");
      else
         return Make_Result
           (Not_Ready,
            "coordinator database requires an unavailable migration",
            "qm.storage.migration-required");
      end if;
   end Validate_Current;
end Quality_Manager.Storage.Migrations;
