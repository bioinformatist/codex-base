"""Archive installation smoke; current behavior coverage lives in the Rust workspace."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import base64

prefix, skill = map(Path, sys.argv[1:])
cli = prefix / 'bin/codex-improve'
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    env = {**os.environ, 'HOME': str(root / 'home'), 'XDG_CONFIG_HOME': str(root / 'config'),
           'XDG_STATE_HOME': str(root / 'state'), 'PATH': os.environ['PORTABLE_CHILD_PATH'],
           'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
    for name in ('python3', 'cargo', 'nix'):
        assert not (Path(env['PATH']) / name).exists()
    fake = root / 'fake-codex'
    fake.write_text('''#!/bin/sh
cat >/dev/null
final= image=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message) final=$2; shift ;;
    --image) image=$(basename "$2"); shift ;;
  esac
  shift
done
printf '%s\\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1}}'
case "${SMOKE_MODE-execute}" in
  review) printf '%s\\n' '{"verdict":"APPROVE","summary":"Checked","findings":[],"coverage":[{"check":"scope","status":"PASS","evidence":"fixture"}],"review_blockers":[],"deferred_acceptance":[]}' > "$final" ;;
  visual) printf '{"status":"COMPLETE","inputIds":["%s"],"observations":[{"inputId":"%s","location":"whole","observation":"pixel","inference":"none","comparison":"none","uncertainty":"none"}],"unchecked":[],"stoppedBecause":null}' "$image" "$image" > "$final" ;;
  *) printf change > tracked; printf '%s\\n' '{"status":"COMPLETE","steps":["changed"],"stoppedBecause":null,"filesChanged":["tracked"],"notes":[]}' > "$final" ;;
esac
''')
    fake.chmod(0o755)
    env['CODEX_IMPROVE_CODEX'] = str(fake)

    def run(*args, code=0, **extra):
        p = subprocess.run([str(cli), *map(str, args)], cwd=root,
                           env={**env, **extra}, capture_output=True, text=True)
        assert p.returncode == code, (args, p.stdout, p.stderr)
        return json.loads(p.stdout) if code == 0 else p.stderr

    repo = root / 'repo'
    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args], env=env, text=True).strip()
    repo.mkdir()
    git('init', '-q')
    git('config', 'user.name', 'Fixture')
    git('config', 'user.email', 'fixture@example.invalid')
    (repo / 'tracked').write_text('base')
    git('add', '.')
    git('commit', '-qm', 'test: base')

    def plan(name, lane='standard', inputs=None):
        p = root / name
        p.write_text('- **Improve contract**: `1.0.0-codex.19`\n' + ''.join(
            f'```json codex-improve-{kind}\n{json.dumps(value)}\n```\n' for kind, value in (
                ('environment', {'version': 1, 'launcher': ['env'], 'probes': []}),
                ('routing', {'version': 1, 'lane': lane, 'writePaths': ['*'] if lane == 'standard' else [],
                             'requiredEvidence': [], 'inputs': inputs or {}}),
                ('gates', {'version': 1, 'gates': []}))))
        return p

    p = plan('plan.md')
    old = root / 'state/codex-improve-v18/sentinel'
    old.parent.mkdir(parents=True)
    old.write_text('untouched')
    p.write_text(p.read_text().replace('codex.19', 'codex.18'))
    assert 'contract' in run('execute', p, repo, code=2)
    p = plan('plan.md')
    # A static original is passed through decoding and snapshotted byte-for-byte.
    image = root / 'original.png'
    image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
    manifest = root / 'inputs.json'
    manifest.write_text(json.dumps({'version': 1, 'images': [{'path': image.name, 'purpose': 'reference', 'source': 'fixture'}]}))
    tree = run('candidate', repo)['tree']
    v = run('visual', repo, tree, plan('visual.md', 'visual'), '--inputs', manifest, SMOKE_MODE='visual')
    assert v['outcome'] == 'COMPLETE'
    snapshot = Path(v['artifacts']['final']).parent / 'images' / v['images'][0]['id']
    assert snapshot.read_bytes() == image.read_bytes()
    assert stat.S_IMODE(snapshot.stat().st_mode) == 0o400
    p = plan('plan.md', inputs={'visual': {'executionId': v['id'], 'inputIds': v['report']['inputIds'], 'report': True}})
    e = run('execute', p, repo)
    assert e['outcome'] == 'COMPLETE'
    assert run('status', e['id'])['report'] == e['report']
    dossier = root / 'review.json'
    dossier.write_text(json.dumps({'version': 1, 'executionId': e['id'], 'head': e['output_head'],
                                  'tree': e['output_candidate_tree'], 'evidence': [], 'notes': 'inspect'}))
    r = run('review', e['id'], e['output_candidate_tree'], dossier, SMOKE_MODE='review')
    assert r['outcome'] == 'APPROVE'
    point = run('checkpoint', e['id'], e['output_candidate_tree'], '--message', 'test: reviewed')
    n = run('next', e['id'], point['checkpoint_oid'], p)
    assert n['base_head'] == point['checkpoint_oid'] and n['worktree'] != e['worktree']
    assert old.read_text() == 'untouched'
    managed, target = root / 'managed.toml', root / 'config.toml'
    managed.write_text("model = 'new'\n")
    target.write_text("model = 'old' # keep comment\nuser = 'keep'\n")
    subprocess.check_call([str(prefix / 'bin/merge-codex-base-config'), str(managed), str(target)], env=env)
    assert '# keep comment' in target.read_text() and "user = 'keep'" in target.read_text()
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
print('extracted native lifecycle, originals, version rejection and config merge passed without Python/Cargo/Nix in child PATH')
