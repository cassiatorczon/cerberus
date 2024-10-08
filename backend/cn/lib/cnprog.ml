module BT = BaseTypes
module IT = IndexTerms
module Loc = Locations
module CF = Cerb_frontend
module RET = ResourceTypes
module LC = LogicalConstraints
open IT

type have_show =
  | Have
  | Show

type cn_extract = Id.t list * (Sym.t, Sctypes.t) CF.Cn.cn_to_extract * IndexTerms.t

type cn_statement =
  | CN_pack_unpack of CF.Cn.pack_unpack * ResourceTypes.predicate_type
  | CN_to_from_bytes of CF.Cn.to_from * ResourceTypes.resource_type
  | CN_have of LogicalConstraints.t
  | CN_instantiate of (Sym.t, Sctypes.t) CF.Cn.cn_to_instantiate * IndexTerms.t
  | CN_split_case of LogicalConstraints.t
  | CN_extract of cn_extract
  | CN_unfold of Sym.t * IndexTerms.t list
  | CN_apply of Sym.t * IndexTerms.t list
  | CN_assert of LogicalConstraints.t
  | CN_inline of Sym.t list
  | CN_print of IndexTerms.t

type cn_load =
  { ct : Sctypes.t;
    pointer : IndexTerms.t
  }

type cn_prog =
  | CN_let of Loc.t * (Sym.t * cn_load) * cn_prog
  | CN_statement of Loc.t * cn_statement

let rec subst substitution = function
  | CN_let (loc, (name, { ct; pointer }), prog) ->
    let pointer = IT.subst substitution pointer in
    let name, prog = suitably_alpha_rename substitution.relevant name prog in
    CN_let (loc, (name, { ct; pointer }), subst substitution prog)
  | CN_statement (loc, stmt) ->
    let stmt =
      match stmt with
      | CN_pack_unpack (pack_unpack, pt) ->
        CN_pack_unpack (pack_unpack, RET.subst_predicate_type substitution pt)
      | CN_to_from_bytes (to_from, res) ->
        CN_to_from_bytes (to_from, RET.subst substitution res)
      | CN_have lc -> CN_have (LC.subst substitution lc)
      | CN_instantiate (o_s, it) ->
        (* o_s is not a (option) binder *)
        CN_instantiate (o_s, IT.subst substitution it)
      | CN_split_case lc -> CN_split_case (LC.subst substitution lc)
      | CN_extract (attrs, to_extract, it) ->
        CN_extract (attrs, to_extract, IT.subst substitution it)
      | CN_unfold (fsym, args) ->
        (* fsym is a function symbol *)
        CN_unfold (fsym, List.map (IT.subst substitution) args)
      | CN_apply (fsym, args) ->
        (* fsym is a lemma symbol *)
        CN_apply (fsym, List.map (IT.subst substitution) args)
      | CN_assert lc -> CN_assert (LC.subst substitution lc)
      | CN_inline nms -> CN_inline nms
      | CN_print it -> CN_print (IT.subst substitution it)
    in
    CN_statement (loc, stmt)


and alpha_rename_ ~from ~to_ prog = (to_, subst (IT.make_rename ~from ~to_) prog)

and alpha_rename from prog =
  let to_ = Sym.fresh_same from in
  alpha_rename_ ~from ~to_ prog


and suitably_alpha_rename syms s prog =
  if SymSet.mem s syms then
    alpha_rename s prog
  else
    (s, prog)


open Cerb_frontend.Pp_ast
open Pp

let dtree_of_to_instantiate = function
  | CF.Cn.I_Function f -> Dnode (pp_ctor "[CN]function", [ Dleaf (Sym.pp f) ])
  | I_Good ty -> Dnode (pp_ctor "[CN]good", [ Dleaf (Sctypes.pp ty) ])
  | I_Everything -> Dleaf !^"[CN]everything"


let dtree_of_to_extract = function
  | CF.Cn.E_Everything -> Dleaf !^"[CN]everything"
  | E_Pred pred ->
    let pred =
      match pred with
      | CN_owned oct -> CF.Cn.CN_owned (Option.map Sctypes.to_ctype oct)
      | CN_block ct -> CN_block (Option.map Sctypes.to_ctype ct)
      | CN_named p -> CN_named p
    in
    Dnode (pp_ctor "[CN]pred", [ Cerb_frontend.Cn_ocaml.PpAil.dtree_of_cn_pred pred ])


let dtree_of_cn_statement = function
  | CN_pack_unpack (Pack, pred) ->
    Dnode (pp_ctor "Pack", [ ResourceTypes.dtree_of_predicate_type pred ])
  | CN_pack_unpack (Unpack, pred) ->
    Dnode (pp_ctor "Unpack", [ ResourceTypes.dtree_of_predicate_type pred ])
  | CN_to_from_bytes (To, res) -> Dnode (pp_ctor "To_bytes", [ ResourceTypes.dtree res ])
  | CN_to_from_bytes (From, res) ->
    Dnode (pp_ctor "From_bytes", [ ResourceTypes.dtree res ])
  | CN_have lc -> Dnode (pp_ctor "Have", [ LC.dtree lc ])
  | CN_instantiate (to_instantiate, it) ->
    Dnode (pp_ctor "Instantiate", [ dtree_of_to_instantiate to_instantiate; IT.dtree it ])
  | CN_split_case lc -> Dnode (pp_ctor "Split_case", [ LC.dtree lc ])
  | CN_extract (attrs, to_extract, it) ->
    Dnode
      ( pp_ctor "Extract",
        [ Dnode (pp_ctor "Attrs", List.map (fun s -> Dleaf (Id.pp s)) attrs);
          dtree_of_to_extract to_extract;
          IT.dtree it
        ] )
  | CN_unfold (s, args) ->
    Dnode (pp_ctor "Unfold", Dleaf (Sym.pp s) :: List.map IT.dtree args)
  | CN_apply (s, args) ->
    Dnode (pp_ctor "Apply", Dleaf (Sym.pp s) :: List.map IT.dtree args)
  | CN_assert lc -> Dnode (pp_ctor "Assert", [ LC.dtree lc ])
  | CN_inline nms -> Dnode (pp_ctor "Inline", List.map (fun nm -> Dleaf (Sym.pp nm)) nms)
  | CN_print it -> Dnode (pp_ctor "Print", [ IT.dtree it ])


let rec dtree = function
  | CN_let (_loc, (s, load), prog) ->
    Dnode
      ( pp_ctor "LetLoad",
        [ Dleaf (Sym.pp s);
          IT.dtree load.pointer;
          Dleaf (Sctypes.pp load.ct);
          dtree prog
        ] )
  | CN_statement (_loc, stmt) -> dtree_of_cn_statement stmt
