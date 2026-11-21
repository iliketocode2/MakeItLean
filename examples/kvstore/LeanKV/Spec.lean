import LeanKV.Spec.Bytes
import LeanKV.Spec.Model
import LeanKV.Spec.Properties
import LeanKV.Spec.Contract
import LeanKV.Spec.Wire
import LeanKV.Spec.Log
import LeanKV.Spec.Store
import LeanKV.Spec.Examples
import LeanKV.Tools.EnglishDocs

/-! Stage 1 gates: every spec declaration carries an `English:` doc, and no definition uses an
implementation hole (holes appear only in theorem statements). -/

#assert_english_docs LeanKV.Spec
#assert_holes_only_in_theorems LeanKV.Spec
