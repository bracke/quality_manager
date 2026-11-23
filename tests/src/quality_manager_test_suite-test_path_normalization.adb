separate (Quality_Manager_Test_Suite)
procedure Test_Path_Normalization (Item : in out Fixture) is
   pragma Unreferenced (Item);
begin
   Assert (Quality_Manager.Config.Normalize_Path ("/a/./b/../c//") = "/a/c", "absolute path normalized");
   Assert (Quality_Manager.Config.Normalize_Path ("") = "", "empty path remains empty");
end Test_Path_Normalization;

