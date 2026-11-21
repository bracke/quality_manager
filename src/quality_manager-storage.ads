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

package Quality_Manager.Storage is
   Current_Schema_Version : constant Positive := 1;

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

   type Stored_Entity is record
      Internal_Id : Positive := 1;
      Kind        : Record_Kind := Metadata_Record;
      Entity_Key  : Ada.Strings.Unbounded.Unbounded_String;
      State       : Ada.Strings.Unbounded.Unbounded_String;
      Payload     : Ada.Strings.Unbounded.Unbounded_String;
      Terminal    : Boolean := False;
      Generation  : Interfaces.Unsigned_64 := 0;
   end record;

   package Entity_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Stored_Entity);

   type Store is limited private;

   procedure Open
     (Item     : in out Store;
      Path     : String;
      Writable : Boolean;
      Result   : out Quality_Manager.Results.Operation_Result);

   procedure Close
     (Item   : in out Store;
      Result : out Quality_Manager.Results.Operation_Result);

   function Is_Open (Item : Store) return Boolean;
   function Identity (Item : Store) return String;

   procedure Put
     (Item   : in out Store;
      Value  : Stored_Entity;
      Result : out Quality_Manager.Results.Operation_Result);

   procedure Read
     (Item       : in out Store;
      Entity_Key : String;
      Value      : out Stored_Entity;
      Result     : out Quality_Manager.Results.Operation_Result);

   procedure Transition_Work
     (Item           : in out Store;
      Work_Key       : String;
      Expected_State : Quality_Manager.Model.Work_State;
      New_State      : Quality_Manager.Model.Work_State;
      Event_Key      : String;
      Cause          : String;
      Evidence       : String;
      Result         : out Quality_Manager.Results.Operation_Result);

   procedure Acquire_Lease
     (Item               : in out Store;
      Resource_Key       : String;
      Owner              : String;
      Expected_Generation : Interfaces.Unsigned_64;
      New_Generation     : Interfaces.Unsigned_64;
      Expires_At         : Interfaces.Unsigned_64;
      Result             : out Quality_Manager.Results.Operation_Result);

   procedure Prepare_Operation
     (Item           : in out Store;
      Operation      : Quality_Manager.Identities.Operation_Id;
      Operation_Kind : String;
      Intent         : String;
      External_Id    : String;
      Result         : out Quality_Manager.Results.Operation_Result);

   procedure Advance_Operation
     (Item           : in out Store;
      Operation      : Quality_Manager.Identities.Operation_Id;
      Expected_State : Quality_Manager.Journal.Journal_State;
      New_State      : Quality_Manager.Journal.Journal_State;
      External_Id    : String;
      Diagnostic     : String;
      Result         : out Quality_Manager.Results.Operation_Result);

   procedure Recovery_Entries
     (Item    : in out Store;
      Entries : out Entity_Vectors.Vector;
      Maximum : Positive;
      Result  : out Quality_Manager.Results.Operation_Result);

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
end Quality_Manager.Storage;
