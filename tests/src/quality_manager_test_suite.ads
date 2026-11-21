with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Quality_Manager_Test_Suite is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   function Suite return AUnit.Test_Suites.Access_Test_Suite;
end Quality_Manager_Test_Suite;
