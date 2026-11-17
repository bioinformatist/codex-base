"""Exercise the installed connected client without Python/Cargo/Nix in its PATH."""
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import tempfile

prefix, skill, fixture = map(Path, sys.argv[1:])
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    env = {**os.environ, 'HOME': str(root / 'home'), 'XDG_STATE_HOME': str(root / 'state'),
           'PATH': os.environ['PORTABLE_CHILD_PATH'], 'CODEX_IMPROVE_SKILL_ROOT': str(skill),
           'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
    for name in ('python3', 'cargo', 'nix'):
        assert subprocess.run(['sh', '-c', f'command -v {name}'], env=env, capture_output=True).returncode != 0
    fake = root / 'codex'
    fake.write_text(f'#!/bin/sh\nexec {shlex.quote(sys.executable)} {shlex.quote(str(fixture))} "$@"\n')
    fake.chmod(0o755)
    env['CODEX_IMPROVE_CODEX'] = str(fake)
    repo = root / 'repo'
    repo.mkdir()
    for args in [('init', '-q'), ('config', 'user.name', 'Fixture'),
                 ('config', 'user.email', 'fixture@example.invalid')]:
        subprocess.check_call(['git', '-C', str(repo), *args], env=env)
    (repo / 'tracked').write_text('base')
    subprocess.check_call(['git', '-C', str(repo), 'add', '.'], env=env)
    subprocess.check_call(['git', '-C', str(repo), 'commit', '-qm', 'test: base'], env=env)
    plan = root / 'plan.md'
    plan.write_text('- **Improve contract**: `1.0.0-codex.20`\n' + ''.join(
        f'```json codex-improve-{kind}\n{json.dumps(value)}\n```\n' for kind, value in (
            ('environment', {'version': 1, 'launcher': ['env'], 'probes': []}),
            ('routing', {'version': 1, 'lane': 'standard', 'writePaths': ['tracked'], 'requiredEvidence': []}),
            ('gates', {'version': 1, 'gates': []}))))
    cli = prefix / 'bin/codex-improve'
    proc = subprocess.Popen([str(cli), 'session', str(plan), str(repo)], env=env,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def until(key, value=None):
        for line in proc.stdout:
            item = json.loads(line)
            if key in item and (value is None or item[key] == value):
                return item
        raise AssertionError((key, proc.wait(), proc.stderr.read()))

    def op(name):
        proc.stdin.write(json.dumps({'op': name}) + '\n')
        proc.stdin.flush()

    task = until('ready')['ready']
    assert task['contract'] == '1.0.0-codex.20'
    op('turn')
    assert until('finished', 'implementation')['outcome'] == 'COMPLETE'
    assert Path(task['worktree'], 'tracked').read_text() == 'native change'
    op('capture')
    assert until('op', 'capture')['result']['tree']
    op('close')
    until('op', 'close')
    assert proc.wait(timeout=10) == 0, proc.stderr.read()
    summary = json.loads(subprocess.check_output([str(cli), 'inspect', task['id']], env=env))
    assert summary['phase'] == 'closed'
    managed, target = root / 'managed.toml', root / 'config.toml'
    managed.write_text("model = 'new'\n")
    target.write_text("model = 'old' # keep comment\nuser = 'keep'\n")
    subprocess.check_call([str(prefix / 'bin/merge-codex-base-config'), str(managed), str(target)], env=env)
    assert '# keep comment' in target.read_text() and "user = 'keep'" in target.read_text()
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
print('installed .20 connected client and config merge passed without Python/Cargo/Nix in child PATH')
