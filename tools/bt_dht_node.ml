(** standalone DHT node *)

open BT_DHT

let bracket res destroy k =
  let x = try k res with exn -> destroy res; raise exn in
  destroy res;
  x

let with_open_in_bin file = bracket (open_in_bin file) close_in_noerr
let with_open_out_bin file = bracket (open_out_bin file) close_out_noerr

let load file : Kademlia.table = with_open_in_bin file Marshal.from_channel

let store file (t:Kademlia.table) =
  let temp = file ^ ".tmp" in
  try
    with_open_out_bin temp (fun ch -> Marshal.to_channel ch t []; Unix2.fsync (Unix.descr_of_out_channel ch));
    Sys.rename temp file
  with exn ->
    lprintf_nl ~exn "write to %S failed" file; Sys.remove temp

let parse_peer s =
  try
    match String2.split s ':' with
    | [addr;port] -> addr, int_of_string port
    | _ -> raise Not_found
  with _ ->
    Printf.eprintf "E: bad peer %S, expecting <addr>:<port>\n%!" s;
    exit 2

let init file = try load file with _ -> Kademlia.create ()

let run_queries =
  let ids = [|
    "FA959F240D5859CAC30F32ECD21BD89F576481F0";
    "BDE98D04AB6BD6E8EA7440F82870E5191E130A84";
    "857224361969AE12066166539538F07BD5EF48B4";
    "81F643A195BBE3BB1DE1AC9184B9F84D74A37EFF";
    "7CC9963D90B54DF1710469743C1B43E0E20489C0";
    "C2C65A1AA5537406183F4D815C77A2A578B00BFB";
    "72F5A608AFBDF6111E5A86B337E9FC27D6020663";
    "FE73D74660695208F3ACD221B7A9A128A3D36D47";
  |] in
  fun dht ->
  let id = Kademlia.H.of_hexa ids.(Random.int (Array.length ids)) in
  query_peers dht id (fun node token peers ->
    lprintf_nl "run_queries : %s returned %d peers : %s"
      (show_node node) (List.length peers) (strl Kademlia.show_addr peers))

let () =
  Random.self_init ();
  try
    match List.tl (Array.to_list Sys.argv) with
    | file::port::peers ->
      let peers = List.map parse_peer peers in
      let bw = UdpSocket.new_bandwidth_controler 
        (TcpBufferedSocket.create_write_bandwidth_controler "UNLIMIT" 0) in
      let dht = start (init file) (int_of_string port) bw in
      let finish () = store file dht.M.rt; stop dht; exit 0 in
      Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ -> show dht; finish ()));
      Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> show dht; finish ()));
      Sys.set_signal Sys.sighup (Sys.Signal_handle (fun _ -> show dht));
      BasicSocket.add_infinite_timer 1800. (fun () -> run_queries dht);
      BasicSocket.add_infinite_timer 3600. (fun () -> store file dht.M.rt);
      let routers = ["router.bittorrent.com", 8991] @ peers in
      bootstrap dht ~routers;
      BasicSocket.loop ()
    | _ -> Printf.eprintf "Usage : %s <storage> <port> [<peer_addr:port>]*\n" Sys.argv.(0)
  with
    exn -> lprintf_nl "main : %s" (Printexc.to_string exn)

