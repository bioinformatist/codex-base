//! Native public lifecycle tests: real Git/Worktrunk, temporary state/config, shell Codex substitute.
use codex_improve::{
    contracts::{CONTRACT, digest},
    state::StateStore,
};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Child, Command, Output, Stdio},
    thread,
    time::{Duration, Instant},
};

const CLI: &str = env!("CARGO_BIN_EXE_codex-improve");
const FAKE: &str = r#"#!/bin/sh
if [ "${1-}" = --version ]; then echo 'codex-cli fixture'; exit; fi
if [ -n "${FAKE_CAPTURE-}" ]; then printf '%s\n' "$@" > "$FAKE_CAPTURE"; fi
if [ -n "${FAKE_PROMPT-}" ]; then cat > "$FAKE_PROMPT"; fi
if [ -n "${FAKE_TOUCH-}" ]; then printf 'changed\n' > "$FAKE_TOUCH"; fi
final= images=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-last-message) final=$2; shift ;;
        --image) images="${images}${images:+,}\"$(basename "$2")\""; shift ;;
    esac
    shift
done
case "${FAKE_MODE-complete}" in
    budget) printf '%s\n' '{"type":"error","message":"shared rollout token budget exhausted"}'; exit 1 ;;
    exit124) printf '%s\n' '{"type":"thread.started"}'; exit 124 ;;
    nested)
        trap '' INT
        printf '%s\n' '{"type":"thread.started","thread_id":"partial-evidence"}'
        echo partial-diagnostic >&2
        sleep 60 </dev/null >/dev/null 2>&1 &
        echo "$!" > "$FAKE_CHILD"
        echo "$$" > "$FAKE_PID"
        echo "$PPID" > "$FAKE_WORKER"
        wait
        exit ;;
esac
printf '%s\n' '{"type":"thread.started"}' '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}'
case "${FAKE_MODE-complete}" in
    corrupt) printf '{broken' > "$final" ;;
    empty) : ;;
    oversized) head -c 65537 /dev/zero > "$final" ;;
    review)
        if [ -n "${FAKE_REPORT-}" ]; then cat "$FAKE_REPORT" > "$final"; else
            printf '%s\n' '{"verdict":"APPROVE","summary":"Checked","findings":[],"coverage":[{"check":"scope","status":"PASS","evidence":"fixture"}],"review_blockers":[],"deferred_acceptance":[]}' > "$final"
        fi ;;
    visual)
        printf '{"status":"COMPLETE","inputIds":[%s],"observations":[' "$images" > "$final"
        # Fixtures use one original image; its opaque snapshot filename is its ID.
        printf '{"inputId":%s,"location":"whole frame","observation":"red rectangle","inference":"none","comparison":"none","uncertainty":"none"}],"unchecked":[],"stoppedBecause":null}\n' "$images" >> "$final" ;;
    *) printf '%s\n' '{"status":"COMPLETE","steps":["done"],"stoppedBecause":null,"filesChanged":[],"notes":[]}' > "$final" ;;
esac
"#;

