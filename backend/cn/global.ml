module CF = Cerb_frontend
open Pp
module SymSet = Set.Make(Sym)
module SymMap = Map.Make(Sym)
module IdMap = Map.Make(Id)
module StringMap = Map.Make(String)
module RT = ReturnTypes
module AT = ArgumentTypes

module ImplMap = 
  Map.Make (struct 
      type t = CF.Implementation.implementation_constant
      let compare = CF.Implementation.implementation_constant_compare 
    end)


type t = 
  { struct_decls : Memory.struct_decls; 
    datatypes : BaseTypes.datatype_info SymMap.t;
    datatype_constrs : BaseTypes.constr_info SymMap.t;
    fun_decls : (Locations.t * AT.ft * CF.Mucore.trusted) SymMap.t;
    (* impl_fun_decls : AT.ift ImplMap.t; *)
    (* impl_constants : IndexTerms.t ImplMap.t; *)
    resource_predicates : ResourcePredicates.definition SymMap.t;
    logical_predicates : LogicalPredicates.definition SymMap.t;
  } 

let empty = 
  { struct_decls = SymMap.empty;
    datatypes = SymMap.empty;
    datatype_constrs = SymMap.empty;
    fun_decls = SymMap.empty;
    (* impl_fun_decls = ImplMap.empty; *)
    (* impl_constants = ImplMap.empty; *)
    resource_predicates = SymMap.empty;
    logical_predicates = SymMap.empty;
  }


let get_resource_predicate_def global id = SymMap.find_opt id global.resource_predicates
let get_logical_predicate_def global id = SymMap.find_opt id global.logical_predicates
let get_fun_decl global sym = SymMap.find_opt sym global.fun_decls
(* let get_impl_fun_decl global i = ImplMap.find i global.impl_fun_decls *)
(* let get_impl_constant global i = ImplMap.find i global.impl_constants *)

let sym_map_from_bindings xs = List.fold_left (fun m (nm, x) -> SymMap.add nm x m)
    SymMap.empty xs

let add_datatypes (dt_info, c_info) global =
  let datatypes = sym_map_from_bindings dt_info in
  let datatype_constrs = sym_map_from_bindings c_info in
  {global with datatypes; datatype_constrs}

let add_predicates (l_pred_list, r_pred_list) global =
  let resource_predicates = sym_map_from_bindings r_pred_list in
  let logical_predicates = sym_map_from_bindings l_pred_list in
  {global with resource_predicates; logical_predicates}

let pp_struct_layout (tag,layout) = 
  item ("struct " ^ plain (Sym.pp tag) ^ " (raw)") 
    (separate_map hardline (fun Memory.{offset; size; member_or_padding} -> 
         item "offset" (Pp.int offset) ^^ comma ^^^
           item "size" (Pp.int size) ^^ comma ^^^
             item "content" 
               begin match member_or_padding with 
               | Some (member, sct) -> 
                  typ (Id.pp member) (Sctypes.pp sct)
               | None ->
                  parens (!^"padding" ^^^ Pp.int size)
               end
       ) layout
    )


let pp_struct_decls decls = 
  Pp.list pp_struct_layout (SymMap.bindings decls) 

let pp_fun_decl (sym, (_, t, _)) = item (plain (Sym.pp sym)) (AT.pp RT.pp t)
let pp_fun_decls decls = flow_map hardline pp_fun_decl (SymMap.bindings decls)

let pp_resource_predicate_definitions defs =
  separate_map hardline (fun (name, def) ->
      item (Sym.pp_string name) (ResourcePredicates.pp_definition def))
    (SymMap.bindings defs)

let pp global = 
  pp_struct_decls global.struct_decls ^^ hardline ^^
  pp_fun_decls global.fun_decls ^^ hardline ^^
  pp_resource_predicate_definitions global.resource_predicates





