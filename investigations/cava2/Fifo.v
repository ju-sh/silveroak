(****************************************************************************)
(* Copyright 2021 The Project Oak Authors                                   *)
(*                                                                          *)
(* Licensed under the Apache License, Version 2.0 (the "License")           *)
(* you may not use this file except in compliance with the License.         *)
(* You may obtain a copy of the License at                                  *)
(*                                                                          *)
(*     http://www.apache.org/licenses/LICENSE-2.0                           *)
(*                                                                          *)
(* Unless required by applicable law or agreed to in writing, software      *)
(* distributed under the License is distributed on an "AS IS" BASIS,        *)
(* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. *)
(* See the License for the specific language governing permissions and      *)
(* limitations under the License.                                           *)
(****************************************************************************)

Require Import Coq.Strings.String.
Require Import Coq.Strings.HexString.
Require Import Coq.Lists.List.
Require Import Coq.NArith.NArith.

Require Import Cava.Types.
Require Import Cava.Expr.
Require Import Cava.Primitives.

Import ListNotations.
Import PrimitiveNotations.

Local Open Scope string_scope.
Local Open Scope N.

Section Var.
  Import ExprNotations.

  Context {var : tvar}.

  Definition fifo {T} {fifo_size}: Circuit _ [Bit; T; Bit] (Bit ** T ** Bit) :=
    let fifo_bits := BitVec (Nat.log2 fifo_size) in
    {{
    fun data_valid data out_ready =>

    let/delay '(fifo; current_length) :=

      ( if data_valid then data +>> fifo else fifo
      , if data_valid && !out_ready then current_length + `K 1`
        else if !data_valid && out_ready && current_length >= `K 1` then (current_length - `K 1`)
        else current_length
      )

      initially (@default (Vec T fifo_size), 0)
        : denote_type (Vec T fifo_size ** fifo_bits) in

    ( current_length >= `K 0`
    , `index` fifo (current_length - `K 1`)
    , (current_length >= `Constant ((N.of_nat fifo_size - 1) : denote_type fifo_bits)` ) )
  }}.

End Var.

Require Import Cava.Semantics.
Require Import Cava.Util.List.
Require Import Cava.Util.Tactics.

Definition no_io_predicate (x: denote_type (Bit**BitVec 32**Bit**Unit))
  := fst x = false /\ fst (snd (snd x)) = false.

Ltac destruct_input input :=
  match type of input with
  | denote_type (Pair _ _) =>
    let x := fresh input in
    let y := fresh input in
    destruct input as [x y];
    destruct_input x; destruct_input y
  | denote_type Unit => destruct input
  | _ => idtac
  end.

Lemma fifo_no_change :
  forall sz st input, no_io_predicate input ->
  st = fst (step (fifo (fifo_size:=sz)) st input).
Proof.
  intros.
  cbn [step fifo absorb_any split_absorbed_denotation combine_absorbed_denotation
    denote_type binary_semantics unary_semantics K
    ].
  destruct_input input.
  unfold no_io_predicate in H.
  cbn in H.
  destruct H.
  rewrite H, H0.
  repeat (destruct_pair_let; cbn [fst snd]).
  reflexivity.
Qed.

Lemma fifo_no_change' :
  forall sz st inputs,
  Forall no_io_predicate inputs ->
  snd (simulate' (fifo (fifo_size:=sz)) inputs st) = st.
Proof.
  intros.
  induction inputs; [reflexivity|].
  cbv [simulate'] in *.
  rewrite fold_left_accumulate'_cons_snd.
  cbn [List.app].

  apply List.Forall_cons_iff in H.
  destruct H.
  apply IHinputs in H0.
  rewrite <- (fifo_no_change _ _ _ H).
  rewrite fold_left_accumulate'_snd_acc_invariant with (acc_b:=[]%list).
  apply H0.
Qed.
