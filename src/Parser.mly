

(* This file is free software, part of smtlib-utils. See file "license" for more details. *)

(** {1 Parser for SMTLIB2.6} *)

(* vim:SyntasticToggleMode:
   vim:set ft=yacc: *)

%{

  let consts =
    let module A = Ast in
    let tbl = Hashtbl.create 32 in
    let mkc c name ~loc = function
      | [] -> c
      | _ ->
        A.parse_errorf ~loc "wrong arity for constant %s" name
    and mkf1 f name ~loc = function
      | [t] -> f t
      | _ ->
        A.parse_errorf ~loc "wrong arity for unary function %s" name
    and mkl f _name ~loc:_ args =
      f args
    and arith_op op _name ~loc:_ args =
      A.arith op args
    and bitvec_op op _name ~loc:_ args =
      A.bitvec op args
    in
    List.iter (fun (s,f) -> Hashtbl.add tbl s f) [
      ("true", mkc A.true_);
      ("false", mkc A.false_);
      ("or", mkl A.or_);
      ("and", mkl A.and_);
      ("not", mkf1 A.not_);
      ("+", arith_op A.Add);
      ("-", arith_op A.Minus);
      ("*", arith_op A.Mult);
      ("/", arith_op A.Div);
      ("<=", arith_op A.Leq);
      ("<", arith_op A.Lt);
      (">=", arith_op A.Geq);
      (">", arith_op A.Gt);
      ("bvult", bitvec_op A.BVUlt);
      ("bvslt", bitvec_op A.BVSlt);
      ("bvnot", bitvec_op A.BVNot);
      ("bvand", bitvec_op A.BVAnd);
      ("bvxor", bitvec_op A.BVXor);
      ("bvshl", bitvec_op A.BVShl);
      ("bvlsht", bitvec_op A.BVLsht);
      ("bvashr", bitvec_op A.BVAshr);
      ("bvadd", bitvec_op A.BVAdd);
      ("bvmul", bitvec_op A.BVMul);
      ("bvurem", bitvec_op A.BVURem);
      ("bvudiv", bitvec_op A.BVUDiv);
      ("concat", bitvec_op A.Concat);
    ];
    tbl

  let apply_const ~loc name args =
    let module A = Ast in
    try
      let f = Hashtbl.find consts name in
      f name ~loc args
    with Not_found ->
      if args=[] then A.const name else A.app name args
%}

%token EOI

%token LEFT_PAREN
%token RIGHT_PAREN

%token PAR
%token ARROW

%token DISTINCT
%token EQ
%token IF
%token MATCH
%token FUN
%token LET
%token AS
%token WILDCARD
%token IS
%token AT
%token BANG
%token SIGN_EXTEND
%token EXTRACT

%token DATA
%token DATUM
%token ASSERT
%token FORALL
%token EXISTS
%token DECLARE_SORT
%token DECLARE_CONST
%token DECLARE_FUN
%token DEFINE_FUN
%token DEFINE_FUN_REC
%token DEFINE_FUNS_REC
%token CHECK_SAT
%token CHECK_SAT_ASSUMING
%token GET_VALUE
%token BITVEC

%token <string>IDENT
%token <string>QUOTED

%start <Ast.term> parse_term
%start <Ast.ty> parse_ty
%start <Ast.statement> parse
%start <Ast.statement list> parse_list

%%

parse_list: l=stmt* EOI {l}
parse: t=stmt EOI { t }
parse_term: t=term EOI { t }
parse_ty: t=ty EOI { t }

cstor_arg:
  | LEFT_PAREN name=IDENT ty=ty RIGHT_PAREN { name, ty }

cstor_dec:
  | LEFT_PAREN c=IDENT l=cstor_arg* RIGHT_PAREN { c, l }

cstor:
  | dec=cstor_dec { let c,l = dec in Ast.mk_cstor ~vars:[] c l }
  | LEFT_PAREN PAR LEFT_PAREN vars=var+ RIGHT_PAREN dec=cstor_dec RIGHT_PAREN
    { let c,l = dec in Ast.mk_cstor ~vars c l }

