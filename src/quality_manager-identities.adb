with Ada.Streams;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with CryptoLib.Hashes;

package body Quality_Manager.Identities is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_64;

   function Equal (Left, Right : Project_Key) return Boolean is
     (Left.Quality_Database_Id = Right.Quality_Database_Id
      and then Left.Quality_Project_Id = Right.Quality_Project_Id
      and then Left.Canonical_Path = Right.Canonical_Path);

   function Text_Value (Value : String) return Identity_Field is
     (Kind => Text_Field, Text => To_Unbounded_String (Value));

   function Number_Value (Value : Interfaces.Unsigned_64) return Identity_Field is
     (Kind => Number_Field, Number => Value);

   function Canonical_Digest (Fields : Identity_Field_Array) return String is
      use Ada.Streams;
      Total : Natural := 0;
   begin
      for Field of Fields loop
         Total := Total + 1 + 8
           + (case Field.Kind is
                 when Text_Field   => Length (Field.Text),
                 when Number_Field => 8);
      end loop;

      declare
         Data   : Stream_Element_Array (1 .. Stream_Element_Offset (Total));
         Cursor : Stream_Element_Offset := Data'First;

         procedure Append_Byte (Value : Natural) is
         begin
            Data (Cursor) := Stream_Element (Value);
            Cursor := Cursor + 1;
         end Append_Byte;

         procedure Append_Unsigned (Value : Interfaces.Unsigned_64) is
         begin
            for Shift in reverse 0 .. 7 loop
               Append_Byte
                 (Natural
                    (Interfaces.Shift_Right (Value, Shift * 8)
                     and Interfaces.Unsigned_64 (16#FF#)));
            end loop;
         end Append_Unsigned;

         Digest     : CryptoLib.Hashes.SHA256_Digest;
         Hex        : String (1 .. 64);
         Hex_Digits : constant String := "0123456789abcdef";
         Position   : Positive := Hex'First;
      begin
         for Field of Fields loop
            Append_Byte (Field_Kind'Pos (Field.Kind) + 1);
            case Field.Kind is
               when Text_Field =>
                  declare
                     Value : constant String := To_String (Field.Text);
                  begin
                     Append_Unsigned (Interfaces.Unsigned_64 (Value'Length));
                     for Character_Value of Value loop
                        Append_Byte (Character'Pos (Character_Value));
                     end loop;
                  end;
               when Number_Field =>
                  Append_Unsigned (8);
                  Append_Unsigned (Field.Number);
            end case;
         end loop;

         Digest := CryptoLib.Hashes.SHA256 (Data);
         for Byte of Digest loop
            Hex (Position) := Hex_Digits (Natural (Byte) / 16 + 1);
            Hex (Position + 1) := Hex_Digits (Natural (Byte) mod 16 + 1);
            Position := Position + 2;
         end loop;
         return Hex;
      end;
   end Canonical_Digest;

   function Work_Identity
     (Project                 : Project_Key;
      Assessment_Run         : Positive;
      Normalized_Finding_Set : String;
      Workflow_Scope         : String) return String is
   begin
      return Canonical_Digest
        ([Number_Value (1),
          Text_Value (To_String (Project.Quality_Database_Id)),
          Number_Value (Interfaces.Unsigned_64 (Project.Quality_Project_Id)),
          Number_Value (Interfaces.Unsigned_64 (Assessment_Run)),
          Text_Value (Normalized_Finding_Set),
          Text_Value (Workflow_Scope)]);
   end Work_Identity;

   function Global_Remediation_Identity
     (Project                 : Project_Key;
      Assessment_Run         : Positive;
      Normalized_Finding_Set : String) return String is
   begin
      return Canonical_Digest
        ([Number_Value (1),
          Text_Value (To_String (Project.Quality_Database_Id)),
          Number_Value (Interfaces.Unsigned_64 (Project.Quality_Project_Id)),
          Number_Value (Interfaces.Unsigned_64 (Assessment_Run)),
          Text_Value (Normalized_Finding_Set)]);
   end Global_Remediation_Identity;

   function Dispatch_Identity
     (Work_Identity : String;
      Plan_Id       : String;
      Plan_Revision : Positive;
      Task_Id       : String) return String is
   begin
      return Canonical_Digest
        ([Text_Value (Work_Identity),
          Text_Value (Plan_Id),
          Number_Value (Interfaces.Unsigned_64 (Plan_Revision)),
          Text_Value (Task_Id)]);
   end Dispatch_Identity;

   function Execution_Identity
     (Dispatch_Identity : String;
      Attempt_Number    : Positive) return String is
   begin
      return Canonical_Digest
        ([Text_Value (Dispatch_Identity),
          Number_Value (Interfaces.Unsigned_64 (Attempt_Number))]);
   end Execution_Identity;
end Quality_Manager.Identities;
