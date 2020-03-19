open Extra
open Coq_ast
open Rc_annot

(** [section_name fname] builds a reasonable Coq section name from a file. The
    slash, dash and dot characters are replaced by underscores. Note that this
    function will miserably fail on weird file names (e.g., ["A file.c"]). *)
let section_name : string -> string = fun fname ->
  let cleanup name c = String.concat "_" (String.split_on_char c name) in
  List.fold_left cleanup fname ['/'; '-'; '.']

let pp_int_type : Coq_ast.int_type pp = fun ff it ->
  let pp fmt = Format.fprintf ff fmt in
  match it with
  | ItSize_t(true)      -> pp "ssize_t"
  | ItSize_t(false)     -> pp "size_t"
  | ItI8(true)          -> pp "i8"
  | ItI8(false)         -> pp "u8"
  | ItI16(true)         -> pp "i16"
  | ItI16(false)        -> pp "u16"
  | ItI32(true)         -> pp "i32"
  | ItI32(false)        -> pp "u32"
  | ItI64(true)         -> pp "i64"
  | ItI64(false)        -> pp "u64"


let rec pp_layout : Coq_ast.layout pp = fun ff layout ->
  let pp fmt = Format.fprintf ff fmt in
  match layout with
  | LVoid              -> pp "LVoid"
  | LPtr               -> pp "LPtr"
  | LStruct(id, false) -> pp "layout_of struct_%s" id
  | LStruct(id, true ) -> pp "ul_layout union_%s" id
  | LInt(i)            -> pp "it_layout %a" pp_int_type i
  | LArray(layout, n)  -> pp "mk_array_layout (%a) %s" pp_layout layout n

let pp_op_type : Coq_ast.op_type pp = fun ff ty ->
  let pp fmt = Format.fprintf ff fmt in
  match ty with
  | OpInt(i) -> pp "IntOp %a" pp_int_type i
  | OpPtr(_) -> pp "PtrOp" (* FIXME *)

let pp_un_op : Coq_ast.un_op pp = fun ff op ->
  let pp fmt = Format.fprintf ff fmt in
  match op with
  | NotBoolOp  -> pp "NotBoolOp"
  | NotIntOp   -> pp "NotIntOp"
  | NegOp      -> pp "NegOp"
  | CastOp(ty) -> pp "(CastOp $ %a)" pp_op_type ty

let pp_bin_op : Coq_ast.bin_op pp = fun ff op ->
  Format.pp_print_string ff @@
  match op with
  | AddOp       -> "+"
  | SubOp       -> "-"
  | MulOp       -> "×"
  | DivOp       -> "/"
  | ModOp       -> "%"
  | AndOp       -> "..." (* TODO *)
  | OrOp        -> "..." (* TODO *)
  | XorOp       -> "..." (* TODO *)
  | ShlOp       -> "..." (* TODO *)
  | ShrOp       -> "..." (* TODO *)
  | EqOp        -> "="
  | NeOp        -> "!="
  | LtOp        -> "<"
  | GtOp        -> ">"
  | LeOp        -> "≤"
  | GeOp        -> "≥"
  | RoundDownOp -> "..." (* TODO *)
  | RoundUpOp   -> "..." (* TODO *)

let rec pp_expr : Coq_ast.expr pp = fun ff e ->
  let pp fmt = Format.fprintf ff fmt in
  match e with
  | Var(None   ,g)                ->
      pp "\"_\""
  | Var(Some(x),g)                ->
      let x = if g then x else Printf.sprintf "\"%s\"" x in
      Format.pp_print_string ff x
  | Val(Null)                     ->
      pp "NULL"
  | Val(Void)                     ->
      pp "VOID"
  | Val(Int(s,it))                ->
      pp "i2v %s %a" s pp_int_type it
  | UnOp(op,ty,e)                 ->
      pp "UnOp %a (%a) (%a)" pp_un_op op pp_op_type ty pp_expr e
  | BinOp(op,ty1,ty2,e1,e2)       ->
      begin
        match (ty1, ty2, op) with
        | (OpPtr(l), OpInt(_), AddOp) ->
            pp "(%a) at_offset{%a, PtrOp, %a} (%a)" pp_expr e1
              pp_layout l pp_op_type ty2 pp_expr e2
        | (OpPtr(_), OpInt(_), _) ->
            Format.eprintf "Binop [%a] not supported on pointers\n%!"
              pp_bin_op op; exit 1
        | (OpInt(_), OpPtr(_), _) ->
            Format.eprintf "Wrong ordering of integer pointer binop [%a]\n%!"
              pp_bin_op op; exit 1
        | _                 ->
            pp "(%a) %a{%a, %a} (%a)" pp_expr e1 pp_bin_op op
              pp_op_type ty1 pp_op_type ty2 pp_expr e2
      end
  | Deref(lay,e)                  ->
      pp "!{%a} (%a)" pp_layout lay pp_expr e
  | CAS(ty,e1,e2,e3)              ->
      pp "CAS@ (%a)@ (%a)@ (%a)@ (%a)" pp_op_type ty
        pp_expr e1 pp_expr e2 pp_expr e3
  | SkipE(e)                      ->
      pp "SkipE (%a)" pp_expr e
  | Use(lay,e)                    ->
      pp "use{%a} (%a)" pp_layout lay pp_expr e
  | AddrOf(e)                     ->
      pp "&(%a)" pp_expr e
  | GetMember(e,name,false,field) ->
      pp "(%a) at{struct_%s} %S" pp_expr e name field
  | GetMember(e,name,true ,field) ->
      pp "(%a) at_union{union_%s} %S" pp_expr e name field