cstors:
  | LEFT_PAREN l=cstor+ RIGHT_PAREN { l }

%inline ty_decl:
  | s=IDENT n=IDENT  {
      let loc = Loc.mk_pos $startpos $endpos in
      try
        let n = int_of_string n in
        s, n
      with Failure _ ->
        Ast.parse_errorf ~loc "expected arity to be an integer, not `%s`" n
  }

ty_decl_paren:
  | LEFT_PAREN ty=ty_decl RIGHT_PAREN { ty }

fun_def_mono:
  | f=IDENT
    LEFT_PAREN args=typed_var* RIGHT_PAREN
    ret=ty
    { f, args, ret }

fun_decl_mono:
  | f=IDENT
    LEFT_PAREN args=ty* RIGHT_PAREN
    ret=ty
    { f, args, ret }

fun_decl:
  | tup=fun_decl_mono { let f, args, ret = tup in [], f, args, ret }
  | LEFT_PAREN
      PAR
      LEFT_PAREN tyvars=tyvar* RIGHT_PAREN
      LEFT_PAREN tup=fun_decl_mono RIGHT_PAREN
    RIGHT_PAREN
    { let f, args, ret = tup in tyvars, f, args, ret }

fun_rec:
  | tup=fun_def_mono body=term
    {
      let f, args, ret = tup in
      Ast.mk_fun_rec ~ty_vars:[] f args ret body
    }
  | LEFT_PAREN
      PAR
      LEFT_PAREN l=tyvar* RIGHT_PAREN
      LEFT_PAREN tup=fun_def_mono body=term RIGHT_PAREN
    RIGHT_PAREN
    {
      let f, args, ret = tup in
      Ast.mk_fun_rec ~ty_vars:l f args ret body
    }

funs_rec_decl:
  | LEFT_PAREN tup=fun_def_mono RIGHT_PAREN
    {
      let f, args, ret = tup in
      Ast.mk_fun_decl ~ty_vars:[] f args ret
    }
  | LEFT_PAREN
      PAR
      LEFT_PAREN l=tyvar* RIGHT_PAREN
      LEFT_PAREN tup=fun_def_mono RIGHT_PAREN
    RIGHT_PAREN
    {
      let f, args, ret = tup in
      Ast.mk_fun_decl ~ty_vars:l f args ret
    }

par_term:
  | LEFT_PAREN
      PAR LEFT_PAREN tyvars=tyvar+ RIGHT_PAREN t=term
    RIGHT_PAREN
  { tyvars, t }
  | t=term
  { [], t }

anystr:
  | s=IDENT {s}
  | s=QUOTED {s}

prop_lit:
  | s=var { s, true }
  | LEFT_PAREN not_=IDENT s=var RIGHT_PAREN {
    if not_ = "not" then s, false
    else
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.parse_errorf ~loc "expected `not`, not `%s`" not_
    }

