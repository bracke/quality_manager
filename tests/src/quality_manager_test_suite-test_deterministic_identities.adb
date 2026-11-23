separate (Quality_Manager_Test_Suite)
procedure Test_Deterministic_Identities (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Project : constant Quality_Manager.Identities.Project_Key :=
     (To_Unbounded_String ("database-a"), 7, To_Unbounded_String ("/project"));
   First : constant String := Quality_Manager.Identities.Work_Identity
     (Project, 3, "AQ-01" & ASCII.LF & "AQ-02", "maintenance:cycle-1");
   Again : constant String := Quality_Manager.Identities.Work_Identity
     (Project, 3, "AQ-01" & ASCII.LF & "AQ-02", "maintenance:cycle-1");
   Campaign : constant String := Quality_Manager.Identities.Work_Identity
     (Project, 3, "AQ-01" & ASCII.LF & "AQ-02", "campaign:coverage");
   Global : constant String := Quality_Manager.Identities.Global_Remediation_Identity
     (Project, 3, "AQ-01" & ASCII.LF & "AQ-02");
begin
   Assert (First'Length = 64, "SHA-256 identity uses 64 lowercase hex digits");
   Assert (First = Again, "logical identity is deterministic");
   Assert (First /= Campaign, "workflow objectives retain distinct identities");
   Assert (Global /= First and then Global /= Campaign, "global remediation identity is separately framed");
   Assert
     (Quality_Manager.Identities.Operation_Identity ("assessment", First) /= 0
      and then Quality_Manager.Identities.Operation_Identity ("assessment", First)
        = Quality_Manager.Identities.Operation_Identity ("assessment", First)
      and then Quality_Manager.Identities.Operation_Identity ("assessment", First)
        /= Quality_Manager.Identities.Operation_Identity ("publication", First),
      "operation identities are deterministic, nonzero, and purpose-qualified");
   Assert
     (Quality_Manager.Identities.Execution_Identity
        (Quality_Manager.Identities.Dispatch_Identity (First, "plan", 2, "task"), 1)
      /= Quality_Manager.Identities.Execution_Identity
        (Quality_Manager.Identities.Dispatch_Identity (First, "plan", 2, "task"), 2),
      "attempt number participates in execution identity");
end Test_Deterministic_Identities;

