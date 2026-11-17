"""Exercise .20 through its public connected interface; no real models or accounts."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary, skill = map(Path, sys.argv[1:3])
fixture = Path(__file__).with_name('native_fixture.py')
with tempfile.TemporaryDirectory(prefix='improve-connected-') as temp:
    root = Path(temp)
    env = {**os.environ, 'HOME': str(root / 'home'), 'XDG_STATE_HOME': str(root / 'state'),
           'CODEX_IMPROVE_SKILL_ROOT': str(skill), 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
    repo = root / 'repo'
    repo.mkdir()

    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args], env=env, text=True).strip()

    git('init', '-q')
    git('config', 'user.name', 'Fixture')
    git('config', 'user.email', 'fixture@example.invalid')
    (repo / 'tracked').write_text('base')
    git('add', '.')
    git('commit', '-qm', 'test: base')
    fake = root / 'codex'
    # The fixture interpreter is explicit; runtime children do not need Python on PATH.
    import shlex
    fake.write_text(f'#!/bin/sh\nexec {shlex.quote(sys.executable)} {shlex.quote(str(fixture))} "$@"\n')
    fake.chmod(0o755)
    env['CODEX_IMPROVE_CODEX'] = str(fake)
    gate = {'id': 'G1', 'class': 'implementation gate', 'kind': 'check', 'check': 'fixture check',
            'invalidatedBy': ['tracked'], 'environment': 'fixture', 'conditions': 'current behavior'}
    plan = root / 'plan.md'
    plan.write_text('- **Improve contract**: `1.0.0-codex.20`\n' + ''.join(
        f'```json codex-improve-{name}\n{json.dumps(value)}\n```\n' for name, value in (
            ('environment', {'version': 1, 'launcher': ['env'], 'probes': []}),
            ('routing', {'version': 1, 'lane': 'deep', 'writePaths': ['tracked'], 'requiredEvidence': ['G1'],
                         'reviewTools': {'docs': ['read']}}), ('gates', {'version': 1, 'gates': [gate]}))))

    def launch(case):
        log = root / f'{case}.jsonl'
        proc = subprocess.Popen([str(binary), 'session', str(plan), str(repo)],
                                env={**env, 'NATIVE_FIXTURE_CASE': case, 'NATIVE_FIXTURE_LOG': str(log)},
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def until(key, value=None):
            for line in proc.stdout:
                item = json.loads(line)
                if key in item and (value is None or item[key] == value):
                    return item
            raise AssertionError((case, key, proc.wait(), proc.stderr.read()))
        def op(name, **fields):
            proc.stdin.write(json.dumps({'op': name, **fields}) + '\n')
            proc.stdin.flush()
        return proc, log, op, until

    for case in ('writers', 'revise', 'block', 'invalid', 'budget', 'timeout', 'cancelled',
                 'write-tool', 'extra-tool', 'hold', 'lost', 'lost-during-review', 'unloaded',
                 'unconfirmed', 'wrong-model', 'wrong-effort'):
        proc, log, op, until = launch(case)
        if case in ('wrong-model', 'wrong-effort'):
            assert 'native model, effort' in until('stopped')['stopped']['stoppedBecause']
            assert proc.wait(timeout=10) == 2
            continue
        task = until('ready')['ready']
        assert task['implementation']['model'] == 'gpt-6.1-sol'
        assert task['implementation']['effort'] == 'xhigh'
        assert task['implementation']['sessionId'] == 'root-0'
        assert task['implementation']['budget'] == {'limit': 300000, 'reminders': [150000, 75000, 30000]}
        op('turn')
        if case == 'unloaded':
            assert 'loaded' in until('stopped')['stopped']['stoppedBecause']
            assert proc.wait(timeout=10) == 2
            continue
        if case == 'hold':
            until('op', 'turn')
            op('cancel', target='implementation')
            assert until('op', 'cancel')['result']['confirmed']
            op('close')
            until('op', 'close')
            assert proc.wait(timeout=10) == 0
            continue
        assert until('finished', 'implementation')['outcome'] == 'COMPLETE'
        op('capture')
        if case in ('lost', 'unconfirmed'):
            reason = until('stopped')['stopped']['stoppedBecause']
            assert ('loaded task root lost' if case == 'lost' else 'termination was not confirmed') in reason
            assert proc.wait(timeout=10) == 2
            continue
        candidate = until('op', 'capture')['result']
        if case == 'writers':
            image = root / 'reference.png'
            image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
            manifest = root / 'images.json'
            manifest.write_text(json.dumps({'version': 1, 'images': [
                {'path': image.name, 'purpose': 'reference', 'source': 'private fixture original'}]}))
            op('images', manifest=str(manifest))
            snapshots = until('op', 'images')['result']
            snapshot = root / 'state/codex-improve-v20/tasks' / task['id'] / 'images' / snapshots[0]['id']
            assert snapshot.read_bytes() == image.read_bytes() and snapshot.stat().st_mode & 0o777 == 0o400
        artifact = root / f'{case}.evidence'
        artifact.write_text('current deterministic fixture passed')
        dossier = root / f'{case}.review.json'
        dossier.write_text(json.dumps({'version': 1, 'taskId': task['id'], **{k: candidate[k] for k in ('head', 'tree')},
                                      'evidence': [{'gate': 'G1', 'status': 'PASS',
                                                    'artifact': {'path': str(artifact), 'sha256': hashlib.sha256(artifact.read_bytes()).hexdigest()},
                                                    'environment': 'fixture', 'head': candidate['head'], 'tree': candidate['tree'],
                                                    'planHash': task['plan_hash']}], 'notes': 'independently inspect'}))
        op('review', tree=candidate['tree'], dossier=str(dossier))
        if case in ('write-tool', 'extra-tool'):
            assert 'writable external tool' in until('stopped')['stopped']['stoppedBecause']
            assert proc.wait(timeout=10) == 2
            continue
        if case == 'lost-during-review':
            stopped = until('stopped')['stopped']
            assert 'loaded task root lost' in stopped['stoppedBecause'] and stopped['approval'] is None
            assert proc.wait(timeout=10) == 2
            continue
        result = until('finished', 'review')
        assert result['outcome'] == {'writers': 'APPROVE', 'revise': 'REVISE', 'block': 'BLOCK',
                                     'invalid': 'invalid_output', 'budget': 'budget_exhausted',
                                     'timeout': 'timed_out', 'cancelled': 'cancelled'}[case], result
        if case != 'writers':
            op('status')
            assert until('op', 'status')['result']['approval'] is None
        if case == 'writers':
            op('status')
            status = until('op', 'status')['result']
            assert status['approval'] == status['review']['id']
            assert status['review']['native']['budget']['limit'] == 100000
            # A continuation uses the still-loaded implementation root and invalidates approval.
            op('turn', prompt='Apply the requested in-scope revision.')
            until('finished', 'implementation')
            op('status')
            assert until('op', 'status')['result']['approval'] is None
        op('close')
        until('op', 'close')
        assert proc.wait(timeout=10) == 0, proc.stderr.read()
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        starts = [c['params'] for c in calls if c.get('method') == 'thread/start']
        assert len(starts) == 2
        assert starts[1]['sandbox'] == 'read-only'
        assert starts[1]['config']['features.apps'] is False
        assert starts[1]['config']['features.plugins'] is False
        assert starts[1]['config']['mcp_servers.write.enabled'] is False
        assert starts[1]['config']['mcp_servers.docs.enabled_tools'] == ['read']
        assert all('resume' not in c.get('method', '') and 'fork' not in c.get('method', '') for c in calls)
        if case == 'writers':
            assert any(c.get('method') == 'turn/interrupt' and c['params']['threadId'] == 'child-a' for c in calls)
            assert {c['params']['processId'] for c in calls if c.get('method') == 'thread/backgroundTerminals/terminate'} == {'101', '102'}
            assert any(c.get('method') == 'thread/list' and c['params'].get('cursor') for c in calls)
            assert any(c.get('method') == 'thread/turns/list' and c['params'].get('cursor') for c in calls)
            role_paths = [v for k, v in starts[0]['config'].items() if k in ('agents.writer.config_file', 'agents.visual.config_file')]
            assert len(role_paths) == 2
            for role in role_paths:
                text = Path(role).read_text()
                assert '"gpt-6-astra"' in text and '"xhigh"' in text
    print('connected .20 fixtures passed: paged freeze, runtime continuity, separate review, verdicts, native failure mapping, cancellation and tool permissions')