struct Fixture {
    temp: tempfile::TempDir,
    repo: PathBuf,
    skill: PathBuf,
    state: PathBuf,
    env: BTreeMap<String, String>,
}
impl Fixture {
    fn new() -> Self {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        let repo = root.join("repo");
        let skill = root.join("skills/improve");
        let state = root.join("state");
        for path in [
            &repo,
            &skill.join("config"),
            &skill.join("references"),
            &state,
            &root.join("home/config"),
        ] {
            fs::create_dir_all(path).unwrap();
        }
        let source = Path::new(env!("CARGO_MANIFEST_DIR"));
        fs::copy(
            source.join("config/roles.json"),
            skill.join("config/roles.json"),
        )
        .unwrap();
        for name in [
            "executor-report.schema.json",
            "review-verdict.schema.json",
            "visual-report.schema.json",
        ] {
            fs::copy(
                source.join("references").join(name),
                skill.join("references").join(name),
            )
            .unwrap();
        }
        for kind in ["core", "review"] {
            let name = format!("ponytail-{kind}.md");
            fs::copy(
                source
                    .join("../../plugins/codex-base/skills/improve/references")
                    .join(&name),
                skill.join("references").join(name),
            )
            .unwrap();
        }
        let codex = root.join("selected-codex");
        fs::write(&codex, FAKE).unwrap();
        fs::set_permissions(&codex, fs::Permissions::from_mode(0o755)).unwrap();
        let env = BTreeMap::from([
            ("HOME".into(), root.join("home").display().to_string()),
            (
                "XDG_CONFIG_HOME".into(),
                root.join("home/config").display().to_string(),
            ),
            ("XDG_STATE_HOME".into(), state.display().to_string()),
            (
                "CODEX_IMPROVE_SKILL_ROOT".into(),
                skill.display().to_string(),
            ),
            ("CODEX_IMPROVE_CODEX".into(), codex.display().to_string()),
            ("GIT_CONFIG_NOSYSTEM".into(), "1".into()),
            ("GIT_CONFIG_GLOBAL".into(), "/dev/null".into()),
        ]);
        let f = Self {
            temp,
            repo,
            skill,
            state,
            env,
        };
        f.git(&["init", "-q"]);
        f.git(&["config", "user.name", "Fixture"]);
        f.git(&["config", "user.email", "fixture@example.invalid"]);
        fs::write(f.repo.join("tracked.txt"), "base\n").unwrap();
        f.git(&["add", "."]);
        f.git(&["commit", "-qm", "test: base"]);
        f
    }
    fn root(&self) -> &Path {
        self.temp.path()
    }
    fn git(&self, args: &[&str]) -> String {
        self.git_at(&self.repo, args)
    }
    fn git_at(&self, path: &Path, args: &[&str]) -> String {
        let out = Command::new("git")
            .arg("-C")
            .arg(path)
            .args(args)
            .envs(&self.env)
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8(out.stdout).unwrap().trim().into()
    }
    fn file(&self, name: &str, value: &str) -> PathBuf {
        let p = self.root().join(name);
        fs::write(&p, value).unwrap();
        p
    }
    fn json(&self, name: &str, value: &Value) -> PathBuf {
        self.file(name, &value.to_string())
    }
    fn plan(
        &self,
        name: &str,
        lane: &str,
        paths: &[&str],
        probes: Value,
        inputs: Value,
        gates: Value,
    ) -> PathBuf {
        let required: Vec<_> = gates
            .as_array()
            .unwrap()
            .iter()
            .filter(|g| g["class"] == "implementation gate")
            .map(|g| &g["id"])
            .collect();
        self.file(name, &format!("- **Improve contract**: `{CONTRACT}`\n```json codex-improve-environment\n{}\n```\n```json codex-improve-routing\n{}\n```\n```json codex-improve-gates\n{}\n```\n", json!({"version":1,"launcher":["env"],"probes":probes}), json!({"version":1,"lane":lane,"writePaths":paths,"requiredEvidence":required,"inputs":inputs}), json!({"version":1,"gates":gates})))
    }
    fn simple_plan(&self) -> PathBuf {
        self.plan(
            "plan.md",
            "standard",
            &["*"],
            json!([]),
            json!({}),
            json!([]),
        )
    }
    fn command(&self, args: &[&str], vars: &[(&str, &str)]) -> Command {
        let mut c = Command::new(CLI);
        c.args(args)
            .envs(&self.env)
            .envs(vars.iter().copied())
            .current_dir(self.root());
        c
    }
    fn raw(&self, args: &[&str], vars: &[(&str, &str)]) -> Output {
        self.command(args, vars).output().unwrap()
    }
    fn cli(&self, args: &[&str], vars: &[(&str, &str)], status: i32) -> Value {
        let out = self.raw(args, vars);
        assert_eq!(
            out.status.code(),
            Some(status),
            "{args:?}\nstdout={}\nstderr={}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        if status == 2 {
            assert!(!out.stderr.is_empty());
            return Value::Null;
        }
        let value: Value = serde_json::from_slice(&out.stdout).unwrap();
        if status == 0 && value["outcome"] == "INCONCLUSIVE" {
            panic!("{value}");
        }
        value
    }
    fn execute(&self, plan: &Path, vars: &[(&str, &str)], status: i32) -> Value {
        self.cli(&["execute", s(plan), s(&self.repo)], vars, status)
    }
    fn store(&self) -> StateStore {
        StateStore::new(Some(&self.state)).unwrap()
    }
    fn load(&self, record: &Value) -> Value {
        self.store().load(vs(&record["id"])).unwrap()
    }
    fn dossier(&self, e: &Value, evidence: Value) -> PathBuf {
        self.json("review.json", &json!({"version":1,"executionId":e["id"],"head":e.get("checkpoint_oid").unwrap_or(&e["output_head"]),"tree":e["output_candidate_tree"],"evidence":evidence,"notes":"inspect complete scope"}))
    }
    fn review(&self, e: &Value, dossier: &Path, vars: &[(&str, &str)], status: i32) -> Value {
        let mut vars = vars.to_vec();
        vars.push(("FAKE_MODE", "review"));
        self.cli(
            &[
                "review",
                vs(&e["id"]),
                vs(&e["output_candidate_tree"]),
                s(dossier),
            ],
            &vars,
            status,
        )
    }
    fn point(&self, e: &Value, status: i32) -> Value {
        self.cli(
            &[
                "checkpoint",
                vs(&e["id"]),
                vs(&e["output_candidate_tree"]),
                "--message",
                "test: reviewed candidate",
            ],
            &[],
            status,
        )
    }
}
fn s(p: &Path) -> &str {
    p.to_str().unwrap()
}
fn vs(v: &Value) -> &str {
    v.as_str().unwrap()
}
fn review_report() -> Value {
    json!({"verdict":"APPROVE","summary":"Checked","findings":[],"coverage":[{"check":"scope","status":"PASS","evidence":"fixture"}],"review_blockers":[],"deferred_acceptance":[]})
}
fn revise_report() -> Value {
    let mut r = review_report();
    r["verdict"] = "REVISE".into();
    r["coverage"][0]["status"] = "FAIL".into();
    r["findings"] = json!([{"check":"scope","severity":"medium","location":"tracked.txt:1","claim":"Wrong result","evidence":"fixture","action":"Fix result"}]);
    r
}

#[test]
fn execute_status_candidate_review_checkpoint_next_and_stale_inputs() {
    let f = Fixture::new();
    let plan = f.simple_plan();
    let capture = f.root().join("argv");
    let e = f.execute(
        &plan,
        &[("FAKE_TOUCH", "tracked.txt"), ("FAKE_CAPTURE", s(&capture))],
        0,
    );
    assert_eq!(e["outcome"], "COMPLETE");
    assert_ne!(e["candidate_tree"], e["output_candidate_tree"]);
    let w = Path::new(vs(&e["worktree"]));
    let index = PathBuf::from(f.git_at(
        w,
        &["rev-parse", "--path-format=absolute", "--git-path", "index"],
    ));
    let before = fs::read(&index).unwrap();
    let c = f.cli(&["candidate", s(w)], &[], 0);
    assert_eq!(
        c,
        json!({"head":e["output_head"],"tree":e["output_candidate_tree"]})
    );
    assert_eq!(fs::read(index).unwrap(), before);
    let status = f.cli(&["status", vs(&e["id"])], &[], 0);
    assert_eq!(status["report"], e["report"]);
    assert_eq!(status["phase"], "finished");
    assert_eq!(f.cli(&["status"], &[], 0).as_array().unwrap().len(), 1);
    let argv = fs::read_to_string(capture).unwrap();
    for arg in [
        "--strict-config",
        "--ephemeral",
        "multi_agent",
        "goals",
        "memories",
        "--output-schema",
        "permissions.improve-executor-runtime.filesystem=",
        "\".git\" = \"read\"",
        "shell_environment_policy.set.XDG_CACHE_HOME=",
    ] {
        assert!(argv.contains(arg), "{arg}: {argv}");
    }
    let dossier = f.dossier(&e, json!([]));
    let review = f.review(&e, &dossier, &[], 0);
    assert_eq!(review["outcome"], "APPROVE");
    let cached = f.review(&e, &dossier, &[("FAKE_TOUCH", "unexpected.txt")], 0);
    assert_eq!(review["id"], cached["id"]);
    assert!(!w.join("unexpected.txt").exists());
    fs::write(w.join("drift.txt"), "external drift").unwrap();
    f.point(&e, 2);
    f.review(&e, &dossier, &[], 2);
    fs::remove_file(w.join("drift.txt")).unwrap();
    let point = f.point(&e, 0);
    f.point(&e, 2);
    let oid = vs(&point["checkpoint_oid"]);
    assert_eq!(f.git_at(w, &["rev-parse", "HEAD"]), oid);
    let next = f.cli(
        &["next", vs(&e["id"]), oid, s(&plan)],
        &[("FAKE_TOUCH", "successor.txt")],
        0,
    );
    assert_eq!(next["base_head"], oid);
    assert_ne!(next["worktree"], e["worktree"]);
    assert!(w.is_dir());
    f.cli(&["next", vs(&e["id"]), oid, s(&plan)], &[], 2);
}