stmt:
  | LEFT_PAREN ASSERT t=term RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.assert_ ~loc t
    }
  | LEFT_PAREN DECLARE_SORT td=ty_decl RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      let s, n = td in
      Ast.decl_sort ~loc s ~arity:n
    }
  | LEFT_PAREN DATA
      LEFT_PAREN tys=ty_decl_paren+ RIGHT_PAREN
      LEFT_PAREN l=cstors+ RIGHT_PAREN
    RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.data_zip ~loc tys l
    }
  | LEFT_PAREN DATUM
      s=IDENT
      l=cstors
    RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.data_zip ~loc [(s, 0)] [l]
    }
  | LEFT_PAREN DECLARE_FUN tup=fun_decl RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      let tyvars, f, args, ret = tup in
      Ast.decl_fun ~loc ~tyvars f args ret
    }
  | LEFT_PAREN DECLARE_CONST f=IDENT ty=ty RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.decl_fun ~loc ~tyvars:[] f [] ty
    }
  | LEFT_PAREN DEFINE_FUN f=fun_rec RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.fun_def ~loc f
    }
  | LEFT_PAREN
    DEFINE_FUN_REC
    f=fun_rec
    RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.fun_rec ~loc f
    }
  | LEFT_PAREN
    DEFINE_FUNS_REC
      LEFT_PAREN decls=funs_rec_decl+ RIGHT_PAREN
      LEFT_PAREN bodies=term+ RIGHT_PAREN
    RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.funs_rec ~loc decls bodies
    }
  | LEFT_PAREN CHECK_SAT RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.check_sat ~loc ()
    }
  | LEFT_PAREN CHECK_SAT_ASSUMING LEFT_PAREN l=prop_lit* RIGHT_PAREN RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.check_sat_assuming ~loc l
    }
  | LEFT_PAREN GET_VALUE l=term+ RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.get_value ~loc l
    }
  | LEFT_PAREN s=IDENT args=anystr* RIGHT_PAREN
    {
      let loc = Loc.mk_pos $startpos $endpos in
      match s, args with
      | "exit", [] -> Ast.exit ~loc ()
      | "set-logic", [l] -> Ast.set_logic ~loc l
      | "set-info", [a;b] -> Ast.set_info ~loc a b
      | "set-option", l -> Ast.set_option ~loc l
      | "get-option", [a] -> Ast.get_option ~loc a
      | "get-info", [a] -> Ast.get_info ~loc a
      | "get-assertions", [] -> Ast.get_assertions ~loc ()
      | "get-assignment", [] -> Ast.get_assignment ~loc ()
      | "get-proof", [] -> Ast.get_proof ~loc ()
      | "get-model", [] -> Ast.get_model ~loc ()
      | "get-unsat-core", [] -> Ast.get_unsat_core ~loc ()
      | "get-unsat-assumptions", [] -> Ast.get_unsat_assumptions ~loc ()
      | "reset", [] -> Ast.reset ~loc ()
      | "reset-assertions", [] -> Ast.reset_assertions ~loc ()
      | "push", [x] ->
        (try Ast.push ~loc (int_of_string x) with _ ->
         Ast.parse_errorf ~loc "expected an integer argument for push, not %s" x)
      | "pop", [x] ->
        (try Ast.pop ~loc (int_of_string x) with _ ->
         Ast.parse_errorf ~loc "expected an integer argument for pop, not %s" x)
      | _ ->
        Ast.parse_errorf ~loc "expected statement"
    }
  | error
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.parse_errorf ~loc "expected statement"
    }

var:
  | WILDCARD { "_" }
  | s=IDENT { s }
tyvar:
  | s=IDENT { s }

ty:
  | s=IDENT {
    begin match s with
      | "Bool" -> Ast.ty_bool
      | "Real" -> Ast.ty_real
      | _ -> Ast.ty_const s
    end
    }
  | LEFT_PAREN WILDCARD BITVEC n=IDENT RIGHT_PAREN {
    let loc = Loc.mk_pos $startpos $endpos in
    try (Ast.ty_bv (int_of_string n)) with _ -> 
      Ast.parse_errorf ~loc "expected an integer argument for BitVec, not %s" n }
  | LEFT_PAREN s=IDENT args=ty+ RIGHT_PAREN
    {Ast.ty_app s args }
  | LEFT_PAREN ARROW tup=ty_arrow_args RIGHT_PAREN
    {
      let args, ret = tup in
      Ast.ty_arrow_l args ret }

ty_arrow_args:
  | a=ty ret=ty { [a], ret }
  | a=ty tup=ty_arrow_args { a :: fst tup, snd tup }

typed_var:
  | LEFT_PAREN s=var ty=ty RIGHT_PAREN { s, ty }

case:
  | LEFT_PAREN
      c=IDENT
      rhs=term
    RIGHT_PAREN
    { Ast.Match_case (c, [], rhs) }
  | LEFT_PAREN
      LEFT_PAREN c=IDENT vars=var+ RIGHT_PAREN
      rhs=term
    RIGHT_PAREN
    { Ast.Match_case (c, vars, rhs) }
  | LEFT_PAREN
     WILDCARD rhs=term
    RIGHT_PAREN
    { Ast.Match_default rhs }

