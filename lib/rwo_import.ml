open Core.Std
module Lang = Rwo_lang
module Html = Rwo_html

module T = struct
  type t = {
    href : string;
    part : float option;
    alt : string option;
    childs : Rwo_html.item list;
  } [@@deriving sexp]

  (* Ignore [childs]. *)
  let compare (x:t) (y:t) =
    compare (x.href, x.part) (y.href, y.part)

end
include T
include Comparable.Make(T)

let lang_of t =
  match Filename.split_extension t.href with
  | _, None ->
    error "href missing file extension" t.href sexp_of_string
  | _, Some ext ->
    Lang.of_string ext |> fun x ->
    Or_error.tag_arg x "invalid file extension" t.href sexp_of_string

let is_import_html = function
  | `Data _ -> false
  | `Element {Html.name="link"; attrs; _} -> (
    match List.Assoc.find attrs "rel" with
    | Some "import" -> true
    | Some _
    | None -> false
  )
  | `Element _ -> false

let of_html item =
  let open Result.Monad_infix in
  if not (is_import_html item) then
    error "attempting to parse non-import node as an import node"
      item Html.sexp_of_item
  else (
    match item with
    | `Element {name="link"; attrs; childs} -> (
      let find x = List.Assoc.find attrs x in
      Html.check_attrs attrs
        ~required:["href"; "rel"]
        ~allowed:(`Some ["part"; "alt"])
      >>= fun () ->

      (
        try Ok (find "part" |> Option.map ~f:Float.of_string)
        with exn -> error "invalid part" exn sexp_of_exn
      ) >>= fun part ->

      let ans =
      {
        href = Option.value_exn (find "href");
        part;
	alt = find "alt";
        childs;
      }
      in

      lang_of ans >>= fun _ -> (* validate language *)

      Ok ans
    )
    | `Element _
    | `Data _ ->
      assert false
  )
;;

let to_html x =
  [
    Some ("rel", "import");
    Some ("href", x.href);
    (Option.map x.part ~f:(fun x -> "part", Float.to_string x));
    (Option.map x.alt ~f:(fun x -> "alt", x));
  ]
  |> List.filter_map ~f:ident
  |> fun a -> Html.link ~a []

let find_all html =
  let rec loop accum = function
    | [] -> accum
    | (`Data _)::rest ->
      loop accum rest
    | (`Element {Html.childs;_} as item)::rest ->
      let accum =
        if is_import_html item
        then (ok_exn (of_html item))::accum
        else accum
      in
      loop (loop accum childs) rest
  in
  loop [] html