#[test]
fn latest_review_reconciliation_and_current_reviewer_binding() {
    let f = Fixture::new();
    let e = f.execute(&f.simple_plan(), &[("FAKE_TOUCH", "tracked.txt")], 0);
    let dossier = f.dossier(&e, json!([]));
    let first = f.review(&e, &dossier, &[], 0);
    let mut d: Value = serde_json::from_slice(&fs::read(&dossier).unwrap()).unwrap();
    d["notes"] = "New inspection".into();
    f.json("review.json", &d);
    let report = f.json("revise-report.json", &revise_report());
    let second = f.review(&e, &dossier, &[("FAKE_REPORT", s(&report))], 0);
    assert_eq!(second["parent"], first["id"]);
    assert_eq!(second["outcome"], "REVISE");
    assert!(f.load(&e).get("approval").is_none());
    f.point(&e, 2);
    let raw = fs::read(vs(&second["artifacts"]["final"])).unwrap();
    let artifact = f.file("support.txt", "Observed behavior disproves finding\n");
    let support = json!({"path":artifact,"sha256":digest(&fs::read(&artifact).unwrap())});
    let mut reconciliation = json!({"version":1,"conclusion":"APPROVE","findings":[{"index":0,"disposition":"unresolved","evidence":[support],"conclusion":"Checked reproducer"}],"evidence":[],"reason":"Evidence disposes finding"});
    let r = f.json("reconcile.json", &reconciliation);
    f.cli(&["reconcile", vs(&second["id"]), s(&r)], &[], 2);
    reconciliation["findings"][0]["disposition"] = "rejected".into();
    f.json("reconcile.json", &reconciliation);
    let reconciled = f.cli(&["reconcile", vs(&second["id"]), s(&r)], &[], 0);
    assert_eq!(reconciled["outcome"], "REVISE");
    assert_eq!(fs::read(vs(&second["artifacts"]["final"])).unwrap(), raw);
    assert_eq!(f.load(&e)["approval"]["source"], "reconciliation");
    fs::write(&artifact, "changed support").unwrap();
    f.point(&e, 2);
    f.review(&e, &dossier, &[], 2);
    fs::write(&artifact, "Observed behavior disproves finding\n").unwrap();
    assert_eq!(f.review(&e, &dossier, &[], 0)["id"], second["id"]);
    let roles_path = f.skill.join("config/roles.json");
    let mut roles: Value = serde_json::from_slice(&fs::read(&roles_path).unwrap()).unwrap();
    roles["reviewer"]["reasoningEffort"] = "medium".into();
    fs::write(&roles_path, roles.to_string()).unwrap();
    f.point(&e, 2);
    let third = f.review(&e, &dossier, &[], 0);
    assert_ne!(third["id"], second["id"]);
    assert_eq!(third["review_binding"]["reviewer"], roles["reviewer"]);
    f.cli(&["reconcile", vs(&second["id"]), s(&r)], &[], 2);
    f.point(&e, 0);
}

#[test]
fn gates_and_deferred_coverage_are_bound_and_revalidated() {
    let f = Fixture::new();
    let gate = json!({"id":"G1","class":"implementation gate","kind":"check","check":"fixture check","invalidatedBy":["**"],"environment":"fixture","conditions":"passed"});
    let deferred = json!({"id":"G5","class":"deferred acceptance","kind":"check","check":"CI","invalidatedBy":["**"],"environment":"CI","conditions":"maintainer"});
    let plan = f.plan(
        "gated.md",
        "standard",
        &["*"],
        json!([]),
        json!({}),
        json!([gate, deferred]),
    );
    let e = f.execute(&plan, &[("FAKE_TOUCH", "tracked.txt")], 0);
    f.review(&e, &f.dossier(&e, json!([])), &[], 2);
    let artifact = f.file("g1.log", "PASS\n");
    let item = json!({"gate":"G1","status":"PASS","artifact":{"path":artifact,"sha256":digest(b"PASS\n")},"environment":"fixture","head":e["output_head"],"tree":e["output_candidate_tree"],"planHash":e["plan_hash"]});
    for bad in [
        json!([item, item]),
        {
            let mut i = item.clone();
            i["status"] = "PENDING".into();
            json!([i])
        },
        {
            let mut i = item.clone();
            i["tree"] = "stale".into();
            json!([i])
        },
    ] {
        f.review(&e, &f.dossier(&e, bad), &[], 2);
    }
    let dossier = f.dossier(&e, json!([item]));
    let mut report = review_report();
    report["coverage"]
        .as_array_mut()
        .unwrap()
        .push(json!({"check":"G1","status":"PASS","evidence":"g1.log"}));
    report["deferred_acceptance"] = json!([{"check":"G5","owner":"maintainer","reason":"CI","evidence_required":"passing run"}]);
    let p = f.json("gated-review.json", &report);
    let review = f.review(&e, &dossier, &[("FAKE_REPORT", s(&p))], 0);
    assert_eq!(review["outcome"], "APPROVE");
    fs::write(artifact, "changed\n").unwrap();
    f.point(&e, 2);
}

