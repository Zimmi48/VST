Require Import floyd.base.
Require Import floyd.client_lemmas.
Require Import floyd.field_mapsto.
Require Import floyd.assert_lemmas.
Require Import floyd.malloc_lemmas.
Require Import floyd.array_lemmas.
Local Open Scope logic.

Fixpoint fold_right_sepcon' (l: list(environ->mpred)) : environ -> mpred :=
 match l with 
 | nil => emp
 | b::nil => b
 | b::r => b * fold_right_sepcon' r
 end.

Lemma fold_right_sepcon'_eq:
  fold_right_sepcon' = @fold_right (environ->mpred) _ sepcon emp.
Proof.
extensionality l rho.
induction l; auto.
simpl.
destruct l. simpl. rewrite sepcon_emp. auto.
f_equal; auto.
Qed.


Lemma orp_dup {A}{ND: NatDed A}: forall P: A, P || P = P.
Proof. intros. apply pred_ext.
apply orp_left; apply derives_refl.
apply orp_right1; apply derives_refl.
Qed.

Lemma mapsto_zeros_memory_block:
 forall sh n b ofs,
  0 <= n ->
  0 <= ofs ->
  ofs+n <= Int.max_unsigned ->
  mapsto_zeros n sh (Vptr b (Int.repr ofs)) |--
  memory_block sh (Int.repr n) (Vptr b (Int.repr ofs)).
Proof.
 unfold mapsto_zeros.
intros.
 rename H0 into H'. rename H1 into H2.
Transparent memory_block.
 unfold memory_block.
Opaque memory_block.
repeat rewrite Int.unsigned_repr by omega.
 rewrite <- (Z2Nat.id n) in H2 by omega.
 rewrite <- (Z2Nat.id n) in H by omega.
 change nat_of_Z with Z.to_nat.
 forget (Z.to_nat n) as n'.
 revert ofs H H' H2;  induction n'; intros.
 simpl; auto.
 rewrite inj_S in H2. unfold Z.succ in H2.
 apply sepcon_derives; auto.
 unfold mapsto_, mapsto.
 apply orp_right2.
 rewrite prop_true_andp by auto.
 apply exp_right with (Vint Int.zero).
 rewrite Int.unsigned_repr by omega. 
 auto.
 fold address_mapsto_zeros. fold memory_block'.
 apply IHn'. omega. omega. omega.
Qed.


Lemma tc_globalvar_sound:
  forall Delta i t gv idata rho, 
   (var_types Delta) ! i = None ->
   (glob_types Delta) ! i = Some (Global_var t) ->
   gvar_volatile gv = false ->
   gvar_init gv = idata ->
   tc_environ Delta rho ->
   globvar2pred(i, gv) rho |-- init_data_list2pred idata (readonly2share (gvar_readonly gv)) (eval_var i t rho) rho.
Proof.
pose (H2:=True).
pose (H4:=True).
pose (H5:=True); intros.
unfold globvar2pred.
simpl.
destruct H6 as [? [? [? ?]]].
destruct (H9 i _ H0); [ | destruct H10; congruence].
destruct (H8 _ _ H0) as [b [? ?]].
rewrite H11. rewrite H1.
rewrite H3; simpl.
unfold eval_var.
unfold Map.get. rewrite H10. rewrite H11.
simpl. rewrite eqb_type_refl.
simpl.
change (Share.splice extern_retainer Tsh) with Ews.
auto.
Qed.

Definition zero_of_type (t: type) : val :=
 match t with
  | Tfloat _ _ => Vfloat Float.zero
  | _ => Vint Int.zero
 end.

