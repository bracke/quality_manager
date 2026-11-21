with Quality_Manager.Results;

package Quality_Manager.Storage.Migrations is
   type Migration_Step is record
      From_Version : Natural;
      To_Version   : Positive;
   end record;

   Initial_Schema : constant Migration_Step :=
     (From_Version => 0, To_Version => Quality_Manager.Storage.Current_Schema_Version);

   function Can_Migrate (From_Version, To_Version : Natural) return Boolean;

   function Validate_Current
     (Found_Version : Natural) return Quality_Manager.Results.Operation_Result;
end Quality_Manager.Storage.Migrations;
