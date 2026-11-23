separate (Quality_Manager.Releases)
procedure Create_Configured
  (Project_Selector : String;
   Profile          : String;
   Config_Path      : String;
   Config_Required  : Boolean) is
   Settings : Quality_Manager.Config.Settings;
   Store : aliased Quality_Manager.Storage.Store;
   Item : Context;
   Result, Close_Result : Operation_Result;
   Projects : Quality_Manager.Storage.Entity_Vectors.Vector;
   Project : Quality_Manager.Identities.Project_Key;
   Source, Policy, Toolchain : Unbounded_String;
   Found   : Boolean := False;
   Commit : Unbounded_String;
   Args : Quality_Manager.Integrations.Processes.String_Vectors.Vector;
   Release_Id : Unbounded_String;
   Quality : Quality_Manager.Integrations.Quality.Adapter;
   Plan    : Quality_Manager.Integrations.JSON_CLI.Response;
   function Selector_Matches (Id : Natural; Path : String) return Boolean is
   begin
      return Project_Selector = Path
        or else Project_Selector =
          Ada.Strings.Fixed.Trim (Natural'Image (Id), Ada.Strings.Both);
   end Selector_Matches;

   procedure Configure is
   begin
      if Profile /= "release" then
         Result := Make_Result
           (Invalid_Request, "the initial release qualifier requires the release profile",
            "qm.release.profile");
         return;
      end if;
      Quality_Manager.Config.Load (Config_Path, Config_Required, Settings, Result);
      if Result.Kind = Success and then Length (Settings.Quality_Database) = 0 then
         Result := Make_Result
           (Invalid_Request, "release creation requires an Ada Quality database",
            "qm.release.quality-database");
      end if;
      if Result.Kind = Success then
         Quality_Manager.Storage.Open
           (Store, To_String (Settings.Coordinator_Database), True, Result);
      end if;
      if Result.Kind = Success then
         Quality_Manager.Storage.List
           (Store, Quality_Manager.Storage.Project_Record, Projects, 100_000, Result);
      end if;
   end Configure;

   procedure Select_Project is
   begin
      for Entity of Projects loop
         declare
            Payload : constant String := To_String (Entity.Payload);
            Id      : constant Natural := JSON_Natural (Payload, "quality_project_id");
            Path    : constant String := JSON_String (Payload, "canonical_path");
         begin
            if To_String (Entity.State) = "ENABLED"
              and then Id > 0
              and then Selector_Matches (Id, Path)
            then
               if Found then
                  Result := Make_Result
                    (Invalid_Request, "release selector matches multiple projects",
                     "qm.release.selector");
                  return;
               end if;
               Found := True;
               Project :=
                 (To_Unbounded_String (JSON_String (Payload, "quality_database_id")),
                  Positive (Id), To_Unbounded_String (Path));
            end if;
         end;
      end loop;
      if not Found then
         Result := Make_Result (Not_Found, "release project not found", "qm.release.selector");
      end if;
   end Select_Project;

   procedure Load_Plan is
   begin
      Quality_Manager.Integrations.Quality.Initialize
        (Quality, To_String (Settings.Ada_Quality_Executable),
         To_String (Settings.Quality_Database), Policy_Path => To_String (Settings.Quality_Policy));
      Quality_Manager.Integrations.Quality.Plan_Check
        (Quality,
         Ada.Strings.Fixed.Trim
           (Positive'Image (Project.Quality_Project_Id), Ada.Strings.Both),
         Profile, False, Plan);
      Result := Plan.Status;
   end Load_Plan;

   procedure Decode_Plan_Project
     (Document     : Jsonlib.Documents.Document;
      Project_Node : Jsonlib.Documents.Node) is
      Id    : Natural := 0;
      Path  : Unbounded_String;
      Valid : Boolean := True;
   begin
      if Document.Kind (Project_Node) /= Jsonlib.Documents.Object_Value then Valid := False;
      end if;
      if not Natural_Field (Document, Project_Node, "project_id", Id) then Valid := False;
      elsif Id /= Project.Quality_Project_Id then Valid := False;
      end if;
      if not String_Field (Document, Project_Node, "path", Path) then Valid := False;
      elsif To_String (Path) /= To_String (Project.Canonical_Path) then Valid := False;
      end if;
      if not String_Field (Document, Project_Node, "source_fingerprint", Source) then Valid := False;
      elsif Length (Source) = 0 then Valid := False;
      end if;
      if not String_Field (Document, Project_Node, "policy_fingerprint", Policy) then Valid := False;
      elsif Length (Policy) = 0 then Valid := False;
      end if;
      if not String_Field (Document, Project_Node, "toolchain_fingerprint", Toolchain) then Valid := False;
      elsif Length (Toolchain) = 0 then Valid := False;
      end if;
      if not Valid then
         Result := Make_Result
           (Incompatible_Contract,
            "release assessment plan identity is incomplete or mismatched",
            "qm.release.plan");
      end if;
   end Decode_Plan_Project;

   procedure Decode_Plan is
      Document : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;
   begin
      Jsonlib.Parsers.Parse
        (To_String (Plan.Document), Document, Error,
         (Max_Depth => 32, Max_Length => 16 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Jsonlib.Errors.Failed (Error) then
         Result := Make_Result
           (Incompatible_Contract, "release assessment plan is invalid JSON",
            "qm.release.plan-json");
         return;
      end if;
      declare
         Project_Nodes : constant Jsonlib.Documents.Node :=
           Document.Member (Document.Root, "projects");
      begin
         if not Jsonlib.Documents.Is_Present (Project_Nodes) then
            Result := Make_Result
              (Incompatible_Contract, "release assessment plan must contain exactly one project",
               "qm.release.plan");
         elsif Document.Kind (Project_Nodes) /= Jsonlib.Documents.Array_Value then
            Result := Make_Result
              (Incompatible_Contract, "release assessment plan must contain exactly one project",
               "qm.release.plan");
         elsif Document.Length (Project_Nodes) /= 1 then
            Result := Make_Result
              (Incompatible_Contract, "release assessment plan must contain exactly one project",
               "qm.release.plan");
         else
            Decode_Plan_Project (Document, Document.Element (Project_Nodes, 1));
         end if;
      end;
   end Decode_Plan;

   procedure Read_Commit is
   begin
      Args.Append (To_Unbounded_String ("rev-parse"));
      Args.Append (To_Unbounded_String ("HEAD"));
      Execute_Simple ("git", Args, To_String (Project.Canonical_Path), Commit, Result);
   end Read_Commit;

   procedure Create_Release is
   begin
      Initialize (Item, Store'Unchecked_Access);
      Create
        (Item, Project, To_String (Commit), To_String (Source),
         To_String (Policy), To_String (Toolchain),
         Quality_Manager.Identities.Canonical_Digest
           ([Quality_Manager.Identities.Text_Value ("release-config"),
             Quality_Manager.Identities.Text_Value (Profile)]),
         Release_Id, Result);
   end Create_Release;
begin
   Configure;
   if Result.Kind = Success then
      Select_Project;
   end if;
   if Result.Kind = Success then
      Load_Plan;
   end if;
   if Result.Kind = Success then
      Decode_Plan;
   end if;
   if Result.Kind = Success then
      Read_Commit;
   end if;
   if Result.Kind = Success then
      Create_Release;
   end if;
   Quality_Manager.Storage.Close (Store, Close_Result);
   if Result.Kind = Success and then Close_Result.Kind /= Success then
      Result := Close_Result;
   end if;
   if Result.Kind /= Success then
      raise Release_Error with Message (Result);
   end if;
end Create_Configured;