Definition init_data2pred' (Delta: tycontext)  (d: init_data)  (sh: share) (ty: type) (v: environ->val) : environ -> mpred :=
 match d with
  | Init_int8 i => `(mapsto sh tuchar) v `(Vint (Int.zero_ext 8 i))
  | Init_int16 i => `(mapsto sh tushort) v ` (Vint (Int.zero_ext 16 i))
  | Init_int32 i => `(mapsto sh tuint) v ` (Vint i)
  | Init_int64 i => `(mapsto sh tulong) v ` (Vlong i)
  | Init_float32 r =>  `(mapsto sh tfloat) v ` (Vfloat ((Float.singleoffloat r)))
  | Init_float64 r =>  `(mapsto sh tdouble) v ` (Vfloat r)
  | Init_space n => 
      match ty  with
      | Tarray t j att => if zeq n (sizeof ty)
                                  then `(array_at_ t sh 0 j) v (* FIXME *)
                                  else TT
      | Tvoid => TT
      | Tfunction _ _ => TT
      | Tstruct _ _ _ => TT (* FIXME *)
      | Tunion _ _ _ => TT (* FIXME *)
      | Tcomp_ptr _ _ => TT
      | t=> if zeq n (sizeof t) 
                               then `(mapsto sh t) v `(zero_of_type t)
                               else  TT
      end
  | Init_addrof symb ofs => 
      match (var_types Delta) ! symb, (glob_types Delta) ! symb with
      | None, Some (Global_var (Tarray t n' att)) =>`(mapsto sh (Tpointer t noattr)) v (`(offset_val ofs) (eval_var symb (Tarray t n' att)))
      | None, Some (Global_var Tvoid) => TT
      | None, Some (Global_var t) => `(mapsto sh (Tpointer t noattr)) v (`(offset_val ofs) (eval_var symb t))
      | None, Some (Global_func f) => 
                 `(mapsto sh (Tpointer (type_of_funspec f) noattr)) v (`(offset_val ofs) (eval_var symb (type_of_funspec f)))
      | Some _, Some (Global_var (Tarray t _ att)) => `(memory_block sh (Int.repr 4)) v
      | Some _, Some (Global_var Tvoid) => TT
      | Some _, Some (Global_var t) => `(memory_block sh (Int.repr 4)) v 
      | Some _, Some (Global_func f) => `(memory_block sh (Int.repr 4)) v 
      | _, _ => TT
      end
 end.

Lemma mapsto_zeros_Tint:
  forall sh i s a b ofs,
   ofs + sizeof (Tint i s a) <= Int.max_unsigned ->
   mapsto_zeros (sizeof (Tint i s a)) sh (Vptr b (Int.repr ofs))
|-- mapsto sh (Tint i s a) (Vptr b (Int.repr ofs)) (Vint Int.zero).
Admitted.

Lemma mapsto_zeros_Tlong:
  forall sh s a b ofs,
   ofs + sizeof (Tlong s a) <= Int.max_unsigned ->
   mapsto_zeros (sizeof (Tlong s a)) sh (Vptr b (Int.repr ofs))
|-- mapsto sh (Tlong s a) (Vptr b (Int.repr ofs)) (Vint Int.zero).
Admitted.

Lemma mapsto_zeros_Tfloat:
  forall sh f a b ofs, 
   ofs + sizeof (Tfloat f a) <= Int.max_unsigned ->
  mapsto_zeros (sizeof (Tfloat f a)) sh (Vptr b (Int.repr ofs))
|-- mapsto sh (Tfloat f a) (Vptr b (Int.repr ofs)) (Vfloat Float.zero).
Admitted.

Lemma mapsto_zeros_Tpointer:
  forall sh t a b ofs, 
   ofs + sizeof (Tpointer t a) <= Int.max_unsigned ->
mapsto_zeros (sizeof (Tpointer t a)) sh (Vptr b (Int.repr ofs))
|-- mapsto sh (Tpointer t a) (Vptr b (Int.repr ofs)) (Vint Int.zero).
Admitted.

Lemma unpack_globvar_aux1:
  forall sh t a b v ofs, 
   ofs + sizeof (Tpointer t a) <= Int.max_unsigned ->
               mapsto sh (Tpointer t a) (Vptr b (Int.repr ofs)) v
                   |-- memory_block sh (Int.repr 4) (Vptr b (Int.repr ofs)).
Admitted.

Lemma sizeof_Tpointer: forall t a, sizeof (Tpointer t a) = 4.
Proof.
(* NOt quite true in CompCert 2.1, if the attributes a contain "align_as".
But it will be true again in CompCert 2.2.
*)
Admitted.

Lemma init_data_size_space:
 forall t, init_data_size (Init_space (sizeof t)) = sizeof t.
Proof. intros.
 pose proof (sizeof_pos t).
 simpl. rewrite Z.max_l; auto. omega.
Qed.

Lemma init_data2pred_rejigger:
  forall (Delta : tycontext) (t : type) (idata : init_data) (rho : environ)
     (sh : Share.t) (b : block) ofs (v : environ -> val),
  no_attr_type t = true ->
  0 <= ofs ->
  ofs + init_data_size idata <= Int.max_unsigned ->
  tc_environ Delta rho ->
  v rho = Vptr b (Int.repr 0) ->
   init_data2pred idata sh (offset_val (Int.repr ofs) (v rho)) rho 
    |-- init_data2pred' Delta idata sh t (`(offset_val (Int.repr ofs)) v) rho.
Proof.
intros until v.
intros H1 H6' H6 H7 H8.
 unfold init_data2pred', init_data2pred.
 rename H8 into H8'.
 assert (H8: offset_val (Int.repr ofs) (v rho) = Vptr b (Int.repr ofs)).
 rewrite H8'; simpl. rewrite Int.add_zero_l; auto.
 clear H8'.
 destruct idata; super_unfold_lift; try apply derives_refl.
*  
 destruct t; try (apply no_attr_e in H1; subst a); 
  try (simpl; apply TT_right);
  try (if_tac;
        [rewrite H8; unfold zero_of_type; subst z; 
         rewrite init_data_size_space in H6
        | simpl; apply TT_right
        ]).
+ apply mapsto_zeros_Tint; auto.
+ apply mapsto_zeros_Tlong; auto.
+ apply mapsto_zeros_Tfloat; auto.
+ apply mapsto_zeros_Tpointer; auto.
+  eapply derives_trans; [ apply mapsto_zeros_memory_block; try omega | ].
pose proof (sizeof_pos (Tarray t z0 a)); omega.
 rewrite memory_block_typed by assumption.
 unfold data_at_, data_at. simpl. unfold eq_rect_r, eq_rect. simpl.
 rewrite withspacer_spacer. unfold spacer.
 rewrite align_0 by (apply alignof_pos). simpl.
 rewrite emp_sepcon.
 apply array_at__array_at.
* 
   destruct ((var_types Delta) ! i) eqn:Hv;
   destruct ((glob_types Delta) ! i) eqn:Hg; 
    try destruct g; try solve [simpl; apply TT_right].
 +     destruct (proj1 (proj2 (proj2 H7)) _ _ Hg) as [b' [H15 H16]]; rewrite H15.
     simpl. destruct fs; simpl.
     rewrite H8.
     apply unpack_globvar_aux1.
     rewrite sizeof_Tpointer; simpl in H6; omega.
 +
    destruct (proj1 (proj2 (proj2 H7)) _ _ Hg) as [b' [H15 H16]]; rewrite H15.
    rewrite H8. (*clear dependent i. *)
    destruct gv; simpl; try apply TT_right; try rewrite H8;
     try  apply unpack_globvar_aux1;
     rewrite sizeof_Tpointer; simpl in H6; omega.
 +  destruct (proj1 (proj2 (proj2 H7)) _ _ Hg) as [b' [H15 H16]]; rewrite H15.
     simpl. destruct fs; simpl.
     rewrite H8. 
    assert (eval_var i (Tfunction (type_of_params (fst f)) (snd f)) rho = Vptr b' Int.zero)
      by admit.  (* straightforward *) 
    rewrite H. apply derives_refl.
+  destruct (proj1 (proj2 (proj2 H7)) _ _ Hg) as [b' [H15 H16]]; rewrite H15.
    assert (eval_var i gv rho = Vptr b' Int.zero)
      by admit.  (* straightforward *) 
    destruct gv; simpl; try apply TT_right; try rewrite H8; try rewrite H;
    apply derives_refl.
Qed.

Lemma unpack_globvar:
  forall Delta i t gv idata, 
   (var_types Delta) ! i = None ->
   (glob_types Delta) ! i = Some (Global_var t) ->
   no_attr_type t = true ->
   gvar_volatile gv = false ->
   gvar_info gv = t ->
   gvar_init gv = idata :: nil ->
   init_data_size idata <= sizeof t ->
   sizeof t <= Int.max_unsigned ->  
   local (tc_environ Delta) && globvar2pred(i, gv) |-- 
       init_data2pred' Delta idata (Share.splice extern_retainer (readonly2share (gvar_readonly gv))) t (eval_var i t).
Proof.
intros.
go_lowerx.
eapply derives_trans; [eapply tc_globalvar_sound; try eassumption | ].
forget (readonly2share (gvar_readonly gv)) as sh.
unfold init_data_list2pred.
simpl.
rewrite sepcon_emp.
destruct (tc_eval_gvar_zero _ _ _ _ H7 H H0) as [b ?].
 replace (eval_var i t rho) with (offset_val Int.zero (eval_var i t rho)) by (rewrite H8; reflexivity).
 eapply derives_trans; [eapply init_data2pred_rejigger; eauto; omega | ].
 unfold init_data2pred'.
 destruct idata; unfold_lift; try destruct t; try if_tac;
   try (rewrite H8; simpl; rewrite Int.add_zero_l; auto);
 try apply derives_refl;
 destruct ( (glob_types Delta) ! i0); try destruct g;try destruct gv0; try apply derives_refl;
   try (rewrite H8; simpl; rewrite Int.add_zero_l; auto).
Qed.

Fixpoint id2pred_star (Delta: tycontext) (sh: share) (t: type) (v: environ->val) (ofs: Z) (dl: list init_data) : environ->mpred :=
 match dl with
 | d::dl' => init_data2pred' Delta d sh t (`(offset_val (Int.repr ofs)) v)
                   * id2pred_star Delta sh t v (ofs + init_data_size d) dl'
 | nil => emp
 end.

Arguments id2pred_star Delta sh t v ofs dl rho  / .

Lemma init_data_list_size_pos : forall a, init_data_list_size a >= 0.
Admitted.

Lemma init_data_size_pos : forall a, init_data_size a > 0.
Admitted.


Lemma unpack_globvar_star:
  forall Delta i gv, 
   (var_types Delta) ! i = None ->
   (glob_types Delta) ! i = Some (Global_var (gvar_info gv)) ->
   no_attr_type (gvar_info gv) = true ->
   gvar_volatile gv = false ->
   gvar_readonly gv = false ->
   init_data_list_size (gvar_init gv) <= sizeof (gvar_info gv) <= Int.max_unsigned ->
   local (tc_environ Delta) && globvar2pred(i, gv) |-- 
       id2pred_star Delta (Share.splice extern_retainer (readonly2share (gvar_readonly gv))) (gvar_info gv) (eval_var i (gvar_info gv)) 0 (gvar_init gv).
Proof.
intros until 4.
remember (gvar_info gv) as t eqn:H3; symmetry in H3.
remember (gvar_init gv) as idata eqn:H4; symmetry in H4.
intros. 
go_lowerx.
eapply derives_trans; [eapply tc_globalvar_sound; eassumption | ].
forget (readonly2share (gvar_readonly gv)) as sh.
destruct (tc_eval_gvar_zero _ _ _ _ H7 H H0) as [b ?].
set (ofs:=0%Z).
replace (eval_var i t rho) with (offset_val (Int.repr ofs) (eval_var i t rho))
   by (rewrite H8; reflexivity).
assert (H11: init_data_list_size idata + ofs <= sizeof t)  by (unfold ofs; omega).
assert (H12:  sizeof t <= Int.max_unsigned)  by omega.
assert (0 <= ofs) by (unfold ofs; omega).
clearbody ofs.
revert ofs H9 H11 H12.
clear dependent gv. clear H H0 H6.
induction idata; simpl; auto; intros.
apply sepcon_derives.
* eapply init_data2pred_rejigger; eauto.
 pose proof (init_data_list_size_pos idata); omega.
* specialize (IHidata (ofs + init_data_size a)).
rewrite offset_offset_val.
rewrite add_repr.
 pose proof (init_data_list_size_pos idata).
pose proof (init_data_size_pos a).
 apply IHidata; try omega.
Qed.

Lemma tc_globalvar_sound_space:
  forall Delta i t gv rho, 
   (var_types Delta) ! i = None ->
   (glob_types Delta) ! i = Some (Global_var t) ->
   no_attr_type t = true ->
   gvar_volatile gv = false ->
   gvar_info gv = t ->
   gvar_init gv = Init_space (sizeof t) :: nil ->
   gvar_readonly gv = false ->
   sizeof t <= Int.max_unsigned ->
   tc_environ Delta rho ->
   globvar2pred(i, gv) rho |-- 
   data_at_ Ews t (eval_var i t rho).
Proof.
intros until 1. intros ? Hno; intros.
eapply derives_trans; [eapply tc_globalvar_sound; eassumption | ].
simpl.
rewrite <- memory_block_typed by auto.
destruct (tc_eval_gvar_zero _ _ _ _ H6 H H0) as [b ?].
rewrite H7.
unfold mapsto_zeros. rewrite sepcon_emp.
rewrite Int.unsigned_zero.
pose proof (mapsto_zeros_memory_block Ews (sizeof t) b 0).
unfold mapsto_zeros in H8. change (Int.repr 0) with Int.zero in H8.
rewrite Int.unsigned_zero in H8. rewrite H4. apply H8.
pose (sizeof_pos t); omega. omega. omega.
Qed.

Lemma array_at_emp:
 forall t sh f lo v, array_at t sh f lo lo v = !!isptr v && emp.
Proof. intros. unfold array_at, rangespec.
replace (lo-lo) with 0 by omega.
simpl. auto.
Qed.

Lemma idpred2_star_ZnthV_tint:
 forall Delta sh n v (data: list int) mdata,
  n = Zlength mdata ->
  mdata = map Init_int32 data ->
  local (`isptr v) && id2pred_star Delta sh (tarray tint n) v 0 mdata |--
  `(array_at tint sh (ZnthV tint (map Vint data)) 0 n) v.
Proof.
intros. subst n mdata.
replace (Zlength (map Init_int32 data)) with (Zlength data)
 by (repeat rewrite Zlength_correct; rewrite map_length; auto).
go_lowerx.
set (ofs:=0%Z).
unfold ofs at 1.
change 0 with (ofs*4)%Z.
set (N := Zlength data). unfold N at 2. clearbody N.
replace (Zlength data) with (ofs + Zlength data) by (unfold ofs; omega).
replace (ZnthV tint (map Vint data)) with (fun i => ZnthV tint (map Vint data) (i-ofs))
  by (extensionality i; unfold ofs; rewrite Z.sub_0_r; auto).
clearbody ofs.
rename H into H'.

revert ofs;
induction data; intros; simpl; auto.
* rewrite Zlength_nil. unfold array_at, rangespec; simpl.
 replace (ofs+0-ofs) with 0 by omega. simpl. normalize.
* rewrite Zlength_cons.
replace (ofs*4+4) with ((Z.succ ofs) * 4)%Z 
 by (unfold Z.succ; rewrite Z.mul_add_distr_r; reflexivity).
replace (ofs + Z.succ (Zlength data)) with (Z.succ ofs + Zlength data) by omega.
rewrite (split3_array_at ofs).
rewrite array_at_emp.
rewrite prop_true_andp by auto. rewrite emp_sepcon.
apply sepcon_derives; auto.
unfold_lift.
rewrite mapsto_tuint_tint.
rewrite mapsto_isptr.
apply derives_extract_prop. intro.
destruct (v rho); inv H.
simpl offset_val.
unfold add_ptr_int; simpl.
rewrite mul_repr.
unfold ZnthV.
change (align 4 4) with 4.
rewrite Zmult_comm.
rewrite if_false by omega.
rewrite Z.sub_diag. simpl nth. auto.
eapply derives_trans; [ apply IHdata | ].
apply derives_refl'.
apply equal_f. apply array_at_ext.
intros. unfold ZnthV. if_tac. rewrite if_true by omega. auto.
rewrite if_false by omega.
assert (Z.to_nat (i-ofs) = S (Z.to_nat (i - Z.succ ofs))).
apply Nat2Z.inj. rewrite inj_S. rewrite Z2Nat.id by omega.
rewrite Z2Nat.id by omega. omega.
rewrite H1. simpl. auto.
rewrite Zlength_correct; clear; omega.
Qed.


Lemma map_instantiate:
  forall {A B} (f: A -> B) (x: A) (y: list B) z,
    y = map f z ->  f x :: y = map f (x :: z).
Proof. intros. subst. reflexivity. Qed.


Lemma unpack_globvar_array:
  forall data n Delta i gv, 
   (var_types Delta) ! i = None ->
   (glob_types Delta) ! i = Some (Global_var (gvar_info gv)) ->
   gvar_info gv = tarray tint n ->
   gvar_volatile gv = false ->
   gvar_readonly gv = false ->
   n = Zlength (gvar_init gv) ->
   gvar_init gv = map Init_int32 data ->
   init_data_list_size (gvar_init gv) <= sizeof (gvar_info gv) <= Int.max_unsigned ->
   local (tc_environ Delta) && globvar2pred(i, gv) |-- 
      `(array_at tint (Share.splice extern_retainer (readonly2share (gvar_readonly gv)))
    (ZnthV tint (map Vint data)) 0 n) (eval_var i (tarray tint n)).
Proof.
 intros.
 match goal with |- ?A |-- _ =>
 eapply derives_trans with (local (`isptr (eval_var i (tarray tint n))) && A)
 end.
 apply andp_right; auto.
 go_lowerx. apply prop_right. eapply eval_var_isptr; eauto.
 right; split; auto. rewrite <- H1; auto.
 eapply derives_trans;[ apply andp_derives; 
                                    [ apply derives_refl 
                                    | eapply unpack_globvar_star; try eassumption; try reflexivity ] |].
rewrite H1; reflexivity.
 rewrite H1. rewrite H3. rewrite H5.
 change (Share.splice extern_retainer (readonly2share false)) with Ews. 
 eapply derives_trans; [ |  apply idpred2_star_ZnthV_tint].
 apply derives_refl.
 rewrite <- H5. auto. auto.
Qed.

Lemma main_pre_eq:
 forall prog u, main_pre prog u = 
  fold_right_sepcon' (map globvar2pred (prog_vars prog)).
Proof.
intros. rewrite fold_right_sepcon'_eq; reflexivity.
Qed.

Definition expand_globvars (Delta: tycontext)  (R R': list (environ -> mpred)) :=
 forall rho, 
    tc_environ Delta rho ->
  SEPx R rho |-- SEPx R' rho.

Lemma do_expand_globvars:
 forall R' Espec Delta P Q R c Post,
 expand_globvars Delta R R' ->
 @semax Espec Delta (PROPx P (LOCALx Q (SEPx R'))) c Post ->
 @semax Espec Delta (PROPx P (LOCALx Q (SEPx R))) c Post.
Proof.
intros.
eapply semax_pre; [ | apply H0].
clear H0.
go_lower.
normalize.
Qed.

Lemma do_expand_globvars_cons: 
   forall Delta A A' R R',
  local (tc_environ Delta) && A |-- A' ->
  expand_globvars Delta R R' ->
  expand_globvars Delta (A::R) (A'::R').
Proof.
intros.
hnf in H|-*.
intros.
apply sepcon_derives; auto.
specialize (H rho).
simpl in H. unfold local in H.
eapply derives_trans; [ | apply H].
apply andp_right; auto. apply prop_right; auto.
Qed.

Lemma do_expand_globvars_nil:
  forall Delta, expand_globvars Delta nil nil.
Proof.
intros. hnf; intros.
auto.
Qed.

Ltac expand_one_globvar :=
 (* given a proof goal of the form   local (tc_environ Delta) && globvar2pred (_,_) |-- ?33 *)
first [
    eapply unpack_globvar;
      [reflexivity | reflexivity | reflexivity | reflexivity | reflexivity | reflexivity
      | reflexivity | compute; congruence ]
 | eapply unpack_globvar_array;
      [reflexivity | reflexivity | reflexivity | reflexivity | reflexivity
      | compute; clear; congruence 
      | repeat eapply map_instantiate; symmetry; apply map_nil
      | compute; split; clear; congruence ]
 | eapply derives_trans;
    [ apply unpack_globvar_star; 
        [reflexivity | reflexivity | reflexivity | reflexivity
        | reflexivity | compute; split; clear; congruence ]
    |  cbv beta; simpl gvar_info; simpl gvar_readonly; simpl readonly2share;
      change (Share.splice extern_retainer Tsh) with Ews
    ]; apply derives_refl
 | apply andp_left2; apply derives_refl
 ].

Ltac expand_main_pre := 
 rewrite main_pre_eq; simpl fold_right_sepcon;
 eapply do_expand_globvars;
 [repeat 
   (eapply do_expand_globvars_cons;
    [ expand_one_globvar | ]);
   apply do_expand_globvars_nil
 |  ];
 unfold init_data2pred'; simpl.

