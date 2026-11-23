separate (Quality_Manager.Campaigns)
procedure Reconcile
     (Item : in out Context; Campaign_Id : String; Result : out Operation_Result) is
      Campaign : Quality_Manager.Storage.Schema.Campaign;
      Targets  : Quality_Manager.Storage.Entity_Vectors.Vector;
      Required : Natural := 0;
      Satisfied : Natural := 0;
   begin
      Load_Campaign (Item, Campaign_Id, Campaign, Result);
      if Result.Kind /= Success then return; end if;
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Campaign_Target_Record, Targets, 100_000, Result);
      if Result.Kind /= Success then return; end if;
      for Target of Targets loop
         if JSON_String (To_String (Target.Payload), "campaign_id") = Campaign_Id
           and then JSON_Natural (To_String (Target.Payload), "definition_revision")
             = Campaign.Definition_Revision
         then
            Required := Required + 1;
            if Ada.Strings.Fixed.Index (To_String (Target.State), "satisfied@") = 1 then
               Satisfied := Satisfied + 1;
            end if;
         end if;
      end loop;
      if Required = 0 then
         Result := Make_Result (Integrity_Error, "campaign has no current targets", "qm.campaign.targets");
         return;
      elsif Satisfied = Required then
         Campaign.State := Quality_Manager.Model.Verified;
      elsif Campaign.Budget > 0 and then Campaign.Used >= Campaign.Budget then
         Campaign.State := Quality_Manager.Model.Blocked;
      elsif Campaign.State /= Quality_Manager.Model.Blocked then
         Campaign.State := Quality_Manager.Model.Queued;
      end if;
      Quality_Manager.Storage.Records.Save (Item.Database.all, Campaign, Result);
   end Reconcile;
