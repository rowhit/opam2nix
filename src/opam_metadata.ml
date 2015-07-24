module URL = OpamFile.URL
module OPAM = OpamFile.OPAM
module Descr = OpamFile.Descr
open OpamTypes

type dependency =
	| NixDependency of string
	| OcamlDependency of OpamTypes.compiler_constraint
	| OsDependency of (bool * string) OpamTypes.generic_formula
	| ExternalDependencies of OpamTypes.tags
	| PackageDependencies of OpamTypes.ext_formula

type importance = Required | Optional
type requirement = importance * dependency

let rec iter_formula : 'a . (importance -> 'a -> unit) -> importance -> 'a OpamFormula.formula -> unit =
	fun iter_atom importance formula ->
		let recurse = iter_formula iter_atom in
		let open OpamFormula in
		match formula with
			| Empty -> ()
			| Atom a -> iter_atom importance a
			| Block b -> recurse importance b
			| And (a,b) -> recurse importance a; recurse importance b
			| Or(a,b) -> recurse Optional a; recurse Optional b

let string_of_dependency = function
	| NixDependency dep -> "nix:"^dep
	| OcamlDependency _ -> "ocaml:<TODO>"
	| OsDependency formula ->
			"os:" ^
				(OpamFormula.string_of_formula (fun (b,s) -> (string_of_bool b) ^","^s) formula)
	| ExternalDependencies tags ->
			"external:" ^
				(OpamMisc.StringSetMap.to_string (OpamMisc.StringSet.to_string) tags)
	| PackageDependencies formula ->
		(* of OpamTypes.ext_formula *)
		"package:<TODO>"

let string_of_requirement = function
	| Required, dep -> string_of_dependency dep
	| Optional, dep -> "{" ^ (string_of_dependency dep) ^ "}"

let add_nix_inputs
	~(add_native: importance -> string -> unit)
	~(add_opam:importance -> string -> unit)
	importance dep =
	let desc = match importance with
		| Required -> "dep"
		| Optional -> "optional dep"
	in
	(* let depend_on = add_input importance in *)
	match dep with
		| NixDependency name ->
				Printf.eprintf "  adding nix %s: %s\n" desc name;
				add_native importance name
		| OcamlDependency _dep ->
				Printf.eprintf "  adding ocaml %s: %s\n" desc "ocaml";
				add_native importance "ocaml" (* XXX ocaml version *)
		| OsDependency _dep ->
				Printf.eprintf "  adding OS %s: <TODO>\n" desc;
				Printf.eprintf "TODO: OsDependency\n"
		| ExternalDependencies externals ->
				let has_nix = ref false in
				OpamMisc.StringSetMap.iter (fun environments packages ->
					if OpamMisc.StringSet.mem "nixpkgs" environments then (
						has_nix := true;
						OpamMisc.StringSet.iter (fun dep ->
							Printf.eprintf "  adding nix %s: %s\n" desc dep;
							add_native importance dep
						) packages
					)
				) externals;
				if not !has_nix then
					Printf.eprintf
						"Note: package has depexts, but none of them `nixpkgs`:\n%s\n"
						(OpamMisc.StringSetMap.to_string (OpamMisc.StringSet.to_string) externals)
		| PackageDependencies formula ->
			let iter_dep importance (dep:OpamPackage.Name.t * (package_dep_flag list * OpamFormula.version_formula)) =
				let (name, (flags, version_formula)) = dep in
				let name = OpamPackage.Name.to_string name in
				let needed_for_build = if List.length flags = 0
					then true
					else flags |> List.fold_left (fun required flag ->
						required || (match flag with Depflag_Build -> true | _ -> false)) false
				in
				if needed_for_build then begin
					let version_desc = ref "" in
					version_formula |> iter_formula (fun _importance (relop, version) ->
						version_desc := !version_desc ^ (
							(OpamFormula.string_of_relop relop) ^
							(OpamPackage.Version.to_string version)
						)
					) importance;
					Printf.eprintf "  adding %s: %s%s\n" desc name !version_desc;
					add_opam importance name
				end else
					Printf.eprintf "  skipping non-build %s on %s\n" desc name
			in
			iter_formula iter_dep importance formula

