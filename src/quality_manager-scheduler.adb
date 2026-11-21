with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Quality_Manager.Identities;
with Quality_Manager.Model;

package body Quality_Manager.Scheduler is
   use type Quality_Manager.Model.Work_State;
   use type Quality_Manager.Results.Result_Kind;
   use type Quality_Manager.Storage.Record_Kind;

   type Queue_Entry is record
      Candidate        : Quality_Manager.Priorities.Candidate;
      Project_Resource : Unbounded_String;
      Resource         : Work_Resource := Agent_Resource;
   end record;

   package Queue_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Queue_Entry);

   type Scheduler_State is record
      Scheduler_Id   : Positive;
      Pending_Items  : Queue_Vectors.Vector;
      Active_Items   : Queue_Vectors.Vector;
      Stop_Requested : Boolean := False;
   end record;

   package State_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Scheduler_State);

   protected Queue_State is
      procedure New_Scheduler (Scheduler_Id : out Positive);
      procedure Delete_Scheduler (Scheduler_Id : Positive);
      procedure Reset (Scheduler_Id : Positive);
      procedure Clear_Pending (Scheduler_Id : Positive);
      procedure Insert (Scheduler_Id : Positive; Value : Queue_Entry);
      procedure Remove_Pending (Scheduler_Id : Positive; Work_Id : String);
      procedure Take
        (Scheduler_Id     : Positive;
         Assessment_Limit : Positive;
         Agent_Limit      : Positive;
         Value            : out Queue_Entry;
         Found            : out Boolean);
      procedure Release (Scheduler_Id : Positive; Work_Id : String);
      procedure Stop (Scheduler_Id : Positive);
      procedure Resume (Scheduler_Id : Positive);
      function Stopping (Scheduler_Id : Positive) return Boolean;
      function Pending (Scheduler_Id : Positive) return Natural;
      function Active (Scheduler_Id : Positive; Resource : Work_Resource) return Natural;
   private
      States : State_Vectors.Vector;
      Next_Scheduler_Id : Natural := 1;
   end Queue_State;

   protected body Queue_State is
      function Find (Scheduler_Id : Positive) return Natural is
      begin
         for Index in States.First_Index .. States.Last_Index loop
            if States (Index).Scheduler_Id = Scheduler_Id then
               return Index;
            end if;
         end loop;
         return 0;
      end Find;

      procedure New_Scheduler (Scheduler_Id : out Positive) is
      begin
         if Next_Scheduler_Id = 0 then
            raise Constraint_Error with "scheduler identity space exhausted";
         end if;
         Scheduler_Id := Positive (Next_Scheduler_Id);
         if Next_Scheduler_Id = Natural (Positive'Last) then
            Next_Scheduler_Id := 0;
         else
            Next_Scheduler_Id := Next_Scheduler_Id + 1;
         end if;
         States.Append
           (Scheduler_State'
              (Scheduler_Id => Scheduler_Id, Pending_Items => <>, Active_Items => <>,
               Stop_Requested => False));
      end New_Scheduler;

      procedure Delete_Scheduler (Scheduler_Id : Positive) is
         Index : constant Natural := Find (Scheduler_Id);
      begin
         if Index > 0 then
            States.Delete (Index);
         end if;
      end Delete_Scheduler;

      procedure Reset (Scheduler_Id : Positive) is
         Index : constant Natural := Find (Scheduler_Id);
      begin
         if Index > 0 then
            States (Index).Pending_Items.Clear;
            States (Index).Active_Items.Clear;
            States (Index).Stop_Requested := False;
         end if;
      end Reset;

      procedure Clear_Pending (Scheduler_Id : Positive) is
         Index : constant Natural := Find (Scheduler_Id);
      begin
         if Index > 0 then
            States (Index).Pending_Items.Clear;
         end if;
      end Clear_Pending;

      procedure Insert (Scheduler_Id : Positive; Value : Queue_Entry) is
         Index : constant Natural := Find (Scheduler_Id);
      begin
         if Index = 0 then
            return;
         end if;
         for Current of States (Index).Pending_Items loop
            if Current.Candidate.Work_Id = Value.Candidate.Work_Id then
               return;
            end if;
         end loop;
         for Current of States (Index).Active_Items loop
            if Current.Candidate.Work_Id = Value.Candidate.Work_Id then
               return;
            end if;
         end loop;
         States (Index).Pending_Items.Append (Value);
      end Insert;

      procedure Remove_Pending (Scheduler_Id : Positive; Work_Id : String) is
         State_Index : constant Natural := Find (Scheduler_Id);
      begin
         if State_Index = 0 then
            return;
         end if;
         for Index in States (State_Index).Pending_Items.First_Index
           .. States (State_Index).Pending_Items.Last_Index
         loop
            if To_String (States (State_Index).Pending_Items (Index).Candidate.Work_Id) = Work_Id then
               States (State_Index).Pending_Items.Delete (Index);
               return;
            end if;
         end loop;
      end Remove_Pending;

      function Resource_Available
        (State_Index      : Positive;
         Value            : Queue_Entry;
         Assessment_Limit : Positive;
         Agent_Limit      : Positive) return Boolean is
         Count : Natural := 0;
      begin
         for Current of States (State_Index).Active_Items loop
            if Current.Resource = Value.Resource then
               Count := Count + 1;
            end if;
            if Current.Project_Resource = Value.Project_Resource
              and then Value.Resource in Agent_Resource | Integration_Resource
              and then Current.Resource in Agent_Resource | Integration_Resource
            then
               return False;
            end if;
         end loop;
         case Value.Resource is
            when Assessment_Resource => return Count < Assessment_Limit;
            when Agent_Resource      => return Count < Agent_Limit;
            when Integration_Resource => return Count < 1;
         end case;
      end Resource_Available;

      procedure Take
        (Scheduler_Id     : Positive;
         Assessment_Limit : Positive;
         Agent_Limit      : Positive;
         Value            : out Queue_Entry;
         Found            : out Boolean) is
         Best : Positive := 1;
         Have_Best : Boolean := False;
         State_Index : constant Natural := Find (Scheduler_Id);
      begin
         Found := False;
         if State_Index = 0 or else States (State_Index).Stop_Requested then
            return;
         end if;
         for Index in States (State_Index).Pending_Items.First_Index
           .. States (State_Index).Pending_Items.Last_Index
         loop
            if Resource_Available
              (State_Index, States (State_Index).Pending_Items (Index), Assessment_Limit, Agent_Limit)
              and then
                (not Have_Best
                 or else Quality_Manager.Priorities.Before
                   (States (State_Index).Pending_Items (Index).Candidate,
                    States (State_Index).Pending_Items (Best).Candidate))
            then
               Best := Index;
               Have_Best := True;
            end if;
         end loop;
         if Have_Best then
            Value := States (State_Index).Pending_Items (Best);
            States (State_Index).Pending_Items.Delete (Best);
            States (State_Index).Active_Items.Append (Value);
            Found := True;
         end if;
      end Take;

      procedure Release (Scheduler_Id : Positive; Work_Id : String) is
         State_Index : constant Natural := Find (Scheduler_Id);
      begin
         if State_Index = 0 then
            return;
         end if;
         for Index in States (State_Index).Active_Items.First_Index
           .. States (State_Index).Active_Items.Last_Index
         loop
            if To_String (States (State_Index).Active_Items (Index).Candidate.Work_Id) = Work_Id then
               States (State_Index).Active_Items.Delete (Index);
               return;
            end if;
         end loop;
      end Release;

      procedure Stop (Scheduler_Id : Positive) is
         Index : constant Natural := Find (Scheduler_Id);
      begin
         if Index > 0 then
            States (Index).Stop_Requested := True;
         end if;
      end Stop;

      procedure Resume (Scheduler_Id : Positive) is
         Index : constant Natural := Find (Scheduler_Id);
      begin
         if Index > 0 then
            States (Index).Stop_Requested := False;
         end if;
      end Resume;

      function Stopping (Scheduler_Id : Positive) return Boolean is
         Index : constant Natural := Find (Scheduler_Id);
      begin
         return Index > 0 and then States (Index).Stop_Requested;
      end Stopping;

      function Pending (Scheduler_Id : Positive) return Natural is
         Index : constant Natural := Find (Scheduler_Id);
      begin
         return (if Index = 0 then 0 else Natural (States (Index).Pending_Items.Length));
      end Pending;

      function Active (Scheduler_Id : Positive; Resource : Work_Resource) return Natural is
         Result : Natural := 0;
         Index  : constant Natural := Find (Scheduler_Id);
      begin
         if Index > 0 then
            for Value of States (Index).Active_Items loop
               if Value.Resource = Resource then
                  Result := Result + 1;
               end if;
            end loop;
         end if;
         return Result;
      end Active;
   end Queue_State;

   procedure Evaluate_Eligibility
     (Facts  : Eligibility_Facts;
      Ready  : out Boolean;
      Reason : out Unbounded_String) is
   begin
      Ready := False;
      if not Facts.Project_Enabled then Reason := To_Unbounded_String ("project-disabled");
      elsif not Facts.Project_Identity_Valid then Reason := To_Unbounded_String ("project-identity-invalid");
      elsif not Facts.Task_Nonterminal then Reason := To_Unbounded_String ("task-terminal");
      elsif not Facts.Dependencies_Satisfied then Reason := To_Unbounded_String ("dependencies-unsatisfied");
      elsif not Facts.Evidence_Applicable then Reason := To_Unbounded_String ("evidence-not-applicable");
      elsif not Facts.Plan_Current then Reason := To_Unbounded_String ("plan-revision-stale");
      elsif not Facts.Approval_Valid then Reason := To_Unbounded_String ("approval-missing-or-stale");
      elsif not Facts.Native_Task_Ready then Reason := To_Unbounded_String ("native-task-not-ready");
      elsif not Facts.Budget_Available then Reason := To_Unbounded_String ("resource-budget-exhausted");
      elsif not Facts.Project_Lock_Available then Reason := To_Unbounded_String ("project-lock-unavailable");
      elsif not Facts.Autonomy_Permits then Reason := To_Unbounded_String ("authorization-required");
      else
         Ready := True;
         Reason := Null_Unbounded_String;
      end if;
   end Evaluate_Eligibility;

   procedure Initialize (Item : in out Scheduler_Type) is
      New_Id : Positive;
   begin
      if Item.Scheduler_Id = 0 then
         Queue_State.New_Scheduler (New_Id);
         Item.Scheduler_Id := New_Id;
      else
         Queue_State.Reset (Positive (Item.Scheduler_Id));
      end if;
      Item.Database := null;
      Item.Status := Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success);
   end Initialize;

   procedure Configure
     (Item               : in out Scheduler_Type;
      Store              : Store_Access;
      Assessment_Workers : Positive := 4;
      Agent_Workers      : Positive := 1) is
   begin
      Item.Database := Store;
      Item.Assessment_Workers := Assessment_Workers;
      Item.Agent_Workers := Agent_Workers;
      Item.Status := Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success);
   end Configure;

   procedure Enqueue_Work
     (Item             : in out Scheduler_Type;
      Work_Id          : String;
      Project_Resource : String;
      Class            : Quality_Manager.Priorities.Priority_Class;
      Eligible_At      : Interfaces.Unsigned_64;
      Resource         : Work_Resource) is
   begin
      if Item.Scheduler_Id = 0 then
         Item.Status := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Not_Ready, "scheduler is not initialized", "qm.scheduler.not-initialized");
         return;
      elsif Work_Id'Length = 0 or else Project_Resource'Length = 0 then
         Item.Status := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Invalid_Request, "queued work requires stable identities", "qm.scheduler.identity");
         return;
      end if;
      Queue_State.Insert
        (Positive (Item.Scheduler_Id),
         (Candidate =>
            (Work_Id => To_Unbounded_String (Work_Id), Class => Class, Eligible_At => Eligible_At),
          Project_Resource => To_Unbounded_String (Project_Resource),
          Resource => Resource));
      Item.Status := Quality_Manager.Results.Make_Result (Quality_Manager.Results.Success);
   end Enqueue_Work;

   function JSON_Natural (Document, Name : String) return Natural is
      Prefix : constant String := Character'Val (34) & Name & Character'Val (34) & ":";
      First  : Natural := Ada.Strings.Fixed.Index (Document, Prefix);
      Last   : Natural;
   begin
      if First = 0 then
         return 0;
      end if;
      First := First + Prefix'Length;
      Last := First;
      while Last <= Document'Last and then Document (Last) in '0' .. '9' loop
         Last := Last + 1;
      end loop;
      return Natural'Value (Document (First .. Last - 1));
   exception
      when Constraint_Error => return 0;
   end JSON_Natural;

   function JSON_String (Document, Name : String) return String is
      Prefix : constant String :=
        Character'Val (34) & Name & Character'Val (34) & ":" & Character'Val (34);
      First  : Natural := Ada.Strings.Fixed.Index (Document, Prefix);
      Last   : Natural;
   begin
      if First = 0 then
         return "";
      end if;
      First := First + Prefix'Length;
      Last := First;
      while Last <= Document'Last and then Document (Last) /= Character'Val (34) loop
         Last := Last + 1;
      end loop;
      if Last > Document'Last then
         return "";
      end if;
      return Document (First .. Last - 1);
   end JSON_String;

   function Project_Resource (Document : String) return String is
      Id : constant Natural := JSON_Natural (Document, "quality_project_id");
   begin
      return
        "quality-project:" & JSON_String (Document, "quality_database_id") & ":"
        & Ada.Strings.Fixed.Trim (Natural'Image (Id), Ada.Strings.Both);
   end Project_Resource;

   procedure Evaluate_And_Queue
     (Item    : in out Scheduler_Type;
      Work_Id : String;
      Facts   : Eligibility_Facts) is
      Ready  : Boolean;
      Reason : Unbounded_String;
      Entity : Quality_Manager.Storage.Stored_Entity;
      Result : Quality_Manager.Results.Operation_Result;
      Event  : Unbounded_String;
   begin
      Evaluate_Eligibility (Facts, Ready, Reason);
      if Ready then
         Enqueue (Item, Work_Id);
         return;
      elsif Item.Database = null then
         Item.Status := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Not_Ready, To_String (Reason), "qm.scheduler.ineligible");
         return;
      end if;
      Quality_Manager.Storage.Read (Item.Database.all, Work_Id, Entity, Result);
      if Result.Kind /= Quality_Manager.Results.Success then
         Item.Status := Result;
         return;
      end if;
      Event := To_Unbounded_String
        ("event:eligibility:"
         & Quality_Manager.Identities.Canonical_Digest
             ([Quality_Manager.Identities.Text_Value (Work_Id),
               Quality_Manager.Identities.Text_Value (To_String (Reason)),
               Quality_Manager.Identities.Number_Value (Entity.Generation)]));
      Quality_Manager.Storage.Transition_Work
        (Item.Database.all, Work_Id, Quality_Manager.Model.Queued, Quality_Manager.Model.Blocked,
         To_String (Event), "scheduler-eligibility", To_String (Reason), Result);
      if Result.Kind = Quality_Manager.Results.Success then
         Queue_State.Remove_Pending (Positive (Item.Scheduler_Id), Work_Id);
      end if;
      Item.Status := Result;
   end Evaluate_And_Queue;

   procedure Enqueue
     (Item    : in out Scheduler_Type;
      Work_Id : String) is
      Entity : Quality_Manager.Storage.Stored_Entity;
      Result : Quality_Manager.Results.Operation_Result;
      Priority : Natural;
   begin
      if Item.Database = null then
         Item.Status := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Not_Ready, "scheduler has no coordinator store", "qm.scheduler.not-configured");
         return;
      end if;
      Quality_Manager.Storage.Read (Item.Database.all, Work_Id, Entity, Result);
      if Result.Kind /= Quality_Manager.Results.Success then
         Item.Status := Result;
         return;
      elsif Entity.Kind /= Quality_Manager.Storage.Work_Item_Record
        or else To_String (Entity.State) /= Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Queued)
      then
         Item.Status := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Not_Ready, "work is not durably queued", "qm.scheduler.work-not-ready");
         return;
      end if;
      Priority := JSON_Natural (To_String (Entity.Payload), "priority");
      Enqueue_Work
        (Item, Work_Id, Project_Resource (To_String (Entity.Payload)),
         Quality_Manager.Priorities.From_Persisted_Priority (Priority), Entity.Generation,
         (if Ada.Strings.Fixed.Index (To_String (Entity.Payload), "__assessment__") > 0
          then Assessment_Resource else Agent_Resource));
   end Enqueue;

   procedure Dispatch_Due (Item : in out Scheduler_Type) is
      Values : Quality_Manager.Storage.Entity_Vectors.Vector;
      Result : Quality_Manager.Results.Operation_Result;
   begin
      if Item.Database = null then
         Item.Status := Quality_Manager.Results.Make_Result
           (Quality_Manager.Results.Not_Ready, "scheduler has no coordinator store", "qm.scheduler.not-configured");
         return;
      end if;
      Queue_State.Clear_Pending (Positive (Item.Scheduler_Id));
      Quality_Manager.Storage.List
        (Item.Database.all, Quality_Manager.Storage.Work_Item_Record, Values, 100_000, Result);
      if Result.Kind /= Quality_Manager.Results.Success then
         Item.Status := Result;
         return;
      end if;
      for Entity of Values loop
         if To_String (Entity.State) = Quality_Manager.Model.Work_State'Image (Quality_Manager.Model.Queued) then
            Enqueue (Item, To_String (Entity.Entity_Key));
            exit when Item.Status.Kind /= Quality_Manager.Results.Success;
         end if;
      end loop;
      if Item.Status.Kind = Quality_Manager.Results.Success then
         Item.Status := Result;
      end if;
   end Dispatch_Due;

   procedure Reconcile (Item : in out Scheduler_Type) is
   begin
      Dispatch_Due (Item);
   end Reconcile;

   procedure Take_Next
     (Item     : in out Scheduler_Type;
      Work_Id  : out Unbounded_String;
      Resource : out Work_Resource;
      Found    : out Boolean) is
      Value : Queue_Entry;
   begin
      Work_Id := Null_Unbounded_String;
      Resource := Agent_Resource;
      if Item.Scheduler_Id = 0 then
         Found := False;
         return;
      end if;
      Queue_State.Take
        (Positive (Item.Scheduler_Id), Item.Assessment_Workers, Item.Agent_Workers, Value, Found);
      if Found then
         Work_Id := Value.Candidate.Work_Id;
         Resource := Value.Resource;
      end if;
   end Take_Next;

   procedure Complete (Item : in out Scheduler_Type; Work_Id : String) is
   begin
      if Item.Scheduler_Id > 0 then
         Queue_State.Release (Positive (Item.Scheduler_Id), Work_Id);
      end if;
   end Complete;

   function Pending_Count (Item : Scheduler_Type) return Natural is
     (if Item.Scheduler_Id = 0 then 0 else Queue_State.Pending (Positive (Item.Scheduler_Id)));
   function Active_Count (Item : Scheduler_Type; Resource : Work_Resource) return Natural is
     (if Item.Scheduler_Id = 0 then 0
      else Queue_State.Active (Positive (Item.Scheduler_Id), Resource));
   function Last_Result (Item : Scheduler_Type) return Quality_Manager.Results.Operation_Result is (Item.Status);
   procedure Request_Stop (Item : in out Scheduler_Type) is
   begin
      if Item.Scheduler_Id > 0 then
         Queue_State.Stop (Positive (Item.Scheduler_Id));
      end if;
   end Request_Stop;
   procedure Resume (Item : in out Scheduler_Type) is
   begin
      if Item.Scheduler_Id > 0 then
         Queue_State.Resume (Positive (Item.Scheduler_Id));
      end if;
   end Resume;
   procedure Shutdown (Item : in out Scheduler_Type) is
   begin
      if Item.Scheduler_Id > 0 then
         Queue_State.Delete_Scheduler (Positive (Item.Scheduler_Id));
         Item.Scheduler_Id := 0;
      end if;
   end Shutdown;
   function Is_Stopping (Item : Scheduler_Type) return Boolean is
     (Item.Scheduler_Id > 0 and then Queue_State.Stopping (Positive (Item.Scheduler_Id)));
end Quality_Manager.Scheduler;