binding:
  | LEFT_PAREN v=var t=term RIGHT_PAREN { v, t }

term:
  | s=QUOTED { Ast.const s }
  | s=IDENT {
    let loc = Loc.mk_pos $startpos $endpos in
    apply_const ~loc s []
    }
  | t=composite_term { t }
  | error
    {
      let loc = Loc.mk_pos $startpos $endpos in
      Ast.parse_errorf ~loc "expected term"
    }

attr:
  | a=IDENT b=anystr { a,b }

composite_term:
  | LEFT_PAREN t=term RIGHT_PAREN { t }
  | LEFT_PAREN IF a=term b=term c=term RIGHT_PAREN { Ast.if_ a b c }
  | LEFT_PAREN DISTINCT l=term+ RIGHT_PAREN { Ast.distinct l }
  | LEFT_PAREN EQ a=term b=term RIGHT_PAREN { Ast.eq a b }
  | LEFT_PAREN ARROW a=term b=term RIGHT_PAREN { Ast.imply a b }
  | LEFT_PAREN f=IDENT args=term+ RIGHT_PAREN {
    let loc = Loc.mk_pos $startpos $endpos in
    apply_const ~loc f args }
  | LEFT_PAREN WILDCARD args=term+ RIGHT_PAREN {
    let loc = Loc.mk_pos $startpos $endpos in
    apply_const ~loc "_" args }
  | LEFT_PAREN LEFT_PAREN WILDCARD SIGN_EXTEND i=IDENT RIGHT_PAREN args=term+ RIGHT_PAREN {
    let loc = Loc.mk_pos $startpos $endpos in
    try (Ast.bitvec (Ast.Sign_extend (int_of_string i)) args) with _ -> 
      Ast.parse_errorf ~loc "expected an integer argument for sign_extend, not %s" i
  }
  | LEFT_PAREN LEFT_PAREN WILDCARD EXTRACT i=IDENT j=IDENT RIGHT_PAREN args=term+ RIGHT_PAREN {
    let loc = Loc.mk_pos $startpos $endpos in
    try (Ast.bitvec (Ast.Extract (int_of_string i, int_of_string j)) args) with _ -> 
      Ast.parse_errorf ~loc "expected an integer argument for pop, not %s %s" i j
  }
  | LEFT_PAREN f=composite_term args=term+ RIGHT_PAREN { Ast.ho_app_l f args }
  | LEFT_PAREN AT f=term arg=term RIGHT_PAREN { Ast.ho_app f arg }
  | LEFT_PAREN BANG t=term attrs=attr+ RIGHT_PAREN { Ast.attr t attrs }
  | LEFT_PAREN
      MATCH
      lhs=term
        LEFT_PAREN
        l=case+
        RIGHT_PAREN
    RIGHT_PAREN
    { Ast.match_ lhs l }
  | LEFT_PAREN
      FUN
      LEFT_PAREN vars=typed_var+ RIGHT_PAREN
      body=term
    RIGHT_PAREN
    { Ast.fun_l vars body }
  | LEFT_PAREN
      LEFT_PAREN WILDCARD IS c=IDENT RIGHT_PAREN
      t=term
    RIGHT_PAREN
    { Ast.is_a c t }
  | LEFT_PAREN
      LET
      LEFT_PAREN l=binding+ RIGHT_PAREN
      r=term
    RIGHT_PAREN
    { Ast.let_ l r }
  | LEFT_PAREN AS t=term ty=ty RIGHT_PAREN
    { Ast.cast t ~ty }
  | LEFT_PAREN FORALL LEFT_PAREN vars=typed_var+ RIGHT_PAREN
    f=term
    RIGHT_PAREN
    { Ast.forall vars f }
  | LEFT_PAREN EXISTS LEFT_PAREN vars=typed_var+ RIGHT_PAREN
    f=term
    RIGHT_PAREN
    { Ast.exists vars f }

%%