#[test]
fn preflight_resume_once_mutation_launch_and_selected_codex() {
    let f = Fixture::new();
    let probe = f.file("probe.sh", "exit 1\n");
    let plan = f.plan(
        "probe-plan.md",
        "standard",
        &["*"],
        json!([{"argv":["sh",probe],"timeoutSeconds":2}]),
        json!({}),
        json!([]),
    );
    let failed = f.execute(&plan, &[], 0);
    assert_eq!(failed["reason"], "environment_preflight_failed");
    fs::write(&probe, "exit 0\n").unwrap();
    let resumed = f.cli(&["resume", vs(&failed["id"])], &[], 0);
    assert_eq!(resumed["outcome"], "COMPLETE");
    assert_eq!(resumed["resume_used"], true);
    assert_eq!(resumed["role_settings"], failed["role_settings"]);
    f.cli(&["resume", vs(&failed["id"])], &[], 2);
    fs::write(&probe, "echo mutation > tracked.txt\n").unwrap();
    let mutated = f.execute(&plan, &[], 0);
    assert_eq!(mutated["reason"], "environment_preflight_mutated_candidate");
    f.cli(&["resume", vs(&mutated["id"])], &[], 2);
    let launcher_plan = f.simple_plan();
    let text = fs::read_to_string(&launcher_plan).unwrap().replace(
        "\"launcher\":[\"env\"]",
        "\"launcher\":[\"sh\",\"-c\",\"printf launcher_failure_marker >&2; exit 7\",\"sh\"]",
    );
    fs::write(&launcher_plan, text).unwrap();
    let launcher = f.execute(&launcher_plan, &[], 1);
    assert_eq!(launcher["reason"], "launcher_exit_7");
    assert_eq!(
        fs::read(vs(&launcher["artifacts"]["launcher_diagnostics"])).unwrap(),
        b"launcher_failure_marker"
    );
    assert!(
        fs::read(vs(&launcher["artifacts"]["diagnostics"]))
            .unwrap()
            .is_empty()
    );
    let plan = f.simple_plan();
    let text = fs::read_to_string(&plan).unwrap().replace(
        "\"launcher\":[\"env\"]",
        "\"launcher\":[\"env\",\"CODEX_IMPROVE_TEST_LAUNCHED=1\"]",
    );
    fs::write(&plan, text).unwrap();
    let capture = f.root().join("selected-argv");
    let selected = f.execute(&plan, &[("FAKE_CAPTURE", s(&capture))], 0);
    assert_eq!(selected["outcome"], "COMPLETE");
    assert!(capture.exists());
}

#[test]
fn recovery_revision_bounds_grants_scope_and_contract_boundary() {
    let f = Fixture::new();
    let plan = f.simple_plan();
    let old = f.root().join("state/codex-improve-v18");
    fs::create_dir_all(&old).unwrap();
    fs::write(old.join("sentinel"), "untouched").unwrap();
    fs::write(
        &plan,
        fs::read_to_string(&plan)
            .unwrap()
            .replace(CONTRACT, "1.0.0-codex.18"),
    )
    .unwrap();
    let capture = f.root().join("unexpected");
    f.execute(&plan, &[("FAKE_CAPTURE", s(&capture))], 2);
    assert!(!capture.exists());
    let plan = f.simple_plan();
    let e = f.execute(
        &plan,
        &[("FAKE_MODE", "budget"), ("FAKE_TOUCH", "tracked.txt")],
        1,
    );
    assert_eq!(e["reason"], "rollout_budget_exhausted");
    assert_eq!(e["closeout_eligible"], true);
    let a = f.file("one.md", "Scope: finish first correction\n");
    let b = f.file("two.md", "Scope: finish second correction\n");
    let recovered = f.cli(
        &[
            "recover",
            vs(&e["id"]),
            s(&a),
            s(&b),
            "--expected-tree",
            vs(&e["output_candidate_tree"]),
        ],
        &[],
        0,
    );
    assert_eq!(recovered["kind"], "recover");
    let middle = f.store().load(vs(&recovered["parent"])).unwrap();
    assert_eq!(middle["parent"], e["id"]);
    f.cli(
        &[
            "recover",
            vs(&e["id"]),
            s(&a),
            "--expected-tree",
            vs(&e["output_candidate_tree"]),
        ],
        &[],
        2,
    );
    let findings = f.file("findings.md", "Finding: correct reviewed result\n");
    let mut revised = recovered;
    for _ in 0..2 {
        revised = f.cli(
            &[
                "revise",
                vs(&revised["id"]),
                s(&findings),
                "--expected-tree",
                vs(&revised["output_candidate_tree"]),
            ],
            &[],
            0,
        );
    }
    f.cli(
        &[
            "revise",
            vs(&revised["id"]),
            s(&findings),
            "--expected-tree",
            vs(&revised["output_candidate_tree"]),
        ],
        &[],
        2,
    );
    for grant in [".git", "other"] {
        f.cli(&["execute", s(&plan), s(&f.repo), "--grant", grant], &[], 2);
    }
    std::os::unix::fs::symlink("tracked.txt", f.repo.join(".codex")).unwrap();
    f.git(&["add", ".codex"]);
    f.git(&["commit", "-qm", "test: symlink grant fixture"]);
    f.cli(
        &["execute", s(&plan), s(&f.repo), "--grant", ".codex"],
        &[],
        2,
    );
    f.git(&["rm", ".codex"]);
    f.git(&["commit", "-qm", "test: remove symlink fixture"]);
    let scoped = f.plan(
        "scope.md",
        "standard",
        &["tracked.txt"],
        json!([]),
        json!({}),
        json!([]),
    );
    let stopped = f.execute(&scoped, &[("FAKE_TOUCH", "outside.txt")], 0);
    assert_eq!(stopped["outcome"], "STOPPED");
    assert_eq!(stopped["reason"], "write_paths_violation");
    fs::create_dir_all(f.repo.join(".agents")).unwrap();
    fs::write(f.repo.join(".agents/keep"), "protected").unwrap();
    f.git(&["add", "."]);
    f.git(&["commit", "-qm", "test: protected metadata"]);
    let ungranted = f.execute(&plan, &[("FAKE_TOUCH", ".agents/keep")], 0);
    assert_eq!(ungranted["reason"], "write_paths_violation");
    let granted = f.cli(
        &["execute", s(&plan), s(&f.repo), "--grant", ".agents"],
        &[("FAKE_TOUCH", ".agents/keep")],
        0,
    );
    assert_eq!(granted["outcome"], "COMPLETE");
    f.cli(
        &[
            "revise",
            vs(&granted["id"]),
            s(&findings),
            "--expected-tree",
            vs(&granted["output_candidate_tree"]),
        ],
        &[],
        2,
    );
    f.cli(
        &[
            "revise",
            vs(&granted["id"]),
            s(&findings),
            "--expected-tree",
            vs(&granted["output_candidate_tree"]),
            "--grant",
            ".agents",
        ],
        &[],
        0,
    );
    assert_eq!(
        fs::read_to_string(old.join("sentinel")).unwrap(),
        "untouched"
    );
    let record_path = f.store().path(vs(&e["id"])).unwrap().join("record.json");
    let mut bytes = fs::read(&record_path).unwrap();
    bytes[10] ^= 1;
    fs::write(record_path, bytes).unwrap();
    f.cli(&["status", vs(&e["id"])], &[], 2);
}

