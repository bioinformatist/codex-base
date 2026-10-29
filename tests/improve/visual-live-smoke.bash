#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
python3 -B - "$repo" "$@" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

repo = Path(sys.argv[1])
cli = repo / "src/improve/scripts/codex-improve"
assert sys.argv[2:] in ([], ["--offline"]), "usage: visual-live-smoke.bash [--offline]"
offline = sys.argv[2:] == ["--offline"]
real = shutil.which("codex")
version = re.search(r'codexVersion = "([^"]+)"', (repo / "nix/packages.nix").read_text())[1]
assert real and subprocess.check_output([real, "--version"], text=True).strip() == f"codex-cli {version}"
parent = Path(os.environ.get("XDG_CACHE_HOME", tempfile.gettempdir())) / "improve-visual-live"
parent.mkdir(parents=True, exist_ok=True, mode=0o700)
root = Path(tempfile.mkdtemp(dir=parent))
print(f"VISUAL_LIVE_EVIDENCE={root}", flush=True)
os.umask(0o077)

# Record the actual invocation without replacing the native CLI or its authentication.
proxy = root / "codex"
proxy.write_text(f"#!{sys.executable}\n" + '''\
import hashlib, json, os, pathlib, subprocess, sys
args = sys.argv[1:]
location = pathlib.Path(os.environ['SMOKE_EVIDENCE']) / os.environ['IMPROVE_EXECUTION_ID']
location.mkdir(mode=0o700)
prompt = sys.stdin.buffer.read()
(location / 'prompt.txt').write_bytes(prompt)
images = [pathlib.Path(args[i+1]) for i, arg in enumerate(args) if arg == '--image']
(location / 'invocation.json').write_text(json.dumps({'argv':args, 'images':[
    {'path':str(p), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in images]}))
mode = os.environ['SMOKE_MODE']
if mode == 'execute' or os.environ['SMOKE_OFFLINE'] == '1':
    ids = [p.name for p in images]
    report = {'status':'COMPLETE','steps':['No-op transport fixture'],'stoppedBecause':None,'filesChanged':[],'notes':[]}
    if mode == 'visual':
        report = {'status':'COMPLETE','inputIds':ids,'observations':[{'inputId':i,'location':'whole frame',
            'observation':'red rectangle','inference':'none','comparison':'none','uncertainty':'none'} for i in ids],
            'unchecked':[],'stoppedBecause':None}
    elif mode == 'review':
        report = {'verdict':'APPROVE','summary':'Transport fixture checked','findings':[],
            'coverage':[{'check':'scope','status':'PASS','evidence':'fixture'}],'review_blockers':[],'deferred_acceptance':[]}
    pathlib.Path(args[args.index('--output-last-message')+1]).write_text(json.dumps(report))
    print(json.dumps({'type':'turn.completed','usage':{'input_tokens':1,'cached_input_tokens':0,'output_tokens':1}}))
else:
    sys.exit(subprocess.run([os.environ['SMOKE_REAL_CODEX'], *args], input=prompt).returncode)
''')
proxy.chmod(0o700)
os.environ.update(CODEX_IMPROVE_CODEX=str(proxy), SMOKE_REAL_CODEX=real,
                  SMOKE_EVIDENCE=str(root), SMOKE_OFFLINE=str(int(offline)),
                  XDG_STATE_HOME=str(root / "state"),
                  GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
if offline:
    os.environ.update(HOME=str(root / "home"), XDG_CONFIG_HOME=str(root / "config"))
fixture = root / "repo"
subprocess.run(["git", "init", "-q", str(fixture)], check=True)
(fixture / "README.md").write_text("Synthetic image transport fixture. No product change.\n")
subprocess.run(["git", "-C", str(fixture), "add", "README.md"], check=True)
subprocess.run(["git", "-C", str(fixture), "-c", "user.name=Fixture", "-c",
                "user.email=fixture@example.invalid", "commit", "-qm", "test: add visual fixture"], check=True)
image = Image.new("RGB", (256, 192), "white")
ImageDraw.Draw(image).rectangle((48, 56, 208, 136), fill=(255, 0, 0))
image.save(root / "original.png")
manifest = root / "inputs.json"
manifest.write_text(json.dumps({"version":1,"images":[{
    "path":"original.png","purpose":"reference","source":"locally generated synthetic image"}]}))

def plan(lane, inputs):
    return ("- **Improve contract**: `1.0.0-codex.19`\n"
        "```json codex-improve-environment\n" + json.dumps({"version":1,"launcher":["env"],"probes":[]}) +
        "\n```\n```json codex-improve-routing\n" + json.dumps({"version":1,"lane":lane,
        "writePaths":["README.md"] if lane == "standard" else [],"requiredEvidence":[],"inputs":inputs}) +
        "\n```\n```json codex-improve-gates\n{\"version\":1,\"gates\":[]}\n```\n"
        "Inspect the attached image. Describe the dominant foreground object's color and shape.\n").encode()

def invoke(name, *args):
    result = subprocess.run([str(cli), *map(str, args)], capture_output=True,
                            env={**os.environ, "SMOKE_MODE":name})
    (root / f"{name}.json").write_bytes(result.stdout)
    (root / f"{name}.stderr").write_bytes(result.stderr)
    (root / f"{name}.exit").write_text(str(result.returncode))
    assert result.returncode == 0, f"{name} failed ({result.returncode}); see {root}"
    return json.loads(result.stdout)

visual_plan = root / "visual.md"
visual_plan.write_bytes(plan("visual", {}))
tree = invoke("candidate", "candidate", fixture)["tree"]
visual = invoke("visual", "visual", fixture, tree, visual_plan, "--inputs", manifest)
assert visual["outcome"] == "COMPLETE", f"visual incomplete; see {root}"
facts = " ".join(item["observation"] for item in visual["report"]["observations"]).lower()
assert "red" in facts and re.search(r"rectang", facts), f"pixel observation mismatch; see {root}"

# A no-op execution exercises the public CLI without an executor model call.
execution_plan = root / "execute.md"
execution_plan.write_bytes(plan("standard", {"visual":{"executionId":visual["id"],
    "inputIds":visual["report"]["inputIds"],"report":True}}))
record = invoke("execute", "execute", execution_plan, fixture)
assert record["outcome"] == "COMPLETE"
head, tree = record["output_head"], record["output_candidate_tree"]
dossier = root / "review.json"
dossier.write_text(json.dumps({"version":1,"executionId":record["id"],"head":head,"tree":tree,
    "evidence":[],"notes":"Review this synthetic transport fixture, original image and normal visual report; scope is the only coverage ID."}))
review = invoke("review", "review", record["id"], tree, dossier)
assert review["outcome"] == "APPROVE", f"review did not approve; see {root}"
expected_digest = hashlib.sha256((root / "original.png").read_bytes()).hexdigest()
roles = json.loads((repo / "src/improve/config/roles.json").read_text())
for result, role in ((visual, "visual"), (review, "reviewer")):
    model = roles[role]["model"]
    invocation = json.loads((root / result["id"] / "invocation.json").read_text())
    args = invocation["argv"]
    assert args[args.index("--model")+1] == model
    assert [entry["sha256"] for entry in invocation["images"]] == [expected_digest]
    assert result["images"] == visual["images"]
prompt = (root / review["id"] / "prompt.txt").read_text()
assert json.JSONDecoder().raw_decode(prompt.split("\nVisual report:\n")[1])[0] == visual["report"], "visual report missing from actual reviewer input"
(root / "passed.json").write_text(json.dumps({"cliVersion":version, "offline":offline, "visual":visual["id"],
    "review":review["id"], "models":[visual["role_settings"],review["role_settings"]],
    "imageSha256":expected_digest, "visualReportSha256":visual["final_hash"],
    "sameOriginals":True,"reviewReceivedVisualReport":True}))
print(f"visual transport smoke passed (offline={offline}); evidence: {root}")
PY
