#!/usr/bin/env python3
"""Turn a VERINA task into a workspace for one arm of Phase 4, experiment A.

    convert.py framework TASK_DIR OUT_DIR    a `mil init --pure` app (spec author, critic, implementer, prover)
    convert.py baseline  TASK_DIR OUT_DIR    one Lean file in VERINA's own layout (a single agent)

Both arms get exactly the same information: the task's description and its signature. Neither
gets the reference solution (code, spec or proof) or the tests (`test.json`, `reject_inputs.json`):
those stay in the dataset and are used only by `score.py`. The task directory is read as data.
"""
import json, os, re, subprocess, sys

ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MIL = os.path.join(ROOT, "cli", ".lake", "build", "bin", "mil")
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_']*$")
TYPE_OK = re.compile(r"^[A-Za-z0-9_ ()×,]*$")


def load(task_dir):
    task = json.load(open(os.path.join(task_dir, "task.json")))
    sig = task["signature"]
    name, params, ret = sig["name"], sig["parameters"], sig["return_type"]
    if not IDENT.match(name) or not TYPE_OK.match(ret) or any(
            not IDENT.match(p["param_name"]) or not TYPE_OK.match(p["param_type"]) for p in params):
        raise SystemExit(f"unexpected signature text in {task['id']}; refusing to generate Lean from it")
    desc = open(os.path.join(task_dir, "description.txt")).read().strip()
    return task["id"], name, params, ret, desc


def app_name(task_id):
    return "".join(w.capitalize() for w in task_id.split("_"))   # verina_basic_1 -> VerinaBasic1


def binders(params):
    return " ".join(f"({p['param_name']} : {p['param_type']})" for p in params)


def arg_names(params):
    return " ".join(p["param_name"] for p in params)


def requirements(task_id, name, params, ret, desc, how):
    return f"""# {task_id} — Requirements (benchmark task; Phase 4 experiment A)

> **Status: APPROVED by the benchmark protocol** (docs/PHASE4.md): the task statement below is the
> approved requirement; there is no user sign-off in this run. Halt and report (do not guess) if the
> task needs Mathlib or another forbidden dependency, if it is ambiguous in a way you cannot settle,
> or if the build is broken before you change anything.

## Task
{desc}

## Signature
`{name} {binders(params)} : {ret}`

## What to deliver
{how}
"""


