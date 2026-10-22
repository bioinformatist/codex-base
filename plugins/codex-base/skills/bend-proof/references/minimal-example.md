# Verified predecessor example

This example was checked on x86_64 Linux with official
[Bend 2.0.38](https://github.com/bendlang/bend/releases/tag/v2.0.38) and
[Lean 4.34.0](https://github.com/leanprover/lean4/releases/tag/v4.34.0).
The [Bend kernel integration](https://github.com/bendlang/bend/blob/v2.0.38/bend2/safe.ts)
builds BendTT on first `--verdict` use with Lean 4.34.0 (`lean` and `leanc`
on PATH or the corresponding elan toolchain), caching it under the selected
home. `BENDTT` can select a prebuilt kernel instead; record its provenance.
The ordinary proof check does not provide that independent verdict.

Tool acquisition is a separate authorized action. No Bend/Lean package is
installed by Codex Base. The experiment used these official assets:

| Asset | SHA-256 |
|---|---|
| `bend-2.0.38-linux-x64.tar.gz` | `f19d088b079c9e1a8834ecd153b7d58c11a5f8f9ab1bdb78dbc96a6bf49aaa81` |
| `lean-4.34.0-linux.tar.zst` | `caaa98356098c85dc0fcbbd28e1ec66f39eb6551829972b752ff20e1286b646b` |

## Project files

Copy each block verbatim into the named file in one target-project directory.
`PROOF.bend` imports the laws, which import the implementation; it has no
runtime entry point. Laws express both zero and successor behavior.

`main.bend`:

```bend
import Base

def pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p
```

`LAWS.bend`:

```bend
import Base
import ./main.bend as Impl

law pred_zero:
  {Impl.pred(0n) == 0n : Nat}

law pred_succ:
  for +n: Nat
  {Impl.pred(1n+n) == n : Nat}
```

`PROOF.bend`:

```bend
import Base
import ./LAWS.bend as Laws

def Laws.pred_zero(): {==}

def Laws.pred_succ(n): {==}
```

`TEST.bend`:

```bend
import Base
import ./main.bend as Impl

def main() -> Nat & Nat:
  (Impl.pred(0n), Impl.pred(3n))
```

## Commands and observed results

With the fixed tools available, run in that directory:

```sh
bend version
lean --version
bend PROOF.bend
bend PROOF.bend --verdict
bend TEST.bend
```

All five commands exited 0. Version output identified `bend 2.0.38` and Lean
4.34.0. The ordinary check printed `ALL PROOFS CHECK` followed by
`Use --verdict for mathematical validity.` The formal verdict printed
`ALL PROOFS CHECK`. The test output was `(0n, 2n)`; compare both values to
the expected results, since this runtime example prints them rather than
asserting them. The first verdict, including the kernel build, took 36.834
seconds; the other commands each took less than one second on the experiment
host. These measurements are not general task budgets.

## Incorrect implementation

In a separate copy, leave laws, proof, and test unchanged and replace only
`main.bend` with:

```bend
import Base

def pred(n: Nat) -> Nat:
  0n
```

`bend PROOF.bend --verdict` exited 1 in 0.173 seconds with `SOME PROOFS FAIL`,
an equality diagnostic (`expected : 0n`, `observed : n`, context `n : Nat`),
and location `Laws.pred_succ`. This is a failure of the successor law, not a
syntax error, missing import, or timeout. Use a disposable copy for this
demonstration; keep agreed target-project properties intact.
