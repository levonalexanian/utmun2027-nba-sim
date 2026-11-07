(* The migrations at start.

   The migrations are Prisma's (prisma/migrations): a folder per migration,
   applied in name order. The app has no Node and no Prisma, so it applies
   them itself, and records each in Prisma's own table _prisma_migrations,
   with the same columns, checksum, and timestamps as prisma migrate deploy.
   So prisma migrate status, run against the same file, tells the truth.

   Everything runs in one BEGIN IMMEDIATE transaction: SQLite's DDL is
   transactional, so a failed migration changes nothing and records nothing,
   and a second process that starts at the same time waits for the first. *)

type migration = { name : string; sql : string; checksum : string }

exception Error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt

(* The table of prisma migrate deploy, as Prisma makes it for SQLite. *)
let create_migrations_table =
  {|CREATE TABLE IF NOT EXISTS "_prisma_migrations" (
    "id"                    TEXT PRIMARY KEY NOT NULL,
    "checksum"              TEXT NOT NULL,
    "finished_at"           DATETIME,
    "migration_name"        TEXT NOT NULL,
    "logs"                  TEXT,
    "rolled_back_at"        DATETIME,
    "started_at"            DATETIME NOT NULL DEFAULT current_timestamp,
    "applied_steps_count"   INTEGER UNSIGNED NOT NULL DEFAULT 0
)|}

let migration_file = "migration.sql"

(** The migrations of [dir], in name order, as prisma migrate deploy reads
    them: each folder is a migration and holds migration.sql. The files
    beside the folders, such as migration_lock.toml, are not migrations. *)
let read_migrations dir =
  if not (Sys.file_exists dir && Sys.is_directory dir) then
    fail "the migrations folder %s does not exist" dir;
  let all =
    Sys.readdir dir |> Array.to_list
    |> List.filter (fun name -> Sys.is_directory (Filename.concat dir name))
    |> List.sort String.compare
    |> List.map (fun name ->
           let path = Filename.concat (Filename.concat dir name) migration_file in
           if not (Sys.file_exists path) then
             fail "the migration %s has no %s" name migration_file;
           let sql = In_channel.with_open_bin path In_channel.input_all in
           let checksum = Digestif.SHA256.(digest_string sql |> to_hex) in
           { name; sql; checksum })
  in
  if all = [] then fail "the app has no migration in %s" dir;
  all

(* --- SQLite helpers --- *)

let check db what rc =
  match rc with
  | Sqlite3.Rc.OK | Sqlite3.Rc.DONE -> ()
  | rc ->
      fail "%s: %s (%s)" what (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)

let exec db what sql = check db what (Sqlite3.exec db sql)

(** Runs [sql] with the text parameters [params], and returns the rows, each
    an array of its columns as text ([None] for NULL). *)
let query db what sql params =
  let stmt = Sqlite3.prepare db sql in
  List.iteri
    (fun i p -> check db what (Sqlite3.bind_text stmt (i + 1) p))
    params;
  let rec rows acc =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let row =
          Array.init (Sqlite3.data_count stmt) (fun i ->
              match Sqlite3.column stmt i with
              | Sqlite3.Data.NULL -> None
              | d -> Some (Sqlite3.Data.to_string_coerce d))
        in
        rows (row :: acc)
    | Sqlite3.Rc.DONE -> List.rev acc
    | rc -> check db what rc; List.rev acc
  in
  let result = rows [] in
  check db what (Sqlite3.finalize stmt);
  result

let now_ms () = Int64.of_float (Unix.gettimeofday () *. 1000.)

(* A random version 4 UUID, as Prisma gives each record. *)
let uuid () =
  let b = Bytes.init 16 (fun _ -> Char.chr (Random.int 256)) in
  Bytes.set b 6 (Char.chr (0x40 lor (Char.code (Bytes.get b 6) land 0x0f)));
  Bytes.set b 8 (Char.chr (0x80 lor (Char.code (Bytes.get b 8) land 0x3f)));
  let h = Bytes.to_string b |> String.to_seq
          |> Seq.map (fun c -> Printf.sprintf "%02x" (Char.code c))
          |> List.of_seq |> String.concat "" in
  Printf.sprintf "%s-%s-%s-%s-%s" (String.sub h 0 8) (String.sub h 8 4)
    (String.sub h 12 4) (String.sub h 16 4) (String.sub h 20 12)

(* --- The checks of _prisma_migrations --- *)

type applied = {
  a_name : string;
  a_checksum : string;
  finished : bool;
  rolled_back : bool;
}

let read_applied db =
  query db "read _prisma_migrations"
    {|SELECT migration_name, checksum, finished_at IS NOT NULL, rolled_back_at IS NOT NULL
      FROM "_prisma_migrations" ORDER BY started_at, migration_name|}
    []
  |> List.map (fun row ->
         let text i = Option.value row.(i) ~default:"" in
         {
           a_name = text 0;
           a_checksum = text 1;
           finished = text 2 = "1";
           rolled_back = text 3 = "1";
         })

(** The names of the migrations that the database has. A row that Prisma
    marked as rolled back does not count, as for prisma migrate deploy. Fails
    on a failed migration that is not resolved, an applied migration that
    [all] does not have, and an applied migration whose file changed. *)
let applied_migrations db all =
  List.fold_left
    (fun done_ record ->
      if record.rolled_back then done_
      else if not record.finished then
        fail
          "the migration %s failed in the database and is not resolved: \
           repair the database, then mark it with prisma migrate resolve"
          record.a_name
      else
        match List.find_opt (fun m -> m.name = record.a_name) all with
        | None ->
            fail
              "the database has the migration %s, which this build does not \
               have: run a build that has it"
              record.a_name
        | Some m when m.checksum <> record.a_checksum ->
            fail
              "the migration %s changed after the database applied it: \
               restore its file, and write a new migration instead"
              m.name
        | Some m -> m.name :: done_)
    [] (read_applied db)

let record db m ~started =
  ignore
    (query db
       ("record " ^ m.name)
       {|INSERT INTO "_prisma_migrations"
           (id, checksum, finished_at, migration_name, started_at, applied_steps_count)
         VALUES (?1, ?2, ?3, ?4, ?5, 1)|}
       [
         uuid ();
         m.checksum;
         Int64.to_string (now_ms ());
         m.name;
         Int64.to_string started;
       ])

(** Upgrades the SQLite file [db_path] to the latest migration of
    [migrations_dir]. Returns the names of the migrations that it applied, in
    order (empty when the database was up to date). *)
let run ~db_path ~migrations_dir =
  Random.self_init ();
  let all = read_migrations migrations_dir in
  let db = Sqlite3.db_open db_path in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.db_close db))
    (fun () ->
      Sqlite3.busy_timeout db 5000;
      (* WAL lets reads run during a write; it is stored in the file. *)
      exec db "enable WAL" "PRAGMA journal_mode=WAL";
      exec db "begin" "BEGIN IMMEDIATE";
      let upgrade () =
        exec db "make the table _prisma_migrations" create_migrations_table;
        let done_ = applied_migrations db all in
        List.filter_map
          (fun m ->
            if List.mem m.name done_ then None
            else
              let started = now_ms () in
              exec db ("apply " ^ m.name) m.sql;
              record db m ~started;
              Some m.name)
          all
      in
      match upgrade () with
      | applied ->
          exec db "commit" "COMMIT";
          applied
      | exception e ->
          ignore (Sqlite3.exec db "ROLLBACK");
          raise e)

(** The name of the latest migration, such as 20261107144946_init. *)
let head ~migrations_dir =
  let all = read_migrations migrations_dir in
  (List.nth all (List.length all - 1)).name
