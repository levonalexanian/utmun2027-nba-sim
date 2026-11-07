let ( let* ) = Lwt.bind

let env_int name ~default =
  match Sys.getenv_opt name with
  | Some v -> ( try int_of_string v with Failure _ -> default)
  | None -> default

(* The SQLite file. Prisma (db/) creates and migrates it; the Makefile and the
   EC2 both set DB_PATH. *)
let db_path =
  match Sys.getenv_opt "DB_PATH" with
  | Some p when p <> "" -> p
  | _ -> failwith "DB_PATH must be set to the SQLite file"

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

  let enable_wal =
    Caqti_request.Infix.(Caqti_type.unit ->! Caqti_type.string)
      "PRAGMA journal_mode=WAL"
end

(* WAL lets reads run during a write. It is stored in the file, so once at
   startup is enough. *)
let enable_wal () =
  Lwt_main.run
    (let* r =
       Caqti_lwt_unix.with_connection (Uri.of_string db_uri)
         (fun (module Db : Caqti_lwt.CONNECTION) -> Db.find Q.enable_wal ())
     in
     let* mode = or_fail r in
     Dream.log "SQLite %s, journal_mode=%s" db_path mode;
     Lwt.return_unit)

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
  enable_wal ();
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
