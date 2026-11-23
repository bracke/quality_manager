separate (Quality_Manager.Verification)
procedure Decode_Improve
     (Response         : Quality_Manager.Integrations.JSON_CLI.Response;
      Expected_Task_Id : String;
      Evidence         : out Improve_Evidence;
      Result           : out Operation_Result) is
      Document : Jsonlib.Documents.Document;
      Version  : Natural;
      Command  : Unbounded_String;

      function Header_Is_Valid
        (Root, Data : Jsonlib.Documents.Node) return Boolean is
        (Natural_Field (Document, Root, "schema_version", Version)
         and then Version = 2
         and then String_Field (Document, Root, "command", Command)
         and then To_String (Command) = "verify"
         and then Jsonlib.Documents.Is_Present (Data)
         and then Document.Kind (Data) = Jsonlib.Documents.Object_Value);

      function Summary_Is_Valid
        (Data  : Jsonlib.Documents.Node;
         Tasks : Jsonlib.Documents.Node) return Boolean is
         Plan_Outcome : Unbounded_String;
         Explanation  : Unbounded_String;
      begin
         return String_Field (Document, Data, "plan_id", Evidence.Plan_Id)
           and then Natural_Field (Document, Data, "baseline_run", Evidence.Baseline_Run)
           and then Natural_Field (Document, Data, "verification_run", Evidence.Verification_Run)
           and then String_Field (Document, Data, "outcome", Evidence.Outcome)
           and then String_Field (Document, Data, "plan_outcome", Plan_Outcome)
           and then String_Field (Document, Data, "project_outcome", Evidence.Project_Outcome)
           and then Boolean_Field (Document, Data, "comparable", Evidence.Comparable)
           and then Natural_Field (Document, Data, "new_critical", Evidence.New_Critical)
           and then String_Field (Document, Data, "explanation", Explanation)
           and then Jsonlib.Documents.Is_Present (Tasks)
           and then Document.Kind (Tasks) = Jsonlib.Documents.Array_Value;
      end Summary_Is_Valid;

      function Read_Task
        (Item    : Jsonlib.Documents.Node;
         Task_Id : out Unbounded_String;
         Outcome : out Unbounded_String) return Boolean is
         Explanation : Unbounded_String;
         Matched     : Natural;
         Total       : Natural;
      begin
         return Document.Kind (Item) = Jsonlib.Documents.Object_Value
           and then String_Field (Document, Item, "task_id", Task_Id)
           and then String_Field (Document, Item, "outcome", Outcome)
           and then Natural_Field (Document, Item, "matched", Matched)
           and then Natural_Field (Document, Item, "total", Total)
           and then String_Field (Document, Item, "explanation", Explanation);
      end Read_Task;

      procedure Process_Tasks
        (Tasks  : Jsonlib.Documents.Node;
         Failed : out Boolean) is
      begin
         Failed := False;
         for Index in 1 .. Document.Length (Tasks) loop
            declare
               Item    : constant Jsonlib.Documents.Node := Document.Element (Tasks, Index);
               Task_Id : Unbounded_String;
               Outcome : Unbounded_String;
            begin
               if not Read_Task (Item, Task_Id, Outcome) then
                  Result := Make_Result
                    (Incompatible_Contract, "Improve task verification is malformed", "qm.verification.improve-task");
                  Failed := True;
                  return;
               elsif To_String (Task_Id) = Expected_Task_Id then
                  if Evidence.Task_Found then
                     Result := Make_Result
                       (Integrity_Error, "Improve returned duplicate task results", "qm.verification.task-duplicate");
                     Failed := True;
                     return;
                  end if;
                  Evidence.Task_Found := True;
                  Evidence.Task_Id := Task_Id;
                  Evidence.Task_Outcome := Outcome;
               end if;
            end;
         end loop;
      end Process_Tasks;
   begin
      Evidence := (others => <>);
      if Response.Status.Kind not in Success | Negative_Result then
         Result := Response.Status;
         return;
      end if;
      Parse (To_String (Response.Document), Document, Result);
      if Result.Kind /= Success then
         return;
      end if;
      declare
         Root : constant Jsonlib.Documents.Node := Document.Root;
         Data : constant Jsonlib.Documents.Node := Document.Member (Root, "data");
      begin
         if not Header_Is_Valid (Root, Data) then
            Result := Make_Result
              (Incompatible_Contract, "Improve verification data is missing", "qm.verification.improve");
            return;
         end if;
         declare
            Tasks : constant Jsonlib.Documents.Node := Document.Member (Data, "tasks");
            Failed : Boolean;
         begin
            if not Summary_Is_Valid (Data, Tasks) then
               Result := Make_Result
                 (Incompatible_Contract, "Improve verification is incomplete", "qm.verification.improve");
               return;
            end if;
            Process_Tasks (Tasks, Failed);
            if Failed then
               return;
            end if;
         end;
      end;
      Result := Make_Result (Success);
   exception
      when others =>  --  AQ: audited exception boundary
         Evidence := (others => <>);
         Result := Make_Result
           (Incompatible_Contract, "invalid Improve verification", "qm.verification.improve");
   end Decode_Improve;
