separate (Quality_Manager_Test_Suite)
procedure Test_Transitions_And_Journal (Item : in out Fixture) is
   pragma Unreferenced (Item);
   use Quality_Manager.Model;
   use Quality_Manager.Journal;
   Validation : Quality_Manager.Results.Operation_Result;
begin
   Assert (Quality_Manager.Transitions.Allowed (Discovered, Planning), "discovered work may enter planning");
   Assert (not Quality_Manager.Transitions.Allowed (Verified, Planning), "verified work cannot reopen");
   Validation := Quality_Manager.Transitions.Validate (Verified, Planning);
   Assert (Validation.Kind = Quality_Manager.Results.Invalid_Request, "terminal transition reports a value error");

   Assert (Action_For (Prepared) = Invoke_After_Revalidation, "prepared operation is revalidated before invoke");
   Assert (Action_For (Invoking) = Query_External_Identity, "invoking operation is queried before retry");
   Assert (Action_For (Reconciling) = Adopt_Confirmed_Result, "confirmed result is adopted");
   Assert (Allowed (Prepared, Invoking), "journal may begin invocation");
   Assert (not Allowed (Committed, Invoking), "committed operation cannot reopen");

   for From_State in Quality_Manager.Journal.Journal_State loop
      for To_State in Quality_Manager.Journal.Journal_State loop
         declare
            Permitted : constant Boolean := Allowed (From_State, To_State);
         begin
            Assert
              (Permitted = Allowed (From_State, To_State),
               "journal transition table is deterministic");
         end;
      end loop;
      declare
         Action : constant Quality_Manager.Journal.Recovery_Action := Action_For (From_State);
      begin
         Assert
           (Action in Invoke_After_Revalidation | Query_External_Identity
              | Adopt_Confirmed_Result | No_Action | Preserve_Failure | Escalate,
            "every journal state has an explicit recovery action");
      end;
   end loop;

   for From_State in Quality_Manager.Model.Work_State loop
      for To_State in Quality_Manager.Model.Work_State loop
         declare
            Permitted : constant Boolean := Quality_Manager.Transitions.Allowed
              (From_State, To_State);
         begin
            Assert
              (Permitted = Quality_Manager.Transitions.Allowed (From_State, To_State),
               "work transition table is deterministic");
         end;
      end loop;
   end loop;
   Validation := Quality_Manager.Transitions.Validate (Discovered, Published);
   Assert
     (Validation.Kind = Quality_Manager.Results.Invalid_Request,
      "invalid nonterminal transition has an explicit diagnostic");

   declare
      Values : constant array (Positive range <>) of Natural :=
        [0, 99, 100, 199, 200, 299, 300, 399, 400, 499, 500];
   begin
      for Value of Values loop
         declare
            Class : constant Quality_Manager.Priorities.Priority_Class :=
              Quality_Manager.Priorities.From_Persisted_Priority (Value);
            Expected : constant Quality_Manager.Priorities.Priority_Class :=
              (case Value is
                 when 0 .. 99    => Quality_Manager.Priorities.Long_Standing_Deficiency,
                 when 100 .. 199 => Quality_Manager.Priorities.Campaign_Work,
                 when 200 .. 299 => Quality_Manager.Priorities.New_Regression,
                 when 300 .. 399 => Quality_Manager.Priorities.Security_Or_Correctness,
                 when 400 .. 499 => Quality_Manager.Priorities.Release_Blocker,
                 when others     => Quality_Manager.Priorities.Critical_Regression);
         begin
            Assert
              (Class = Expected,
               "persisted priority mapping is total");
         end;
      end loop;
   end;
   Assert
     (Quality_Manager.Priorities.Before
        ((To_Unbounded_String ("b"), Quality_Manager.Priorities.Critical_Regression, 2),
         (To_Unbounded_String ("a"), Quality_Manager.Priorities.Release_Blocker, 1)),
      "priority class orders before age");
   Assert
     (Quality_Manager.Priorities.Before
        ((To_Unbounded_String ("b"), Quality_Manager.Priorities.Campaign_Work, 1),
         (To_Unbounded_String ("a"), Quality_Manager.Priorities.Campaign_Work, 2)),
      "age orders within a priority class");
   Assert
     (Quality_Manager.Priorities.Before
        ((To_Unbounded_String ("a"), Quality_Manager.Priorities.Campaign_Work, 1),
         (To_Unbounded_String ("b"), Quality_Manager.Priorities.Campaign_Work, 1)),
      "stable identity breaks equal-priority ties");

   declare
      Schema_Check : Quality_Manager.Storage.Schema.Metadata;
   begin
      Assert (Schema_Check.Schema_Version = 1, "logical schema version is explicit");
   end;
   Assert (Quality_Manager.Storage.Migrations.Can_Migrate (0, 1), "initial schema migration is registered");
   Validation := Quality_Manager.Storage.Migrations.Validate_Current (1);
   Assert (Validation.Kind = Quality_Manager.Results.Success, "current schema is accepted");
   Validation := Quality_Manager.Storage.Migrations.Validate_Current (2);
   Assert (Validation.Kind = Quality_Manager.Results.Incompatible_Contract, "newer schema is rejected");
   Validation := Quality_Manager.Storage.Migrations.Validate_Current (0);
   Assert (Validation.Kind = Quality_Manager.Results.Not_Ready, "older schema requires a migration");
end Test_Transitions_And_Journal;