let rec pp_stmt : Coq_ast.stmt pp = fun ff stmt ->
  let pp fmt = Format.fprintf ff fmt in
  match stmt with
  | Goto(id)               ->
      pp "Goto %S" id
  | Return(e)              ->
      pp "Return @[<hov 0>(%a)@]" pp_expr e
  | Assign(lay,e1,e2,stmt) ->
      pp "@[<hov 2>%a <-{ %a }@ %a ;@]@;%a"
        pp_expr e1 pp_layout lay pp_expr e2 pp_stmt stmt
  | Call(ret_id,e,es,stmt) ->
      let pp_args _ es =
        let n = List.length es in
        let fn i e =
          let sc = if i = n - 1 then "" else " ;" in
          pp "%a%s@;" pp_expr e sc
        in
        List.iteri fn es
      in
      pp "@[<hov 2>%S <- %a with@ [ @[<hov 2>%a@] ] ;@]@;%a"
        (Option.get "_" ret_id) pp_expr e pp_args es pp_stmt stmt
  | SkipS(stmt)            ->
      pp_stmt ff stmt
  | If(e,stmt1,stmt2)      ->
      pp "if: @[<hov 0>%a@]@;then@;@[<v 2>%a@]@;else@;@[<v 2>%a@]"
        pp_expr e pp_stmt stmt1 pp_stmt stmt2
  | Assert(e, stmt)        ->
      pp "assert: (%a) ;@;%a" pp_expr e pp_stmt stmt
  | ExprS(attrs, e, stmt)  ->
      (* TODO actually handle attributes. *)
      let pp_attr attr =
        let _ =
          try ignore (parse_attr attr) with Invalid_annot(msg) ->
          Format.eprintf "Error: %s\n%!" msg
        in
        let {rc_attr_id=id; rc_attr_args=args} = attr in
        let args = List.map (Printf.sprintf "\"%s\"") args in
        pp "(* %s(%s) *)@;" id (String.concat ", " args)
      in
      List.iter pp_attr attrs;

      pp "expr: (%a) ;@;%a" pp_expr e pp_stmt stmt