(* type opam_package_id = { *)
(* 	opam_name: string; *)
(* 	opam_version: OpamTypes.version; *)
(* } *)
(*  *)
(* module OpamPackageOrd = struct *)
(* 	type t = opam_package_id *)
(* 	let compare a b = *)
(* 		let name_diff = String.compare a.opam_name b.opam_name in *)
(* 		if name_diff <> 0 *)
(* 			then name_diff *)
(* 			else OpamPackage.Version.compare (a.opam_version) (b.opam_version) *)
(* end *)

module PackageMap = OpamPackage.Map

(* module Deps = struct *)
(* 	type t = dependency list PackageMap.t *)
(* 	let add t package_id dep = *)
(* 		let existing = try PackageMap.find package_id with Not_found -> [] in *)
(* 		PackageMap.add package_id (dep :: existing) t *)
(* end *)

class dependency_map =
	let map : requirement list PackageMap.t ref = ref PackageMap.empty in
	let get_existing package_id = try PackageMap.find package_id !map with Not_found -> [] in
	object
		method init_package package_id =
			let existing = get_existing package_id in
			map := PackageMap.add package_id existing !map

		method add_dep package_id (dep:requirement) =
			let existing = get_existing package_id in
			map := PackageMap.add package_id (dep :: existing) !map

		method to_string =
			let reqs_to_string = (fun reqs -> String.concat "," (List.map string_of_requirement reqs)) in
			PackageMap.to_string reqs_to_string !map
	end

