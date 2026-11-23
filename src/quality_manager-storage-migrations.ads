with Quality_Manager.Results;

--  Validates and applies atomic schema migrations.
package Quality_Manager.Storage.Migrations is
   --  Public contract for this Quality Manager unit.
   type Migration_Step is record
      From_Version : Natural;
      To_Version   : Positive;
   end record;
   --  Migration Step record.
   --  @field From_Version From Version.
   --  @field To_Version To Version.

   Initial_Schema : constant Migration_Step :=
     (From_Version => 0, To_Version => Quality_Manager.Storage.Current_Schema_Version);
   --  Initial Schema.

   function Can_Migrate (From_Version, To_Version : Natural) return Boolean;
   --  Return Can Migrate.
   --  @param From_Version From Version.
   --  @param To_Version To Version.
   --  @return Can Migrate result.

   function Validate_Current
     (Found_Version : Natural) return Quality_Manager.Results.Operation_Result;
   --  Return Validate Current.
   --  @param Found_Version Found Version.
   --  @return Validate Current result.
end Quality_Manager.Storage.Migrations;
