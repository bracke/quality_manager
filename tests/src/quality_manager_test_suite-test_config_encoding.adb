separate (Quality_Manager_Test_Suite)
procedure Test_Config_Encoding (Item : in out Fixture) is
   pragma Unreferenced (Item);
   Settings : Quality_Manager.Config.Settings;
   Result   : Quality_Manager.Results.Operation_Result;
begin
   Write_Invalid_UTF_8;
   Quality_Manager.Config.Load (Base_Path, True, Settings, Result);
   Assert (Result.Kind = Quality_Manager.Results.Invalid_Request, "invalid UTF-8 is rejected");
   Assert (not Quality_Manager.Config.Is_Valid_UTF_8 (Character'Val (16#C0#) & Character'Val (16#AF#)),
           "overlong UTF-8 is rejected");
   Assert (Quality_Manager.Config.Is_Valid_UTF_8 ("quality"), "ASCII is valid UTF-8");
   Assert
     (Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#C2#) & Character'Val (16#A2#)),
      "valid two-byte UTF-8 is accepted");
   Assert
     (Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#E0#) & Character'Val (16#A0#) & Character'Val (16#80#))
      and then Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#E1#) & Character'Val (16#80#) & Character'Val (16#80#))
      and then Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#ED#) & Character'Val (16#9F#) & Character'Val (16#BF#)),
      "valid three-byte UTF-8 ranges are accepted");
   Assert
     (Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#F0#) & Character'Val (16#90#)
         & Character'Val (16#80#) & Character'Val (16#80#))
      and then Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#F1#) & Character'Val (16#80#)
         & Character'Val (16#80#) & Character'Val (16#80#))
      and then Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#F4#) & Character'Val (16#8F#)
         & Character'Val (16#BF#) & Character'Val (16#BF#)),
      "valid four-byte UTF-8 ranges are accepted");
   Assert
     (not Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#E0#) & Character'Val (16#80#) & Character'Val (16#80#))
      and then not Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#E1#) & Character'Val (16#41#) & Character'Val (16#80#))
      and then not Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#ED#) & Character'Val (16#A0#) & Character'Val (16#80#)),
      "invalid three-byte UTF-8 ranges are rejected");
   Assert
     (not Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#F0#) & Character'Val (16#80#)
         & Character'Val (16#80#) & Character'Val (16#80#))
      and then not Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#F1#) & Character'Val (16#41#)
         & Character'Val (16#80#) & Character'Val (16#80#))
      and then not Quality_Manager.Config.Is_Valid_UTF_8
        (Character'Val (16#F4#) & Character'Val (16#90#)
         & Character'Val (16#80#) & Character'Val (16#80#)),
      "invalid four-byte UTF-8 ranges are rejected");
   Remove_Test_File;
end Test_Config_Encoding;