(* let maybe_string s = match s with *)
(* 	| Some s -> `String s *)
(* 	| None -> `Null *)
(*  *)
(* let dump_json data = *)
(* 	let json_str = OpamJson.to_string data in *)
(* 	print_endline json_str *)
(*  *)
(* type json_obj = [`O of (string * OpamJson.t) list] *)
(*  *)
(* let json_of_os_constr cons : json_obj = *)
(* 	let (bool, str) = cons in *)
(* 	`O [ *)
(* 		("type", `String "os_constraint"); *)
(* 		("value", `A [ *)
(* 			`Bool bool; *)
(* 			`String str; *)
(* 		]); *)
(* 	] *)
(*  *)
(* let json_of_compiler_version_constraint cons : json_obj = *)
(* 	let (relop, ver) = cons in *)
(* 	`O [ *)
(* 		("type", `String "version"); *)
(* 		("op", `String (OpamFormula.string_of_relop relop)); *)
(* 		("version", OpamCompiler.Version.to_json ver); *)
(* 	] *)
(*  *)
(* let json_of_version_constraint (cons:OpamFormula.version_constraint) : json_obj = *)
(* 	let (relop, ver) = cons in *)
(* 	`O [ *)
(* 		("type", `String "version"); *)
(* 		("op", `String (OpamFormula.string_of_relop relop)); *)
(* 		("version", OpamPackage.Version.to_json ver); *)
(* 	] *)
(*  *)
(* type dep = (OpamPackage.Name.t * OpamFormula.version_formula) *)
(* let rec json_of_dependency (dep:dep) : json_obj = *)
(* 	let (name, version) = dep in *)
(* 	`O [ *)
(* 		("type", `String "dependency"); *)
(* 		("name", OpamPackage.Name.to_json name); *)
(* 		("constraints", json_of_formula json_of_version_constraint version); *)
(* 	] *)
(*  *)
(* and json_of_formula : 'a . ('a -> json_obj) -> 'a OpamFormula.formula -> OpamJson.t = *)
(* 	fun atom_to_json formula -> *)
(* 	let recurse = json_of_formula atom_to_json in *)
(* 	let open OpamFormula in *)
(* 	match formula with *)
(* 		| Empty -> `Null *)
(* 		| Atom f -> ((atom_to_json f):>OpamJson.t) *)
(* 		| Block f -> recurse f *)
(* 		| And (a,b) -> `A [`String "&&"; (recurse a); (recurse b)] *)
(* 		| Or (a,b) -> `A [`String "||"; (recurse a); (recurse b)] *)
(*  *)
(* let json_of_depends : dep OpamFormula.formula -> OpamJson.t = *)
(* 	json_of_formula json_of_dependency *)
(*  *)
(* let info_opam ic = *)
(* 	let file = OPAM.read_from_channel ic in *)
(* 	`O [ *)
(* 		("type", `String "opam"); *)
(* 		("ocaml_version", match (OPAM.ocaml_version file) with *)
(* 			| None -> `Null *)
(* 			| Some constr -> json_of_formula json_of_compiler_version_constraint constr *)
(* 		); *)
(* 		("os", json_of_formula json_of_os_constr (OPAM.os file)); *)
(* 		("depends", json_of_depends (OPAM.depends file)); *)
(* 		("depends_optional", json_of_depends (OPAM.depopts file)); *)
(* 		("depends_external", match OPAM.depexts file with *)
(* 			| None -> `Null *)
(* 			| Some deps -> *)
(* 				OpamMisc.StringSetMap.to_json OpamMisc.StringSet.to_json deps; *)
(* 		); *)
(* 		("conflicts", json_of_depends (OPAM.conflicts file)); *)
(* 	] *)
(*  *)
(* let info_descr ic = *)
(* 	let file = Descr.read_from_channel ic in *)
(* 	`O [ *)
(* 		("type", `String "descr"); *)
(* 		("summary", `String (Descr.synopsis file)); *)
(* 		("description", `String (Descr.body file)); *)
(* 	] *)

type url = [
	| `http of string
	| `git of string * string option
]

let url file = match (URL.kind file, URL.url file) with
	| `http, (src, None) -> `http src
	| `http, (src, Some what) -> failwith "http url with fragment"
	| `git, src -> `git src
	| `local, _ -> failwith "`local url not supported"
	| `darcs, _ -> failwith "TODO: darcs"
	| `hg, _ -> failwith "TODO: hg"

let load_url path =
	let url_file = open_in path in
	let rv = URL.read_from_channel url_file in
	close_in url_file;
	url rv

let load_opam path =
	Printf.eprintf "  Loading opam info from %s\n" path;
	let file = open_in path in
	let rv = OPAM.read_from_channel file in
	close_in file;
	rv

let concat_address (addr, frag) =
	match frag with
		| Some frag -> addr ^ "#" ^ frag
		| None -> addr

let string_of_url url =
	match url with
		| `http addr -> addr
		| `git addr -> "git:" ^ (concat_address addr)

let sha256_of_path p =
	let open Lwt in
	lwt lines = Lwt_process.with_process_in ("", [|"nix-hash"; "--type";"sha256"; p|]) (fun proc ->
		lwt lines = proc#stdout |> Lwt_io.read_lines |> Lwt_stream.to_list in
		lwt status = proc#close in
		let open Unix in
		match status with
			| WEXITED 0 -> return lines
			| _ -> failwith "nix-hash failed"
	) in
	match lines with
		| [line] -> return line
		| _ -> failwith ("Unexpected nix-hash output:\n" ^ (String.concat "\n" lines))

let nix_of_url ~add_input ~cache (url:url) =
	let open Nix_expr in
	let local_copy = cache#download url in
	let sha256 = sha256_of_path local_copy |> Lwt_main.run in
	match url with
		| `http src ->
			add_input "fetchurl";
			`Call [
				`Id "fetchurl";
				`Attrs (AttrSet.build [
					"url", str src;
					"sha256", str sha256;
				]);
			]
		| `git addr ->
				add_input "fetchgit";
				`Call [
					`Id "fetchurl";
					`Attrs (AttrSet.build [
						"url", str (concat_address addr);
						"sha256", str sha256;
					]);
				]

let attrs_of_opam ~add_dep (opam:OPAM.t) =
	add_dep Required (match (OPAM.ocaml_version opam) with
		| None -> NixDependency "ocaml"
		| Some constr -> OcamlDependency constr
	);
	add_dep Required (PackageDependencies (OPAM.depends opam));
	add_dep Optional (PackageDependencies (OPAM.depopts opam));
	[]



(* let info_opam ic = *)
(* 	`O [ *)
(* 		("type", `String "opam"); *)
(* 		("ocaml_version", match (OPAM.ocaml_version file) with *)
(* 			| None -> `Null *)
(* 			| Some constr -> json_of_formula json_of_compiler_version_constraint constr *)
(* 		); *)
(* 		("os", json_of_formula json_of_os_constr (OPAM.os file)); *)
(* 		("depends", json_of_depends (OPAM.depends file)); *)
(* 		("depends_optional", json_of_depends (OPAM.depopts file)); *)
(* 		("depends_external", match OPAM.depexts file with *)
(* 			| None -> `Null *)
(* 			| Some deps -> *)
(* 				OpamMisc.StringSetMap.to_json OpamMisc.StringSet.to_json deps; *)
(* 		); *)
(* 		("conflicts", json_of_depends (OPAM.conflicts file)); *)
(* 	] *)

let nix_of_opam ~name ~version ~cache ~deps path : Nix_expr.t =
	let pkgid = OpamPackage.create
		(OpamPackage.Name.of_string name)
		(OpamPackage.Version.of_string version)
	in
	let open Nix_expr in
	let inputs = ref [ Required, "stdenv"; Required, "opamSelection" ] in
	let add_input = fun importance name -> inputs := (importance, name) :: !inputs in

	let url = load_url (Filename.concat path "url") in
	let src = nix_of_url ~add_input:(add_input Required) ~cache url in

	deps#init_package pkgid;

	let opam_inputs = ref [ ] in
	let add_opam_input importance name = opam_inputs := (importance, name) :: !opam_inputs in
	let add_dep = fun importance dep ->
		(* deps#add_dep pkgid dep; *)
		add_nix_inputs
			~add_native:add_input
			~add_opam:add_opam_input
			importance dep
	in

	let opam = load_opam (Filename.concat path "opam") in
	let buildAttrs = attrs_of_opam ~add_dep opam in

	(* clean up potentially-duplicate `inputs` *)
	let opam_inputs =
		let rv = ref AttrSet.empty in
		let mandatory, optional = !opam_inputs |> List.partition (fun (i,_) -> i = Required) in
		let snd = fun (a,b) -> b in
		optional |> List.map snd |> List.iter (fun name ->
			rv := AttrSet.add name (`Property_or (`Id "opamSelection", name, `Null)) !rv
		);
		mandatory |> List.map snd |> List.iter (fun name ->
			rv := AttrSet.add name (`Property (`Id "opamSelection", name)) !rv
		);
		rv
	in

	let inputs =
		let mandatory, optional = !inputs |> List.partition (fun (i,_) -> i = Required) in
		let snd = fun (a,b) -> b in
		let mandatory = mandatory |> List.map snd in
		let optional = optional |> List.map snd |> List.filter (fun name ->
			not (List.mem name mandatory)
		) in
		let export = fun importance items ->
			items |> List.sort compare |> List.map (fun name -> (importance, name))
		in
		(export Required mandatory @ export Optional optional)
	in

	let input_args = inputs |> List.map (function
		| Required, name -> `Id name
		| Optional, name -> `Default (name, `Null)
	) in

	(`Function (
		(`NamedArguments input_args),
		(`Let_bindings (!opam_inputs,
			(`Call [
				`Id "stdenv.mkDerivation";
				(`Attrs (AttrSet.build (buildAttrs @ [
					"src", src;
					"buildInputs", `Call [
						`Id "filter";
						`Lit "(item: item != null)";
						`List (
							(inputs |> List.map (fun (dep, name) -> `Id name)) @
							(AttrSet.keys !opam_inputs |> List.map (fun name -> `Id name))
						);
					];
					"createFindlibDestdir", `Lit "true";
				])))
			])
		))
	))


