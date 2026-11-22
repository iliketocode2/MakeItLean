import Lake
open Lake DSL

/-! AppName: a worked example of an app on the LeanKV substrate (spec package). -/
package appname

require leankvImpl from "../kvstore/impl"
require makeitlean from "../../lean"

@[default_target]
lean_lib AppNameSpec where
  roots := #[`AppName.Spec]
