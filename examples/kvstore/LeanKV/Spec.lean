import LeanKV.Spec.Bytes
import LeanKV.Spec.Model
import LeanKV.Spec.Properties
import LeanKV.Spec.Contract
import LeanKV.Tools.EnglishDocs

/-! Stage 1 gate: every spec declaration must carry an `English:` doc. -/

#assert_english_docs LeanKV.Spec
