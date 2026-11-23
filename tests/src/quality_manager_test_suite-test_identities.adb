separate (Quality_Manager_Test_Suite)
procedure Test_Identities (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Left : constant Quality_Manager.Identities.Project_Key :=
     (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
   Same : constant Quality_Manager.Identities.Project_Key := Left;
   Other : constant Quality_Manager.Identities.Project_Key :=
     (To_Unbounded_String ("database-b"), 7, To_Unbounded_String ("/project"));
begin
   Assert (Quality_Manager.Identities.Equal (Left, Same), "same qualified identity matches");
   Assert (not Quality_Manager.Identities.Equal (Left, Other), "database identity is authoritative");
end Test_Identities;

