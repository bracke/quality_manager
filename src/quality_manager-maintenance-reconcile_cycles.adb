separate (Quality_Manager.Maintenance)
procedure Reconcile_Cycles
  (Item   : in out Context;
   Result : out Operation_Result) is
   Cycles : Quality_Manager.Storage.Entity_Vectors.Vector;
   Work   : Quality_Manager.Storage.Entity_Vectors.Vector;
   function Eligible_Cycle
     (Cycle : Quality_Manager.Storage.Stored_Entity) return Boolean is
      Key : constant String := To_String (Cycle.Entity_Key);
   begin
      return not Cycle.Terminal
        and then To_String (Cycle.State) =
          Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Queued)
        and then Key'Length > 6
        and then Key (Key'First .. Key'First + 5) = "cycle:";
   end Eligible_Cycle;

   function Terminal_State (State : Quality_Manager.Model.Work_State) return Boolean is
     (State in Quality_Manager.Model.Verified | Quality_Manager.Model.Inconclusive |
               Quality_Manager.Model.Blocked | Quality_Manager.Model.Needs_Intervention |
               Quality_Manager.Model.Failed | Quality_Manager.Model.Cancelled |
               Quality_Manager.Model.Superseded);

   procedure Process_Cycle
     (Cycle : Quality_Manager.Storage.Stored_Entity) is
      Key      : constant String := To_String (Cycle.Entity_Key);
      Cycle_Id : constant String := Key (Key'First + 6 .. Key'Last);
      Match    : Natural := 0;
      Work_Key : Unbounded_String;
      State    : Quality_Manager.Model.Work_State := Quality_Manager.Model.Discovered;
   begin
      for Candidate of Work loop
         if JSON_String (To_String (Candidate.Payload), "global_remediation") =
           "assessment:" & Cycle_Id
         then
            Match := Match + 1;
            Work_Key := Candidate.Entity_Key;
            begin
               State := Quality_Manager.Model.Work_State'Value (To_String (Candidate.State));
            exception
               when Constraint_Error =>
                  Result := Make_Result
                    (Incompatible_Contract, "cycle work has an unknown state",
                     "qm.maintenance.cycle-work-state");
                  return;
            end;
         end if;
      end loop;
      if Match > 1 then
         Result := Make_Result
           (Integrity_Error, "cycle identifies multiple assessment work items",
            "qm.maintenance.cycle-work");
      elsif Match = 1 and then Terminal_State (State) then
         Quality_Manager.Storage.Complete_Cycle
           (Item.Database.all, Key, Quality_Manager.Model.Queued,
            "event:" & Cycle_Id & ":maintenance:completed",
            "maintenance coordination pass completed",
            "work:" & To_String (Work_Key) & ":" &
              Quality_Manager.Model.Work_State'Image (State), Result);
      end if;
   end Process_Cycle;
begin
   if Item.Database = null then
      Result := Make_Result
        (Not_Ready, "maintenance context is not initialized", "qm.maintenance.context");
      return;
   end if;
   Quality_Manager.Storage.List
     (Item.Database.all, Quality_Manager.Storage.Cycle_Record, Cycles, 100_000, Result);
   if Result.Kind = Success then
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Work_Item_Record, Work, 100_000, Result);
   end if;
   if Result.Kind /= Success then
      return;
   end if;
   for Cycle of Cycles loop
      if Eligible_Cycle (Cycle) then
         Process_Cycle (Cycle);
         if Result.Kind /= Success then
            return;
         end if;
      end if;
   end loop;
   Result := Make_Result (Success);
end Reconcile_Cycles;

