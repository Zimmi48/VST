(*Stephen Yi-Hsien Lin 05/15/2013,  modified by Andrew Appel, October 2013 *)

Require Recdef.
Require Import Integers.
Require Import Coqlib.
Require Import Coq.Strings.String.
Require Import Coq.Strings.Ascii.

Notation "[ ]" := nil.
Notation "[ x , .. , y ]" := (cons x .. (cons y []) ..).

(* PREPROCESSING: CONVERTING STRINGS TO PADDED MESSAGE BLOCKS *)

(*converting a string to a list of N*)
Fixpoint str_to_Z (str : string) : list Z :=
  match str with
    |EmptyString => nil
    |String c s => Z.of_N (N_of_ascii c) :: str_to_Z s
    end.

(*combining four Z into a Integer*)
Definition Z_to_Int (a b c d : Z) : Int.int :=
  Int.or (Int.or (Int.or (Int.shl (Int.repr a) (Int.repr 24)) (Int.shl (Int.repr b) (Int.repr 16)))
            (Int.shl (Int.repr c) (Int.repr 8))) (Int.repr d).

Function zeros (n : Z) {measure Z.to_nat n} : list Int.int :=
 if Z.gtb n 0 then Int.zero :: zeros (n-1) else nil.
Proof.
   intros. rewrite Z2Nat.inj_sub by omega.
   apply Zgt_is_gt_bool in teq.
   assert (0 < n) by omega. apply Z2Nat.inj_lt in H; try omega.
   simpl in H. change (Z.to_nat 1) with 1%nat. omega.
Defined.

Definition padlen (n: Z) : list Int.int :=
    let p := Zdiv (n+4) 4 + 2 (* number of words with trailing 128-byte, 
                                                      up to 3 zero bytes, and 2 length words *)
    in let q := 16 - (Zmod p 16)   (* number of zero-pad words *)
      in zeros q ++ [Int.repr (n * 8 / Int.modulus), Int.repr (n * 8)].

Fixpoint generate_and_pad (n: list Z) len : list Int.int :=
  match n with
  | nil => Z_to_Int 128 0 0 0 :: padlen len
  | [h1]=> Z_to_Int h1 128 0 0 :: padlen (len+1)
  | [h1, h2] => Z_to_Int h1 h2 128 0 :: padlen (len+2)
  | [h1, h2, h3] => Z_to_Int h1 h2 h3 128 :: padlen (len+3)
  | h1::h2::h3::h4::t => Z_to_Int h1 h2 h3 h4 :: generate_and_pad t (len+4)
  end.

Definition generate_and_pad_msg (n: list Z) : list Int.int :=
   generate_and_pad n 0.

(* FUNCTIONS USED ONLY FOR DEBUGGING AND TESTING *)
Definition hexdigit(a: Z) : Z :=
 if Z.leb 48 a && Z.ltb a 58 then Z.sub a 48
 else if Z.leb 65 a && Z.ltb a 71 then Z.sub a 55
 else if Z.leb 97 a && Z.ltb a 103 then Z.sub a 87
 else 0%Z.

Fixpoint hexstring_to_Zlist (s: string): list Z  :=
 match s with
 | String a (String b r) =>  (hexdigit (Z.of_N (N_of_ascii a)) * 16 
                                         + hexdigit (Z.of_N (N_of_ascii b)))
                                          :: hexstring_to_Zlist r
 | _ => nil
 end.

(*ROUND FUNCTION*)

(*hardcoding the constants, first 32 bits of the fractional parts of the cube roots of the first 64 prime numbers*)
Definition K := map Int.repr
  [1116352408 , 1899447441, 3049323471, 3921009573,
   961987163   , 1508970993, 2453635748, 2870763221,
   3624381080, 310598401  , 607225278  , 1426881987,
   1925078388, 2162078206, 2614888103, 3248222580,
   3835390401, 4022224774, 264347078  , 604807628,
   770255983  , 1249150122, 1555081692, 1996064986,
   2554220882, 2821834349, 2952996808, 3210313671,
   3336571891, 3584528711, 113926993  , 338241895,
   666307205  , 773529912  , 1294757372, 1396182291,
   1695183700, 1986661051, 2177026350, 2456956037,
   2730485921, 2820302411, 3259730800, 3345764771,
   3516065817, 3600352804, 4094571909, 275423344,
   430227734  , 506948616  , 659060556  , 883997877,
   958139571  , 1322822218, 1537002063, 1747873779,
   1955562222, 2024104815, 2227730452, 2361852424,
   2428436474, 2756734187, 3204031479, 3329325298].

(*functions used for round function*)
Definition Ch (x y z : int) : int :=
  Int.xor (Int.and x y) (Int.and (Int.not x) z).

Definition Maj (x y z : int) : int :=
  Int.xor (Int.xor (Int.and x z) (Int.and y z) ) (Int.and x y).

Definition Sh b x := Int.ror x (Int.repr b).
Definition Rt b x := Int.shru x (Int.repr b).

Definition Sigma_0 (x : int) : int := Int.xor (Int.xor (Sh 2 x) (Sh 13 x)) (Sh 22 x).
Definition Sigma_1 (x : int) : int := Int.xor (Int.xor (Sh 6 x) (Sh 11 x)) (Sh 25 x).
Definition sigma_0 (x : int) : int := Int.xor (Int.xor (Sh 7 x) (Sh 18 x)) (Rt 3 x).
Definition sigma_1 (x : int) : int := Int.xor (Int.xor (Sh 17 x) (Sh 19 x)) (Rt 10 x).

