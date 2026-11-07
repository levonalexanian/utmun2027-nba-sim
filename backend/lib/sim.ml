(* The simulation logic of the UTMUN 2027 NBA Committee: teams, players,
   the draft, and games. Pure OCaml, no database or HTTP, so it is easy to
   test. *)

type position = PG | SG | SF | PF | C

type player = {
  id : int;
  name : string;
  position : position;
  rating : int;  (** 0 to 100 *)
}

type team = {
  id : int;
  name : string;
  roster : player list;
  wins : int;
  losses : int;
}

(** A team's strength: the average rating of its best five players. *)
let strength team =
  let best =
    team.roster
    |> List.sort (fun (a : player) b -> compare b.rating a.rating)
    |> List.filteri (fun i _ -> i < 5)
  in
  match best with
  | [] -> 0.
  | ps ->
      float_of_int (List.fold_left (fun acc (p : player) -> acc + p.rating) 0 ps)
      /. float_of_int (List.length ps)

(** Draft order: worst record picks first. *)
let draft_order teams =
  List.sort
    (fun a b ->
      match compare a.wins b.wins with 0 -> compare b.losses a.losses | c -> c)
    teams

(** Runs a draft of [rounds] rounds. Each team in turn takes the best player
    left. Returns the teams with their new players, in draft order, and the
    players nobody picked. *)
let run_draft ~rounds teams prospects =
  let pool =
    List.sort (fun (a : player) b -> compare b.rating a.rating) prospects
  in
  let order = draft_order teams in
  let rec round n teams pool =
    if n = 0 then (teams, pool)
    else
      let teams, pool =
        List.fold_left
          (fun (picked, pool) team ->
            match pool with
            | [] -> (team :: picked, [])
            | best :: rest ->
                ({ team with roster = best :: team.roster } :: picked, rest))
          ([], pool) teams
      in
      round (n - 1) (List.rev teams) pool
  in
  round rounds order pool

(** Plays one game. The stronger team is more likely to win, never certain. *)
let play_game rng home away =
  let h = strength home +. 3. (* home court *) and a = strength away in
  let p_home = if h +. a = 0. then 0.5 else h /. (h +. a) in
  if Random.State.float rng 1. < p_home then
    ({ home with wins = home.wins + 1 }, { away with losses = away.losses + 1 })
  else
    ({ home with losses = home.losses + 1 }, { away with wins = away.wins + 1 })