def framework(task_dir, out):
    task_id, name, params, ret, desc = load(task_dir)
    App = app_name(task_id)
    if os.path.exists(out):
        raise SystemExit(f"{out} exists")
    subprocess.run([MIL, "init", "--pure", App, out], check=True, cwd=ROOT, capture_output=True)
    B, A = binders(params), arg_names(params)
    sp = os.path.join(out, App, "Spec")
    W = lambda p, s: open(p, "w").write(s)
    W(os.path.join(sp, "Model.lean"), f"""/-!
# {App} spec: the function's contract (SPEC AUTHOR: write this)

Replace both `sorry`s with the precondition and postcondition the requirements describe, in
VERINA's shape (the postcondition receives the result and the precondition proof). Keep them
decidable (`@[reducible]`, decidable pieces) so worked examples can be checked with `decide`.
Every declaration needs an `English:` doc.
-/

namespace {App}.Spec

/-- English: (spec author) Which inputs are allowed. -/
@[reducible] def {name}_precond {B} : Prop := sorry

/-- English: (spec author) What a correct result satisfies. -/
@[reducible] def {name}_postcond {B} (result : {ret}) (_h : {name}_precond {A}) : Prop := sorry

end {App}.Spec
""")
    W(os.path.join(sp, "Properties.lean"), f"""import {App}.Spec.Model

/-!
# {App} spec: worked examples (SPEC AUTHOR and SPEC CRITIC: write these)

From the requirements: for chosen inputs, `#guard decide ({name}_postcond … expected …)` (sound) and
`#guard !decide ({name}_postcond … wrong …)` (complete); likewise for the precondition.
-/

namespace {App}.Spec

end {App}.Spec
""")
    W(os.path.join(sp, "Contract.lean"), f"""import {App}.Spec.Model

/-!
# {App} spec: the implementation contract (generated from the signature; do not edit)
-/

namespace {App}.Spec

/-- English: IMPLEMENTATION HOLE. The function, on inputs that meet the precondition. -/
def Impl.{name} {B} (h : {name}_precond {A}) : {ret} := sorry

/-- English: The obligation: on every allowed input, the implementation's result meets the
postcondition. -/
theorem impl_{name}_ok {B} (h : {name}_precond {A}) :
    {name}_postcond {A} (Impl.{name} {A} h) h := sorry

end {App}.Spec
""")
    impl = os.path.join(out, "impl", f"{App}Impl")
    W(os.path.join(impl, "Core.lean"), f"""import {App}.Spec.Model

/-! {App} implementation (IMPLEMENTER: write this). -/

namespace {App}Impl
open {App}.Spec

/-- The function (fills `Impl.{name}`). -/
def {name} {B} (h : {name}_precond {A}) : {ret} := sorry

end {App}Impl
""")
    W(os.path.join(impl, "Proofs.lean"), f"""import {App}Impl.Core

/-! Proof of the {App} obligation (PROVER: write this). -/

namespace {App}Impl
open {App}.Spec

theorem {name}_ok {B} (h : {name}_precond {A}) :
    {name}_postcond {A} ({name} {A} h) h := by
  sorry

end {App}Impl
""")
    W(os.path.join(out, "impl", "fill.json"), json.dumps({
        "holes": {f"{App}.Spec.Impl.{name}": f"{App}Impl.{name} {A} h"},
        "obligations": {f"{App}.Spec.impl_{name}_ok": f"{App}Impl.{name}_ok {A} h"}}, indent=2) + "\n")
    cfg = json.load(open(os.path.join(out, "mil.json")))
    cfg["holes"] = [f"{App}.Spec.Impl.{name}"]
    cfg["obligations"] = [f"{App}.Spec.impl_{name}_ok"]
    W(os.path.join(out, "mil.json"), json.dumps(cfg, indent=2) + "\n")
    W(os.path.join(out, "REQUIREMENTS.md"), requirements(task_id, name, params, ret, desc,
        "The MakeItLean workflow for a pure function (agents/AGENTS.md): the spec in "
        f"`{App}/Spec/Model.lean` and worked examples in `Properties.lean` (spec author, then spec "
        f"critic), the function in `impl/{App}Impl/Core.lean` (implementer), its proof in "
        f"`impl/{App}Impl/Proofs.lean` (prover). Done when `mil judge {out}/mil.json` prints ACCEPTED."))
    W(os.path.join(out, "TRUST.md"), f"# {task_id} — Trust manifest\n\n> Benchmark run: written by the auditor if the run reaches Stage 6.\n")
    print(json.dumps({"arm": "framework", "task": task_id, "app": App, "dir": out,
                      "score": {"imports": f"{App}.Spec.Model,{App}Impl.Core", "pre": f"{App}.Spec.{name}_precond",
                                "post": f"{App}.Spec.{name}_postcond", "code": f"{App}Impl.{name}",
                                "cwd": os.path.join(out, "impl")}}))


def baseline(task_dir, out):
    task_id, name, params, ret, desc = load(task_dir)
    B, A = binders(params), arg_names(params)
    os.makedirs(out, exist_ok=False)
    open(os.path.join(out, "Solution.lean"), "w").write(f"""/-
{task_id}. Replace every `sorry` (precondition, function, postcondition, proof). Lean 4.36,
core library only (no Mathlib); no `sorry`, no custom axioms, no `native_decide` in the result.
Check your work with: `elan run leanprover/lean4:v4.36.0 lean Solution.lean`
-/

/-- Which inputs are allowed. -/
@[reducible] def {name}_precond {B} : Prop := sorry

/-- The function. -/
def {name} {B} (h_precond : {name}_precond {A}) : {ret} := sorry

/-- What a correct result satisfies. -/
@[reducible] def {name}_postcond {B} (result : {ret}) (h_precond : {name}_precond {A}) : Prop := sorry

/-- The function meets its postcondition on every allowed input. -/
theorem {name}_spec_satisfied {B} (h_precond : {name}_precond {A}) :
    {name}_postcond {A} ({name} {A} h_precond) h_precond := by
  sorry
""")
    open(os.path.join(out, "REQUIREMENTS.md"), "w").write(requirements(task_id, name, params, ret, desc,
        "Fill in `Solution.lean`: the precondition, the function, the postcondition, and a proof that "
        "the function meets the postcondition. It must build with Lean 4.36 and the core library only."))
    print(json.dumps({"arm": "baseline", "task": task_id, "dir": out,
                      "score": {"prelude": os.path.join(out, "Solution.lean"), "pre": f"{name}_precond",
                                "post": f"{name}_postcond", "code": name}}))


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("framework", "baseline"):
        raise SystemExit(__doc__)
    (framework if sys.argv[1] == "framework" else baseline)(os.path.realpath(sys.argv[2]), os.path.realpath(sys.argv[3]))
