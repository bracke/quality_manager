with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Quality_Manager.Identities is
   function Equal (Left, Right : Project_Key) return Boolean is
     (Left.Quality_Database_Id = Right.Quality_Database_Id
      and then Left.Quality_Project_Id = Right.Quality_Project_Id
      and then Left.Canonical_Path = Right.Canonical_Path);
end Quality_Manager.Identities;
