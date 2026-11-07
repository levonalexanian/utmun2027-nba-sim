let ( let* ) = Lwt.bind

let env_int name ~default =
  match Sys.getenv_opt name with
  | Some v -> ( try int_of_string v with Failure _ -> default)
  | None -> default

let required name =
  match Sys.getenv_opt name with
  | Some v when v <> "" -> v
  | _ -> failwith (name ^ " must be set")

(* The SQLite file, and Prisma's migrations (prisma/migrations), which the
   backend applies at start. The Makefile and the EC2 set both. *)
let db_path = required "DB_PATH"
let migrations_dir = required "MIGRATIONS_DIR"

let db_uri = "sqlite3:" ^ db_path

let or_fail = function
  | Ok x -> Lwt.return x
  | Error e -> Lwt.fail (Caqti_error.Exn e)

module Q = struct
  let list_teams =
    [%rapper
      get_many
        {sql| SELECT @int{id}, @string{name}, @int{wins} FROM "Team" ORDER BY name |sql}]

  (* A consistent copy of the whole database, taken while the app runs. *)
  let vacuum_into = [%rapper execute {sql| VACUUM INTO %string{path} |sql}]
end

let migrate () =
  match Migrate.run ~db_path ~migrations_dir with
  | [] ->
      Dream.log "SQLite %s is up to date at %s" db_path
        (Migrate.head ~migrations_dir)
  | applied ->
      List.iter (Dream.log "Applied the migration %s") applied
  | exception Migrate.Error msg ->
      prerr_endline ("Cannot migrate the database: " ^ msg);
      exit 1

let timestamp () =
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02dT%02d%02d%02dZ" (t.tm_year + 1900) (t.tm_mon + 1)
    t.tm_mday t.tm_hour t.tm_min t.tm_sec

let list_teams req =
  let* teams =
    Dream.sql req (fun db ->
        let* r = Q.list_teams () db in
        or_fail r)
  in
  let team (id, name, wins) =
    `Assoc [ ("id", `Int id); ("name", `String name); ("wins", `Int wins) ]
  in
  Dream.json (Yojson.Safe.to_string (`List (List.map team teams)))

(* GET /api/admin/dump with "Authorization: Bearer $ADMIN_TOKEN": downloads a
   snapshot of the SQLite database. Disabled (404) when ADMIN_TOKEN is unset. *)
let dump req =
  match Sys.getenv_opt "ADMIN_TOKEN" with
  | None | Some "" -> Dream.empty `Not_Found
  | Some token when Dream.header req "Authorization" <> Some ("Bearer " ^ token)
    ->
      Dream.empty `Unauthorized
  | Some _ ->
      let name = Printf.sprintf "nba-sim-%s.db" (timestamp ()) in
      let path = Filename.concat (Filename.get_temp_dir_name ()) name in
      let* () =
        Dream.sql req (fun db ->
            let* r = Q.vacuum_into ~path db in
            or_fail r)
      in
      let data = In_channel.with_open_bin path In_channel.input_all in
      Sys.remove path;
      Dream.respond
        ~headers:
          [
            ("Content-Type", "application/vnd.sqlite3");
            ( "Content-Disposition",
              Printf.sprintf "attachment; filename=\"%s\"" name );
          ]
        data

(* In production the backend also serves the built frontend from STATIC_DIR. *)
let static_routes =
  match Sys.getenv_opt "STATIC_DIR" with
  | Some dir -> [ Dream.get "/**" (Dream.static dir) ]
  | None -> []

let () =
  migrate ();
  Dream.run ~interface:"0.0.0.0" ~port:(env_int "PORT" ~default:8080)
  @@ Dream.logger
  (* One connection: SQLite has a single writer, and the load is small. *)
  @@ Dream.sql_pool ~size:1 db_uri
  @@ Dream.router
       ([
          Dream.get "/api/health" (fun _ -> Dream.json {|{"status":"ok"}|});
          Dream.get "/api/teams" list_teams;
          Dream.get "/api/admin/dump" dump;
        ]
       @ static_routes)
