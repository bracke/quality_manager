with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Quality_Manager.Identities;
with Quality_Manager.Integrations.Quality;
with Quality_Manager.Journal;
with Quality_Manager.Results;
with Quality_Manager.Storage;

--  Reconciles interrupted coordinator and upstream operations.
package Quality_Manager.Recovery is
   --  Public contract for this Quality Manager unit.
   type Recovery_Item is record
      Operation_Key : Ada.Strings.Unbounded.Unbounded_String;
      State         : Quality_Manager.Journal.Journal_State;
      Action        : Quality_Manager.Journal.Recovery_Action;
   end record;
   --  Recovery Item record.
   --  @field Operation_Key Operation Key.
   --  @field State State.
   --  @field Action Action.

   package Recovery_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Recovery_Item);
   --  Recovery Vectors container.

   procedure Reconstruct
     (Store   : in out Quality_Manager.Storage.Store;
      Maximum : Positive;
      Work    : out Recovery_Vectors.Vector;
      Result  : out Quality_Manager.Results.Operation_Result);
   --  Perform Reconstruct.
   --  @param Store Store.
   --  @param Maximum Maximum.
   --  @param Work Work.
   --  @param Result Result.

   procedure Reconcile_Assessment
     (Store     : in out Quality_Manager.Storage.Store;
      Quality   : Quality_Manager.Integrations.Quality.Adapter;
      Operation : Quality_Manager.Identities.Operation_Id;
      Run       : Positive;
      Result    : out Quality_Manager.Results.Operation_Result);
   --  Perform Reconcile Assessment.
   --  @param Store Store.
   --  @param Quality Quality.
   --  @param Operation Operation.
   --  @param Run Run.
   --  @param Result Result.
end Quality_Manager.Recovery;
