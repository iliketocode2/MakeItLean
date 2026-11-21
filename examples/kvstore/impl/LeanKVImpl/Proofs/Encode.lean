import LeanKVImpl.Proofs.Bytes
import LeanKVImpl.Core.Log

/-! `impl_encodeRecord_eq` for the core encoder (Stage 4). -/

namespace LeanKV.Proofs
open LeanKV.Spec

theorem core_encodeRecord_eq (ops : List (WriteOp ByteArray)) :
    toBytes (Core.encodeRecord ops) = encodeRecord (ops.map (WriteOp.map toBytes)) :=
  toBytes_ofBytes _

end LeanKV.Proofs