(*word function*)
Definition W (msg : list int) : int :=
 match msg with
 | x0::x1::x2::x3::x4::x5::x6::x7::x8::x9::x10::x11::x12::x13::x14::x15::_ =>
   (Int.add (Int.add (sigma_1 x1) x6) (Int.add (sigma_0 x14) x15))
 | _ => Int.zero  (* impossible *)
 end.

(*generating 64 words for the given message block imput*)
Fixpoint generate_word (msg : list int) (n : nat) {struct n}: list int :=
  match n with
  |O   => msg 
  |S n' => generate_word (W msg :: msg) n'
  end.
Arguments generate_word msg n : simpl never.
Global Opaque generate_word. (* for some reason the Arguments...simpl-never
   command does not do the job *)


(*registers that represent intermediate and final hash values*)
Definition registers := list int.

(*initializing the values of registers, first thirty-two bits of the fractional
    parts of the square roots of the first eight prime numbers*)
Definition init_registers : registers := 
  map Int.repr  [1779033703, 3144134277, 1013904242, 2773480762,
                        1359893119, 2600822924, 528734635, 1541459225].

Fixpoint map2 {A B C: Type} (f: A -> B -> C) (al: list A) (bl: list B) : list C :=
 match al, bl with
  | a::al', b::bl' => f a b :: map2 f al' bl'
  | _, _ => nil
  end.

Definition registers_add: registers -> registers -> registers := map2 Int.add.

(*round function*)
Definition rnd_function (x : registers) (k : int) (w : int) : registers:=
  match x with 
  |  [a, b, c, d, e, f, g, h] => 
    [Int.add (Int.add (Int.add (Int.add (Int.add h (Sigma_1 e)) (Ch e f g)) k) w)
                        (Int.add (Sigma_0 a) (Maj a b c)),
     a, b, c,
     Int.add (d) (Int.add (Int.add (Int.add (Int.add h (Sigma_1 e)) (Ch e f g)) k) w),
     e, f, g]
  | _ => nil  (* impossible *)
  end.

(*execute round function for 64 rounds*)
Fixpoint rnd_64 (x: registers) (k w : list int) : registers :=
  match k, w with
  | k1::k', w1::w' => rnd_64 (rnd_function x k1 w1) k' w'
  | _ , _ => x
  end.
Arguments rnd_64  x k w : simpl never.  (* blows up otherwise *)

Definition process_block (r: registers) (block: list int) : registers :=
       (registers_add r (rnd_64 r K (rev(generate_word block 48)))).

Fixpoint grab_and_process_block (n: nat) (r: registers) (firstrev msg: list int) : registers * list int :=
 match n, msg with
  | O, _ => (process_block r firstrev, msg)
  | S n', m1::msg' => grab_and_process_block n' r (m1::firstrev) msg'
  | _, nil => (r,nil) (* impossible *)
 end.

(*iterate through all the message blocks; this could have been done with just a Fixpoint
  if we incorporated grab_and_process_block into process_msg, but I wanted to 
  modularize a bit more. *)
Function process_msg  (r: registers) (msg : list int) {measure List.length msg}  : registers :=
 match msg with
 | nil => r
 | _ => let (r', msg') := grab_and_process_block 16 r nil msg
             in process_msg r' msg'
 end.
Proof.
  intros; subst.
  simpl.
  assert (Datatypes.length msg' <= Datatypes.length l)%nat; [ | omega].
  simpl in teq0.
  do 16 (destruct l; [inv teq0; solve [simpl; auto 50] | ]).
  unfold process_block in teq0.
  assert (i15::l = msg') by congruence.
  subst msg'.
  simpl.
  omega.
Defined.

(*wrapping up everything*)

Fixpoint intlist_to_Zlist (l: list int) : list Z :=
 match l with
 | nil => nil
 | i::r =>
     Int.unsigned (Rt 24 i) ::
     Int.unsigned (Int.and (Rt 16 i) (Int.repr 255)) ::
     Int.unsigned (Int.and (Rt 8 i) (Int.repr 255)) ::
     Int.unsigned (Int.and i (Int.repr 255)) ::
     intlist_to_Zlist r
 end.

Definition SHA_256 (str : list Z) : list Z :=
    intlist_to_Zlist (process_msg init_registers (generate_and_pad_msg str)).

(*EXAMPLES*)

Fixpoint listZ_eq (al bl: list Z) : bool :=
 match al, bl with
 | nil, nil => true
 | a::al', b::bl' => Z.eqb a b && listZ_eq al' bl'
 | _, _ => false
  end.

Definition check m h := 
  listZ_eq (SHA_256 (str_to_Z m)) (hexstring_to_Zlist h) = true.

(*This input message is 344 bits long, which would have one message block after padding*)
Goal  check   "The quick brown fox jumps over the lazy dog"
  "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592".
Proof. vm_compute; auto. Qed.

(*This input message would have four message blocks after padding*)
Goal check "The Secure Hash Algorithm is a family of cryptographic hash functions published by the National Institute of Standards and Technology (NIST) as a U.S. Federal Information Processing Standard (FIPS)"
 "27c3971526f07a22decc4dc01340c6c4b972ba6d31b74fb1fbb2edf2bce5fea6".
Proof. vm_compute; auto. Qed.
