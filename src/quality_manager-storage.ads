with Ada.Finalization;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Database;
with Database.Schema;
with Interfaces;
with Quality_Manager.Identities;
with Quality_Manager.Model;
with Quality_Manager.Journal;
with Quality_Manager.Results;

--  Provides transactional persistent coordinator storage.
package Quality_Manager.Storage is
   --  Public contract for this Quality Manager unit.
   Current_Schema_Version : constant Positive := 1;
   --  Current Schema Version.

   type Record_Kind is
     (Metadata_Record,
      Project_Record,
      Cycle_Record,
      Work_Item_Record,
      Dispatch_Record,
      Attempt_Record,
      Lease_Record,
      Journal_Record,
      Approval_Record,
      Campaign_Record,
      Campaign_Target_Record,
      Release_Record,
      Verification_Record,
      Event_Record);
   --  Record Kind values.
   --  @enum Metadata_Record Metadata Record.
   --  @enum Project_Record Project Record.
   --  @enum Cycle_Record Cycle Record.
   --  @enum Work_Item_Record Work Item Record.
   --  @enum Dispatch_Record Dispatch Record.
   --  @enum Attempt_Record Attempt Record.
   --  @enum Lease_Record Lease Record.
   --  @enum Journal_Record Journal Record.
   --  @enum Approval_Record Approval Record.
   --  @enum Campaign_Record Campaign Record.
   --  @enum Campaign_Target_Record Campaign Target Record.
   --  @enum Release_Record Release Record.
   --  @enum Verification_Record Verification Record.
   --  @enum Event_Record Event Record.

   type Stored_Entity is record
      Internal_Id : Positive := 1;
      Kind        : Record_Kind := Metadata_Record;
      Entity_Key  : Ada.Strings.Unbounded.Unbounded_String;
      State       : Ada.Strings.Unbounded.Unbounded_String;
      Payload     : Ada.Strings.Unbounded.Unbounded_String;
      Terminal    : Boolean := False;
      Generation  : Interfaces.Unsigned_64 := 0;
   end record;
   --  Stored Entity record.
   --  @field Internal_Id Internal Id.
   --  @field Kind Kind.
   --  @field Entity_Key Entity Key.
   --  @field State State.
   --  @field Payload Payload.
   --  @field Terminal Terminal.
   --  @field Generation Generation.

   package Entity_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Stored_Entity);
   --  Entity Vectors container.

   type Store is limited private;
   --  Store domain value.

   procedure Open
     (Item     : in out Store;
      Path     : String;
      Writable : Boolean;
      Result   : out Quality_Manager.Results.Operation_Result);
   --  Perform Open.
   --  @param Item Item.
   --  @param Path Path.
   --  @param Writable Writable.
   --  @param Result Result.

   procedure Close
     (Item   : in out Store;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Close.
   --  @param Item Item.
   --  @param Result Result.

   function Is_Open (Item : Store) return Boolean;
   --  Return Is Open.
   --  @param Item Item.
   --  @return Is Open result.
   function Identity (Item : Store) return String;
   --  Return Identity.
   --  @param Item Item.
   --  @return Identity result.

   procedure Put
     (Item   : in out Store;
      Value  : Stored_Entity;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Put.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Put_Current
     (Item   : in out Store;
      Value  : Stored_Entity;
      Result : out Quality_Manager.Results.Operation_Result);
   --  Perform Put Current.
   --  @param Item Item.
   --  @param Value Value.
   --  @param Result Result.

   procedure Read
     (Item       : in out Store;
      Entity_Key : String;
      Value      : out Stored_Entity;
      Result     : out Quality_Manager.Results.Operation_Result);
   --  Perform Read.
   --  @param Item Item.
   --  @param Entity_Key Entity Key.
   --  @param Value Value.
   --  @param Result Result.

   procedure List
     (Item    : in out Store;
      Kind    : Record_Kind;
      Values  : out Entity_Vectors.Vector;
      Maximum : Positive;
      Result  : out Quality_Manager.Results.Operation_Result);
   --  Perform List.
   --  @param Item Item.
   --  @param Kind Kind.
   --  @param Values Values.
   --  @param Maximum Maximum.
   --  @param Result Result.

   procedure Transition_Work
     (Item           : in out Store;
      Work_Key       : String;
      Expected_State : Quality_Manager.Model.Work_State;
      New_State      : Quality_Manager.Model.Work_State;
      Event_Key      : String;
      Cause          : String;
      Evidence       : String;
      Result         : out Quality_Manager.Results.Operation_Result);
   --  Perform Transition Work.
   --  @param Item Item.
   --  @param Work_Key Work Key.
   --  @param Expected_State Expected State.
   --  @param New_State New State.
   --  @param Event_Key Event Key.
   --  @param Cause Cause.
   --  @param Evidence Evidence.
   --  @param Result Result.

   procedure Complete_Cycle
     (Item           : in out Store;
      Cycle_Key      : String;
      Expected_State : Quality_Manager.Model.Work_State;
      Event_Key      : String;
      Cause          : String;
      Evidence       : String;
      Result         : out Quality_Manager.Results.Operation_Result);
   --  Perform Complete Cycle.
   --  @param Item Item.
   --  @param Cycle_Key Cycle Key.
   --  @param Expected_State Expected State.
   --  @param Event_Key Event Key.
   --  @param Cause Cause.
   --  @param Evidence Evidence.
   --  @param Result Result.

   procedure Acquire_Lease
     (Item               : in out Store;
      Resource_Key       : String;
      Owner              : String;
      Expected_Generation : Interfaces.Unsigned_64;
      New_Generation     : Interfaces.Unsigned_64;
      Expires_At         : Interfaces.Unsigned_64;
      Result             : out Quality_Manager.Results.Operation_Result);
   --  Perform Acquire Lease.
   --  @param Item Item.
   --  @param Resource_Key Resource Key.
   --  @param Owner Owner.
   --  @param Expected_Generation Expected Generation.
   --  @param New_Generation New Generation.
   --  @param Expires_At Expires At.
   --  @param Result Result.

   procedure Acquire_Exclusive_Lease
     (Item         : in out Store;
      Resource_Key : String;
      Owner        : String;
      Now          : Interfaces.Unsigned_64;
      Expires_At   : Interfaces.Unsigned_64;
      Generation   : in out Interfaces.Unsigned_64;
      Result       : out Quality_Manager.Results.Operation_Result);
   --  Perform Acquire Exclusive Lease.
   --  @param Item Item.
   --  @param Resource_Key Resource Key.
   --  @param Owner Owner.
   --  @param Now Now.
   --  @param Expires_At Expires At.
   --  @param Generation Generation.
   --  @param Result Result.

   procedure Release_Lease
     (Item         : in out Store;
      Resource_Key : String;
      Owner        : String;
      Generation   : Interfaces.Unsigned_64;
      Result       : out Quality_Manager.Results.Operation_Result);
   --  Perform Release Lease.
   --  @param Item Item.
   --  @param Resource_Key Resource Key.
   --  @param Owner Owner.
   --  @param Generation Generation.
   --  @param Result Result.

   procedure Prepare_Operation
     (Item           : in out Store;
      Operation      : Quality_Manager.Identities.Operation_Id;
      Operation_Kind : String;
      Intent         : String;
      External_Id    : String;
      Result         : out Quality_Manager.Results.Operation_Result);
   --  Perform Prepare Operation.
   --  @param Item Item.
   --  @param Operation Operation.
   --  @param Operation_Kind Operation Kind.
   --  @param Intent Intent.
   --  @param External_Id External Id.
   --  @param Result Result.

   procedure Advance_Operation
     (Item           : in out Store;
      Operation      : Quality_Manager.Identities.Operation_Id;
      Expected_State : Quality_Manager.Journal.Journal_State;
      New_State      : Quality_Manager.Journal.Journal_State;
      External_Id    : String;
      Diagnostic     : String;
      Result         : out Quality_Manager.Results.Operation_Result);
   --  Perform Advance Operation.
   --  @param Item Item.
   --  @param Operation Operation.
   --  @param Expected_State Expected State.
   --  @param New_State New State.
   --  @param External_Id External Id.
   --  @param Diagnostic Diagnostic.
   --  @param Result Result.

   procedure Recovery_Entries
     (Item    : in out Store;
      Entries : out Entity_Vectors.Vector;
      Maximum : Positive;
      Result  : out Quality_Manager.Results.Operation_Result);
   --  Perform Recovery Entries.
   --  @param Item Item.
   --  @param Entries Entries.
   --  @param Maximum Maximum.
   --  @param Result Result.

private
   type Store is new Ada.Finalization.Limited_Controlled with record
      DB       : Database.Handle;
      Table    : Database.Schema.Table_Schema;
      Opened   : Boolean := False;
      Writable : Boolean := False;
      Store_Id : Ada.Strings.Unbounded.Unbounded_String;
      Next_Id  : Positive := 1;
   end record;

   overriding procedure Finalize (Item : in out Store);
   --  Close the underlying database handle during controlled finalization.
   --  @param Item Store being finalized.
end Quality_Manager.Storage;