let pp_ast : Coq_ast.t pp = fun ff ast ->
  (* Formatting utilities. *)
  let pp fmt = Format.fprintf ff fmt in

  (* Printing some header. *)
  pp "@[<v 0>From refinedc.lang Require Export notation.@;";
  pp "From refinedc.lang Require Import tactics.@;";
  pp "Set Default Proof Using \"Type\".@;@;";

  (* Printing generation data and entry point in a comment. *)
  let pp_entry ff = Option.iter (Format.fprintf ff ", entry point [%s]") in
  pp "(* Generated from [%s]%a.*)@;" ast.source_file pp_entry ast.entry_point;

  (* Opening the section. *)
  let sect = section_name ast.source_file in
  pp "@[<v 2>Section %s.@;" sect;

  (* Declaration of objects (global variable) in the context. *)
  pp "(* Global variables. *)@;";
  let pp_global_var = pp "Context (%s : loc).@;" in
  List.iter pp_global_var ast.global_vars;

  (* Declaration of functions in the context. *)
  pp "@;(* Functions. *)@;";
  let pp_func_decl (id, _) = pp "Context (%s : loc).@;" id in
  List.iter pp_func_decl ast.functions;

  (* Printing for struct/union members. *)
  let pp_members members =
    let n = List.length members in
    let fn i (id, (attrs, layout)) =
      let sc = if i = n - 1 then "" else ";" in
      (*
      let annot =
        try field_annot attrs with Invalid_annot(msg) ->
          Format.eprintf "Error: %s\n%!" msg; exit 1
      in
      ignore annot; (* TODO actually handle attributes. *)
      *)

      pp "@;(%S, %a)%s" id pp_layout layout sc
    in
    List.iteri fn members
  in

  (* Definition of structs/unions. *)
  let pp_struct (id, decl) =
    pp "@;(* Definition of struct [%s]. *)@;" id;
    pp "@[<v 2>Program Definition struct_%s := {|@;" id;

    (* TODO actually handle attributes. *)
    let pp_attr attr =
      let _ =
        try ignore (parse_attr attr) with Invalid_annot(msg) ->
        Format.eprintf "Error: %s\n%!" msg
      in
      let {rc_attr_id=id; rc_attr_args=args} = attr in
      let args = List.map (Printf.sprintf "\"%s\"") args in
      pp "(* %s(%s) *)@;" id (String.concat ", " args)
    in
    List.iter pp_attr decl.struct_attrs;

    pp "@[<v 2>sl_members := [";
    pp_members decl.struct_members;
    pp "@]@;];@]@;|}.@;";
    pp "Solve Obligations with solve_struct_obligations.@;"
  in
  let pp_union (id, decl) =
    pp "@;(* Definition of union [%s]. *)@;" id;
    pp "@[<v 2>Program Definition union_%s := {|@;" id;

    (* TODO actually handle attributes. *)
    let pp_attr attr =
      let _ =
        try ignore (parse_attr attr) with Invalid_annot(msg) ->
        Format.eprintf "Error: %s\n%!" msg
      in
      let {rc_attr_id=id; rc_attr_args=args} = attr in
      let args = List.map (Printf.sprintf "\"%s\"") args in
      pp "(* %s(%s) *)@;" id (String.concat ", " args)
    in
    List.iter pp_attr decl.struct_attrs;

    pp "@[<v 2>ul_members := [";
    pp_members decl.struct_members;
    pp "@]@;];@]@;|}.@;";
    pp "Solve Obligations with solve_struct_obligations.@;"
  in
  let rec sort_structs found strs =
    match strs with
    | []                     -> []
    | (id, s) as str :: strs ->
    if List.for_all (fun id -> List.mem id found) s.struct_deps then
      str :: sort_structs (id :: found) strs
    else
      sort_structs found (strs @ [str])
  in
  let pp_struct_union ((_, {struct_is_union}) as s) =
    if struct_is_union then pp_union s else pp_struct s
  in
  List.iter pp_struct_union (sort_structs [] ast.structs);

  (* Definition of functions. *)
  let pp_function (id, def) =
    pp "\n@;(* Definition of function [%s]. *)@;" id;
    pp "@[<v 2>Definition impl_%s : function := {|@;" id;

    let annots =
      try function_annots def.func_attrs with Invalid_annot(msg) ->
        Format.eprintf "Error: %s\n%!" msg; exit 1
    in
    ignore annots; (* TODO handle annotations. *)

    pp "@[<v 2>f_args := [";
    begin
      let n = List.length def.func_args in
      let fn i (id, layout) =
        let sc = if i = n - 1 then "" else ";" in
        pp "@;(%S, %a)%s" id pp_layout layout sc
      in
      List.iteri fn def.func_args
    end;
    pp "@]@;];@;";

    pp "@[<v 2>f_local_vars := [";
    begin
      let n = List.length def.func_vars in
      let fn i (id, layout) =
        let sc = if i = n - 1 then "" else ";" in
        pp "@;(%S, %a)%s" id pp_layout layout sc
      in
      List.iteri fn def.func_vars
    end;
    pp "@]@;];@;";

    pp "f_init := \"#0\";@;";

    pp "@[<v 2>f_code := (";
    begin
      let fn id (attrs, stmt) =
        pp "@;@[<v 2><[ \"%s\" :=@;" id;

        (* TODO actually handle attributes. *)
        let pp_attr attr =
          let _ =
            try ignore (parse_attr attr) with Invalid_annot(msg) ->
            Format.eprintf "Error: %s\n%!" msg
          in
          let {rc_attr_id=id; rc_attr_args=args} = attr in
          let args = List.map (Printf.sprintf "\"%s\"") args in
          pp "(* %s(%s) *)@;" id (String.concat ", " args)
        in
        List.iter pp_attr attrs;

        pp_stmt ff stmt;
        pp "@]@;]> $";
      in
      SMap.iter fn def.func_blocks;
      pp "∅"
    end;
    pp "@]@;)%%E";
    pp "@]@;|}.";
  in
  List.iter pp_function ast.functions;

  (* Closing the section. *)
  pp "@]@;End %s.@]" sect

let write_ast : string -> Coq_ast.t -> unit = fun fname ast ->
  let oc = open_out fname in
  let ff = Format.formatter_of_out_channel oc in
  Format.fprintf ff "%a@." pp_ast ast;
  close_out oc