#[test]
fn invalid_review_retry_requires_authority_and_new_review_invalidates_approval() {
    let f = Fixture::new();
    let e = f.execute(&f.simple_plan(), &[("FAKE_TOUCH", "tracked.txt")], 0);
    let d = f.dossier(&e, json!([]));
    let first = f.review(&e, &d, &[], 0);
    let mut dossier: Value = serde_json::from_slice(&fs::read(&d).unwrap()).unwrap();
    dossier["notes"] = "fresh inspection".into();
    f.json("review.json", &dossier);
    let bad = f.json("bad-report.json", &json!({"bad":"report"}));
    let second = f.review(&e, &d, &[("FAKE_REPORT", s(&bad))], 1);
    assert_eq!(second["reason"], "invalid_final_output");
    assert!(second["validation_error"].is_string());
    assert!(f.load(&e).get("approval").is_none());
    f.point(&e, 2);
    f.review(&e, &d, &[], 2);
    f.cli(
        &[
            "review",
            vs(&e["id"]),
            vs(&e["output_candidate_tree"]),
            s(&d),
            "--retry-of",
            vs(&first["id"]),
            "--retry-authorized",
        ],
        &[("FAKE_MODE", "review")],
        2,
    );
    let third = f.cli(
        &[
            "review",
            vs(&e["id"]),
            vs(&e["output_candidate_tree"]),
            s(&d),
            "--retry-of",
            vs(&second["id"]),
            "--retry-authorized",
        ],
        &[("FAKE_MODE", "review")],
        0,
    );
    assert_eq!(third["outcome"], "APPROVE");
    f.point(&e, 0);
}

#[test]
fn visual_originals_inherited_by_execution_review_and_resume() {
    let f = Fixture::new();
    let image = f.root().join("original.png");
    image::RgbImage::from_pixel(12, 8, image::Rgb([255, 0, 0]))
        .save(&image)
        .unwrap();
    let manifest = f.json("inputs.json", &json!({"version":1,"images":[{"path":"original.png","purpose":"reference","source":"synthetic fixture"}]}));
    let tree = f.cli(&["candidate", s(&f.repo)], &[], 0);
    let visual_plan = f.plan("visual.md", "visual", &[], json!([]), json!({}), json!([]));
    let visual = f.cli(
        &[
            "visual",
            s(&f.repo),
            vs(&tree["tree"]),
            s(&visual_plan),
            "--inputs",
            s(&manifest),
        ],
        &[("FAKE_MODE", "visual")],
        0,
    );
    assert_eq!(visual["outcome"], "COMPLETE");
    let inputs = json!({"visual":{"executionId":visual["id"],"inputIds":visual["report"]["inputIds"],"report":true}});
    let probe = f.file("visual-probe.sh", "exit 1\n");
    let plan = f.plan(
        "inherited.md",
        "standard",
        &["*"],
        json!([{"argv":["sh",probe],"timeoutSeconds":2}]),
        inputs,
        json!([]),
    );
    let stopped = f.execute(&plan, &[], 0);
    assert_eq!(stopped["reason"], "environment_preflight_failed");
    let prompt = fs::read(
        f.store()
            .path(vs(&stopped["id"]))
            .unwrap()
            .join("prompt.txt"),
    )
    .unwrap();
    assert!(String::from_utf8_lossy(&prompt).contains("red rectangle"));
    fs::write(&probe, "exit 0\n").unwrap();
    let capture = f.root().join("image-args");
    let e = f.cli(
        &["resume", vs(&stopped["id"])],
        &[("FAKE_CAPTURE", s(&capture)), ("FAKE_TOUCH", "tracked.txt")],
        0,
    );
    assert_eq!(e["images"], visual["images"]);
    assert_eq!(e["image_owner"], visual["id"]);
    assert_eq!(
        fs::read(f.store().path(vs(&e["id"])).unwrap().join("prompt.txt")).unwrap(),
        prompt
    );
    assert!(fs::read_to_string(&capture).unwrap().contains("--image"));
    fs::write(&probe, "exit 1\n").unwrap();
    let d = f.dossier(&e, json!([]));
    let review = f.review(&e, &d, &[], 0);
    assert_eq!(review["reason"], "environment_preflight_failed");
    fs::write(&probe, "exit 0\n").unwrap();
    let resumed = f.cli(
        &["resume", vs(&review["id"])],
        &[("FAKE_MODE", "review")],
        0,
    );
    assert_eq!(resumed["outcome"], "APPROVE");
    for key in [
        "review_binding",
        "execution_id",
        "images",
        "image_owner",
        "visual_report",
        "role_settings",
    ] {
        assert_eq!(resumed[key], review[key], "{key}");
    }
    let snapshot = f
        .store()
        .path(vs(&visual["id"]))
        .unwrap()
        .join("images")
        .join(vs(&visual["images"][0]["id"]));
    assert_eq!(fs::read(&snapshot).unwrap(), fs::read(image).unwrap());
    fs::set_permissions(&snapshot, fs::Permissions::from_mode(0o600)).unwrap();
    fs::write(snapshot, "tampered").unwrap();
    f.point(&e, 2);
}

