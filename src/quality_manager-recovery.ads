with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Quality_Manager.Journal;
with Quality_Manager.Results;
with Quality_Manager.Storage;

package Quality_Manager.Recovery is
   type Recovery_Item is record
      Operation_Key : Ada.Strings.Unbounded.Unbounded_String;
      State         : Quality_Manager.Journal.Journal_State;
      Action        : Quality_Manager.Journal.Recovery_Action;
   end record;

   package Recovery_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Recovery_Item);

   procedure Reconstruct
     (Store   : in out Quality_Manager.Storage.Store;
      Maximum : Positive;
      Work    : out Recovery_Vectors.Vector;
      Result  : out Quality_Manager.Results.Operation_Result);
end Quality_Manager.Recovery;