fn wait_file(path: &Path, child: &mut Child) {
    let start = Instant::now();
    while !path.exists() {
        assert!(
            start.elapsed() < Duration::from_secs(15),
            "missing {}",
            path.display()
        );
        assert!(child.try_wait().unwrap().is_none(), "CLI exited early");
        thread::sleep(Duration::from_millis(30));
    }
}
fn dead(pid: i32) -> bool {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"));
    stat.is_err()
        || stat
            .unwrap()
            .split(") ")
            .nth(1)
            .is_some_and(|s| s.starts_with('Z'))
}
#[test]
fn cancellation_and_worker_death_kill_nested_codex_and_keep_partial_evidence() {
    for kill_worker in [false, true] {
        let f = Fixture::new();
        let plan = f.simple_plan();
        let child_pid = f.root().join("child.pid");
        let codex_pid = f.root().join("codex.pid");
        let worker_pid = f.root().join("worker.pid");
        let mut child = f
            .command(
                &["execute", s(&plan), s(&f.repo)],
                &[
                    ("FAKE_MODE", "nested"),
                    ("FAKE_CHILD", s(&child_pid)),
                    ("FAKE_PID", s(&codex_pid)),
                    ("FAKE_WORKER", s(&worker_pid)),
                ],
            )
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        wait_file(&worker_pid, &mut child);
        let worker: i32 = fs::read_to_string(&worker_pid)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        let target = if kill_worker {
            worker
        } else {
            child.id() as i32
        };
        nix::sys::signal::kill(
            nix::unistd::Pid::from_raw(target),
            if kill_worker {
                nix::sys::signal::Signal::SIGKILL
            } else {
                nix::sys::signal::Signal::SIGTERM
            },
        )
        .unwrap();
        let started = Instant::now();
        while child.try_wait().unwrap().is_none() {
            if started.elapsed() > Duration::from_secs(15) {
                child.kill().unwrap();
                panic!("supervision did not terminate");
            }
            thread::sleep(Duration::from_millis(30));
        }
        let output = child.wait_with_output().unwrap();
        assert_eq!(
            output.status.code(),
            Some(1),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let e: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(e["phase"], "finished");
        assert_eq!(e["outcome"], "INCONCLUSIVE");
        let reason = vs(&e["reason"]);
        assert!(
            if kill_worker {
                reason == "launcher_exit_-9"
            } else {
                reason == "caller_signal"
            },
            "{reason}"
        );
        assert!(
            String::from_utf8_lossy(&fs::read(vs(&e["artifacts"]["events"])).unwrap())
                .contains("partial-evidence")
        );
        assert!(
            String::from_utf8_lossy(&fs::read(vs(&e["artifacts"]["diagnostics"])).unwrap())
                .contains("partial-diagnostic")
        );
        for path in [&codex_pid, &child_pid] {
            let pid = fs::read_to_string(path).unwrap().trim().parse().unwrap();
            assert!(dead(pid), "surviving pid {pid}");
        }
        assert!(e["output_candidate_tree"].is_string());
    }
}

#[test]
fn write_paths_use_python_character_classes() {
    let f = Fixture::new();
    let plan = f.plan(
        "scope.md",
        "standard",
        &["[^a].rs"],
        json!([]),
        json!({}),
        json!([]),
    );
    for (name, outcome, reason) in [
        ("b.rs", "STOPPED", "write_paths_violation"),
        ("a.rs", "COMPLETE", "completed"),
        ("^.rs", "COMPLETE", "completed"),
    ] {
        let e = f.execute(&plan, &[("FAKE_TOUCH", name)], 0);
        assert_eq!(e["outcome"], outcome);
        assert_eq!(e["reason"], reason);
        assert!(Path::new(vs(&e["worktree"])).join(name).is_file());
    }
}

#[test]
fn git_scope_cache_hooks_and_integration_preserve_user_dirt() {
    use codex_improve::git_worktree::*;
    let f = Fixture::new();
    fs::write(f.repo.join(".gitignore"), "cache.bin\ncollision.bin\n").unwrap();
    fs::write(f.repo.join(".worktreeinclude"), "cache.bin\n").unwrap();
    f.git(&["add", "."]);
    f.git(&["commit", "-qm", "test: cache include"]);
    fs::write(f.repo.join("cache.bin"), "cached").unwrap();
    let plan = f.simple_plan();
    let e = f.cli(
        &[
            "execute",
            s(&plan),
            s(&f.repo),
            "--copy-from",
            s(&f.repo),
            "--include",
            "cache.bin",
        ],
        &[],
        0,
    );
    let w = validate_worktree(Path::new(vs(&e["worktree"])), true).unwrap();
    assert_eq!(
        fs::read_to_string(w.path.join("cache.bin")).unwrap(),
        "cached"
    );
    assert_eq!(
        fs::metadata(&w.path).unwrap().permissions().mode() & 0o777,
        0o700
    );
    let source = validate_worktree(&f.repo, false).unwrap();
    assert!(copy_ignored(&source, &w, &["other.bin".into()]).is_err());
    let base = candidate(&w).unwrap().1;
    fs::rename(w.path.join("tracked.txt"), w.path.join("renamed.txt")).unwrap();
    let renamed = candidate(&w).unwrap().1;
    assert!(check_write_paths(&w, &base, &renamed, &["renamed.txt".into()], &[]).is_err());
    check_write_paths(
        &w,
        &base,
        &renamed,
        &["tracked.txt".into(), "renamed.txt".into()],
        &[],
    )
    .unwrap();
    fs::rename(w.path.join("renamed.txt"), w.path.join("tracked.txt")).unwrap();
    fs::set_permissions(
        w.path.join("tracked.txt"),
        fs::Permissions::from_mode(0o755),
    )
    .unwrap();
    assert!(
        check_write_paths(&w, &base, &candidate(&w).unwrap().1, &["other".into()], &[]).is_err()
    );
    fs::write(w.path.join("tracked.txt"), "reviewed").unwrap();
    let tree = candidate(&w).unwrap().1;
    assert!(require_candidate(&w, &tree[..8]).is_err());
    let hook = w.common_dir.join("hooks/pre-commit");
    fs::write(&hook, "#!/bin/sh\nexit 1\n").unwrap();
    fs::set_permissions(&hook, fs::Permissions::from_mode(0o755)).unwrap();
    assert!(checkpoint(&w, &tree, "test: rejected hook").is_err());
    assert_eq!(git(&w.path, &["rev-parse", "HEAD"]).unwrap(), w.head);
    fs::write(
        &hook,
        "#!/bin/sh\nprintf mutated > tracked.txt\ngit add tracked.txt\n",
    )
    .unwrap();
    assert!(checkpoint(&w, &tree, "test: mutated hook").is_err());
    assert_eq!(git(&w.path, &["rev-parse", "HEAD"]).unwrap(), w.head);
    fs::remove_file(hook).unwrap();
    fs::write(w.path.join("tracked.txt"), "reviewed").unwrap();
    fs::write(w.path.join("collision.bin"), "reviewed collision").unwrap();
    f.git_at(&w.path, &["add", "-f", "collision.bin"]);
    let oid = checkpoint(&w, &candidate(&w).unwrap().1, "test: reviewed").unwrap();
    fs::write(f.repo.join("collision.bin"), "local ignored").unwrap();
    assert!(integrate_exact(&f.repo, &oid, &w.head).is_err());
    assert_eq!(f.git(&["rev-parse", "HEAD"]), w.head);
    fs::remove_file(f.repo.join("collision.bin")).unwrap();
    fs::write(f.repo.join("unrelated.txt"), "keep").unwrap();
    let merged = integrate_exact(&f.repo, &oid, &w.head).unwrap();
    assert_eq!(f.git(&["rev-parse", &format!("{merged}^2")]), oid);
    assert_eq!(
        fs::read_to_string(f.repo.join("unrelated.txt")).unwrap(),
        "keep"
    );
    assert!(integrate_exact(&f.repo, &oid, &w.head).is_err());
}

#[test]
fn roles_prompts_readonly_scout_and_failures_use_public_contracts() {
    use codex_improve::contracts::read_roles;
    let f = Fixture::new();
    let roles = read_roles(&f.skill.join("config/roles.json")).unwrap();
    assert_eq!(roles.as_object().unwrap().len(), 7);
    let materials = json!({"writer":{"facts":[{"fact":"Settled fact","source":"tracked.txt:1"}],"conclusions":["Use the fact"],"audience":"contributors","language":"English","terminology":[],"preserve":["meaning"],"scope":["tracked.txt"],"acceptance":["accurate"]}});
    for lane in ["economy", "standard", "deep", "writer"] {
        let plan = f.plan(
            "role.md",
            lane,
            &["*"],
            json!([]),
            if lane == "writer" {
                materials.clone()
            } else {
                json!({})
            },
            json!([]),
        );
        let capture = f.root().join("role-args");
        let prompt = f.root().join("role-prompt");
        let e = f.execute(
            &plan,
            &[("FAKE_CAPTURE", s(&capture)), ("FAKE_PROMPT", s(&prompt))],
            0,
        );
        assert_eq!(e["role_settings"], roles[lane]);
        let args = fs::read_to_string(&capture).unwrap();
        assert!(args.contains(vs(&roles[lane]["model"])));
        assert!(args.contains(&format!("network.enabled={}", roles[lane]["networkAccess"])));
        let prompt = fs::read_to_string(prompt).unwrap();
        assert!(prompt.contains("## The smallest complete change"));
        assert!(!prompt.contains("## 1. Understand first"));
    }
    let plan = f.simple_plan();
    f.cli(&["execute", s(&plan), s(&f.repo), "--lane", "deep"], &[], 2);
    for (mode, reason) in [
        ("corrupt", "invalid_final_output"),
        ("empty", "empty_final_output"),
        ("oversized", "final_output_limit"),
        ("exit124", "codex_exit_124"),
    ] {
        let e = f.execute(&plan, &[("FAKE_MODE", mode)], 1);
        assert_eq!(e["reason"], reason);
    }
    let detached = f.root().join("detached");
    f.git(&["worktree", "add", "-q", "--detach", s(&detached)]);
    for path in [&f.repo, &detached] {
        fs::write(path.join("tracked.txt"), "staged").unwrap();
        f.git_at(path, &["add", "tracked.txt"]);
        fs::write(path.join("tracked.txt"), "unstaged").unwrap();
        fs::write(path.join("new.txt"), "untracked").unwrap();
        let index = PathBuf::from(f.git_at(
            path,
            &["rev-parse", "--path-format=absolute", "--git-path", "index"],
        ));
        let before = fs::read(&index).unwrap();
        let c = f.cli(&["candidate", s(path)], &[], 0);
        let capture = f.root().join("scout-args");
        let e = f.cli(
            &["scout", s(path), vs(&c["tree"]), s(&plan)],
            &[("FAKE_CAPTURE", s(&capture))],
            0,
        );
        assert_eq!(e["outcome"], "COMPLETE");
        assert_eq!(e["role_settings"], roles["scout"]);
        let args = fs::read_to_string(capture).unwrap();
        assert!(args.contains("read-only") && args.contains("network_access=false"));
        assert_eq!(fs::read(index).unwrap(), before);
        assert_eq!(
            fs::read_to_string(path.join("tracked.txt")).unwrap(),
            "unstaged"
        );
        f.point(&e, 2);
        let drifted = f.cli(
            &["scout", s(path), vs(&c["tree"]), s(&plan)],
            &[("FAKE_TOUCH", "drift.txt")],
            0,
        );
        assert_eq!(drifted["reason"], "postrun_candidate_drift");
    }
}

#[test]
fn visual_limits_capture_provenance_and_gate_binding() {
    let f = Fixture::new();
    let image = f.root().join("original.png");
    image::RgbImage::from_pixel(12, 8, image::Rgb([255, 0, 0]))
        .save(&image)
        .unwrap();
    let sha = digest(&fs::read(&image).unwrap());
    let candidate = f.cli(&["candidate", s(&f.repo)], &[], 0);
    let plan = f.plan("visual.md", "visual", &[], json!([]), json!({}), json!([]));
    let entry = json!({"path":"original.png","purpose":"candidate","source":"fixture render"});
    let manifest = f.json("inputs.json", &json!({"version":1,"images":[entry]}));
    let args = [
        "visual",
        s(&f.repo),
        vs(&candidate["tree"]),
        s(&plan),
        "--inputs",
        s(&manifest),
    ];
    let unbound = f.cli(&args, &[("FAKE_MODE", "visual")], 0);
    assert_eq!(unbound["images"][0]["bound"], false);
    for (limits, entries) in [
        (
            json!({"count":1,"perImageBytes":1,"totalBytes":1024}),
            json!([entry]),
        ),
        (
            json!({"count":1,"perImageBytes":1024,"totalBytes":1}),
            json!([entry]),
        ),
        (
            json!({"count":1,"perImageBytes":1024,"totalBytes":2048}),
            json!([entry, entry]),
        ),
    ] {
        f.plan(
            "visual.md",
            "visual",
            &[],
            json!([]),
            json!({"imageLimits":limits}),
            json!([]),
        );
        f.json("inputs.json", &json!({"version":1,"images":entries}));
        f.cli(&args, &[], 2);
    }
    f.plan("visual.md", "visual", &[], json!([]), json!({}), json!([]));
    let log = format!(
        "fixture render\n{}\n{}\n{sha}\n",
        candidate["head"], candidate["tree"]
    );
    f.file("invocation.log", &log);
    let capture = f.json("capture.json", &json!({"command":"fixture render","head":candidate["head"],"tree":candidate["tree"],"scenario":"fixture","viewport":[12,8],"output":{"path":"original.png","sha256":sha},"invocation":{"path":"invocation.log","sha256":digest(log.as_bytes())}}));
    let mut bound_entry = entry.clone();
    bound_entry["capture"] = json!({"record":"capture.json","sha256":digest(&fs::read(&capture).unwrap()),"verifiedBy":"test fixture"});
    f.json("inputs.json", &json!({"version":1,"images":[bound_entry]}));
    let visual = f.cli(&args, &[("FAKE_MODE", "visual")], 0);
    assert_eq!(visual["images"][0]["bound"], true);
    let gate = json!({"id":"G1","class":"implementation gate","kind":"check","check":"visual inspection","invalidatedBy":["**"],"environment":"fixture","conditions":"bound original"});
    let gated = f.plan(
        "gated.md",
        "standard",
        &["*"],
        json!([]),
        json!({}),
        json!([gate]),
    );
    let e = f.execute(&gated, &[], 0);
    let item = |v: &Value| json!({"gate":"G1","status":"PASS","artifact":{"path":v["artifacts"]["final"],"sha256":v["final_hash"]},"environment":"fixture","head":e["output_head"],"tree":e["output_candidate_tree"],"planHash":e["plan_hash"],"visualExecutionId":v["id"]});
    f.review(&e, &f.dossier(&e, json!([item(&unbound)])), &[], 2);
    let d = f.dossier(&e, json!([item(&visual)]));
    let mut report = review_report();
    report["coverage"]
        .as_array_mut()
        .unwrap()
        .push(json!({"check":"G1","status":"PASS","evidence":"bound original"}));
    let report = f.json("report.json", &report);
    let review = f.review(&e, &d, &[("FAKE_REPORT", s(&report))], 0);
    assert_eq!(review["outcome"], "APPROVE");
    let location = f.store().path(vs(&visual["id"])).unwrap().join("images");
    let provenance = location.join(format!("{}.invocation", vs(&visual["images"][0]["id"])));
    fs::set_permissions(&provenance, fs::Permissions::from_mode(0o600)).unwrap();
    fs::write(provenance, "tampered").unwrap();
    f.point(&e, 2);
}

#[test]
fn integration_requires_execution_checkpoint_and_exact_target_review() {
    let f = Fixture::new();
    let e = f.execute(&f.simple_plan(), &[("FAKE_TOUCH", "tracked.txt")], 0);
    let d = f.dossier(&e, json!([]));
    f.review(&e, &d, &[], 0);
    let point = f.point(&e, 0);
    let head = f.git(&["rev-parse", "HEAD"]);
    let args = [
        "checkpoint",
        vs(&e["id"]),
        "--integrate-oid",
        vs(&point["checkpoint_oid"]),
        "--target",
        s(&f.repo),
        "--expected-target",
        &head,
    ];
    f.cli(&args, &[], 2);
    let current = f.load(&e);
    let d = f.dossier(&current, json!([]));
    let mut dossier: Value = serde_json::from_slice(&fs::read(&d).unwrap()).unwrap();
    dossier["target"] =
        json!({"worktree":f.repo,"head":head,"mergeTree":e["output_candidate_tree"]});
    f.json("review.json", &dossier);
    f.review(&current, &d, &[], 0);
    f.git(&["commit", "--allow-empty", "-qm", "test: target moved"]);
    f.cli(&args, &[], 2);
    let new_head = f.git(&["rev-parse", "HEAD"]);
    dossier["target"]["head"] = new_head.clone().into();
    f.json("review.json", &dossier);
    f.review(&current, &d, &[], 0);
    let integrated = f.cli(
        &[
            "checkpoint",
            vs(&e["id"]),
            "--integrate-oid",
            vs(&point["checkpoint_oid"]),
            "--target",
            s(&f.repo),
            "--expected-target",
            &new_head,
        ],
        &[],
        0,
    );
    assert_eq!(
        f.git(&[
            "rev-parse",
            &format!("{}^{{tree}}", vs(&integrated["integrated_oid"]))
        ]),
        e["output_candidate_tree"]
    );
}
