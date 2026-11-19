"""Exercise .20 through its public connected interface; no real models or accounts."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib

from jsonschema import Draft7Validator

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
    gates = [{'id': f'G{i}', 'class': 'implementation gate', 'kind': 'check', 'check': 'fixture check',
              'invalidatedBy': ['tracked'], 'environment': 'fixture', 'conditions': 'current behavior'}
             for i in range(1, 6)]
    plan = root / 'plan.md'

    def launch(case):
        deferred = [{**gates[0], 'id': 'D-CI', 'class': 'deferred acceptance'}] if case == 'deferred' else []
        plan.write_text('- **Improve contract**: `1.0.0-codex.20`\n' + ''.join(
            f'```json codex-improve-{name}\n{json.dumps(value)}\n```\n' for name, value in (
                ('environment', {'version': 1, 'launcher': ['env'], 'probes': []}),
                ('routing', {'version': 1, 'lane': 'deep', 'writePaths': ['tracked'],
                             'requiredEvidence': [g['id'] for g in gates], 'reviewTools': {'docs': ['read']}}),
                ('gates', {'version': 1, 'gates': [*gates, *deferred]}))))
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

    def inspect(task):
        return json.loads(subprocess.check_output([str(binary), 'inspect', task['id']], env=env))

    def write_dossier(case, task, candidate, notes):
        artifact = root / f'{case}.evidence'
        artifact.write_text('current deterministic fixture passed')
        dossier = root / f'{case}.review.json'
        dossier.write_text(json.dumps({'version': 1, 'taskId': task['id'], **{k: candidate[k] for k in ('head', 'tree')},
                                      'evidence': [{'gate': gate['id'], 'status': 'PASS',
                                                    'artifact': {'path': str(artifact), 'sha256': hashlib.sha256(artifact.read_bytes()).hexdigest()},
                                                    'environment': 'fixture', 'head': candidate['head'], 'tree': candidate['tree'],
                                                    'planHash': task['plan_hash']} for gate in gates], 'notes': notes}))
        return dossier

    for case in ('writers', 'revise', 'block', 'invalid', 'budget', 'timeout', 'cancelled',
                 'write-tool', 'extra-tool', 'hold', 'lost', 'lost-during-review', 'unloaded',
                 'unconfirmed', 'wrong-model', 'wrong-effort', 'deferred', 'failed-empty',
                 'failed-report', 'disconnect-review', 'disconnect-start-review', 'disconnect-start-implementation',
                 'cancel-review', 'implementation-budget',
                 'interrupted-no-evidence', 'executor-stopped', 'invalid-implementation', 'review-running'):
        proc, log, op, until = launch(case)
        if case in ('wrong-model', 'wrong-effort'):
            assert 'native model, effort' in until('stopped')['stopped']['stoppedBecause']
            assert proc.wait(timeout=10) == 2
            continue
        task = until('ready')['ready']
        assert task['implementation']['model'] == 'gpt-6.2-sol'
        assert task['implementation']['effort'] == 'xhigh'
        assert task['implementation']['sessionId'] == 'root-0'
        assert task['implementation']['budget'] == {'limit': 300000, 'reminders': [150000, 75000, 30000]}
        op('turn')
        if case == 'unloaded':
            stopped = until('stopped')['stopped']
            assert 'loaded' in stopped['stoppedBecause']
            assert stopped['report']['status'] == 'COMPLETE' and stopped['nativeStatus'] == 'completed'
            assert inspect(task)['rawReport'] == stopped['rawReport']
            assert proc.wait(timeout=10) == 2
            continue
        if case in ('hold', 'review-running'):
            until('op', 'turn')
            if case == 'review-running':
                op('review', tree='unused', dossier='unused')
                stopped = until('stopped')['stopped']
                assert 'review requires COMPLETE' in stopped['stoppedBecause']
                assert stopped['nativeStatus'] == 'unknown' and stopped['finalUsage'] is None
                assert proc.wait(timeout=10) == 2
                continue
            op('cancel', target='implementation')
            assert until('op', 'cancel')['result']['confirmed']
            op('status')
            status = until('op', 'status')['result']
            assert status['outcome'] == 'cancelled' and status['nativeStatus'] == 'interrupted'
            assert status['report'] is None and status['approval'] is None
            assert inspect(task)['outcome'] == 'cancelled'
            op('close')
            until('op', 'close')
            assert proc.wait(timeout=10) == 0
            continue
        implementation = until('finished', 'implementation')
        assert implementation['outcome'] == {'implementation-budget': 'budget_exhausted',
                                             'interrupted-no-evidence': 'budget_exhausted',
                                             'executor-stopped': 'STOPPED',
                                             'invalid-implementation': 'invalid_output'}.get(case, 'COMPLETE')
        if case == 'disconnect-start-implementation':
            op('turn', prompt='Apply the requested in-scope revision.')
            stopped = until('stopped')['stopped']
            assert 'App Server connection lost' in stopped['stoppedBecause'] and stopped['approval'] is None
            assert stopped['outcome'] == 'unknown' and stopped['nativeStatus'] == 'unknown'
            assert stopped['lastNativeStatus'] == 'inProgress' and stopped['finalUsage'] is None
            assert stopped['turnId'] == 'turn-1' and stopped['threadId'] == task['implementation']['threadId']
            assert stopped['report']['status'] == 'COMPLETE' and stopped['report']['notes'] == ['pending submission report']
            assert json.loads(stopped['rawReport']) == stopped['report'] and stopped['reportError'] is None
            assert stopped['lastUsage']['total']['totalTokens'] == 12
            assert inspect(task) == stopped
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            assert calls[-1]['method'] == 'turn/start'
            assert proc.wait(timeout=10) == 2
            continue
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
        dossier = write_dossier(case, task, candidate,
                                '1. Verified facts and sources: fixture artifact.\n'
                                '2. Questions for independent judgment: inspect connected callers.\n'
                                '3. Candidate or input changes: initial candidate.')
        if case == 'interrupted-no-evidence':
            incomplete = json.loads(dossier.read_text())
            incomplete['evidence'].pop(0)
            dossier.write_text(json.dumps(incomplete))
        op('review', tree=candidate['tree'], dossier=str(dossier))
        if case in ('executor-stopped', 'invalid-implementation', 'interrupted-no-evidence'):
            stopped = until('stopped')['stopped']
            expected = 'missing required gate evidence' if case == 'interrupted-no-evidence' else 'review requires COMPLETE'
            assert expected in stopped['stoppedBecause'] and stopped['approval'] is None
            assert stopped['nativeStatus'] == implementation['nativeStatus']
            if case == 'invalid-implementation':
                assert stopped['report'] is None and stopped['reportError'] and stopped['rawReport'] == 'invalid final'
            assert proc.wait(timeout=10) == 2
            continue
        if case in ('write-tool', 'extra-tool'):
            assert 'writable external tool' in until('stopped')['stopped']['stoppedBecause']
            assert proc.wait(timeout=10) == 2
            continue
        if case in ('lost-during-review', 'disconnect-review', 'disconnect-start-review'):
            stopped = until('stopped')['stopped']
            reason = 'loaded task root lost' if case == 'lost-during-review' else 'App Server connection lost'
            assert reason in stopped['stoppedBecause'] and stopped['approval'] is None
            assert stopped['outcome'] == 'COMPLETE'
            review = stopped['review']
            assert review['outcome'] == 'unknown' and review['report']['verdict'] == 'APPROVE'
            assert json.loads(review['rawReport']) == review['report']
            assert review['binding']['tree'] == candidate['tree']
            assert review['turnId'] == 'turn-0' and review['threadId'] == review['native']['threadId']
            if case in ('disconnect-review', 'disconnect-start-review'):
                assert review['nativeStatus'] == 'unknown' and review['lastNativeStatus'] == 'inProgress'
                assert review['lastUsage']['total']['totalTokens'] == 12 and review['finalUsage'] is None
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                assert calls[-1]['method'] == 'turn/start'
            assert inspect(task) == stopped
            assert proc.wait(timeout=10) == 2
            continue
        if case == 'cancel-review':
            until('event', 'thread/tokenUsage/updated')
            op('status')
            running = until('op', 'status')['result']['review']
            assert running['outcome'] == 'running' and running['nativeStatus'] == 'unknown'
            assert running['report']['verdict'] == 'APPROVE'
            op('cancel', target='review')
            assert until('op', 'cancel')['result']['confirmed']
        else:
            result = until('finished', 'review')
            assert result['outcome'] == {'writers': 'budget_exhausted', 'revise': 'REVISE', 'block': 'BLOCK', 'invalid': 'invalid_output',
                                         'budget': 'budget_exhausted', 'timeout': 'timed_out',
                                         'cancelled': 'cancelled', 'failed-empty': 'failed',
                                         'failed-report': 'failed'}.get(case, 'APPROVE'), result
        op('status')
        status = until('op', 'status')['result']
        review = status['review']
        assert review['turnId'] == 'turn-0' and review['threadId'] == review['native']['threadId']
        assert review['binding']['tree'] == candidate['tree']
        assert (status['approval'] == review['id']) == (review['outcome'] == 'APPROVE')
        if case == 'failed-empty':
            assert review['report'] is None and review['reportError']
        else:
            assert json.loads(review['rawReport']) == review['report']
            assert review['reportError'] is None
            assert review['coverageError'] == ('duplicate coverage check: G2' if case == 'invalid' else None)
        if case == 'cancel-review':
            assert review['outcome'] == 'cancelled' and status['approval'] is None
            # Completion observed while cancelling is diagnostic, never approval.
            assert review['nativeStatus'] == 'completed' and review['report']['verdict'] == 'APPROVE'
        if case in ('writers', 'budget', 'timeout', 'failed-empty', 'failed-report', 'cancelled'):
            assert review['nativeStatus'] in ('failed', 'interrupted')
            assert review['finalUsage'] is None and review['lastUsage']['total']['totalTokens'] == 12
        if case == 'implementation-budget':
            assert status['outcome'] == 'budget_exhausted' and status['nativeStatus'] == 'failed'
            assert review['outcome'] == 'APPROVE'
        if case == 'deferred':
            assert [d['check'] for d in review['report']['deferred_acceptance']] == ['D-CI']
        assert inspect(task)['review'] == review
        if case == 'writers':
            assert review['native']['budget']['limit'] == 100000
            # A same-candidate review receives just the immediately preceding diagnostic snapshot.
            first = review
            op('review', tree=candidate['tree'], dossier=str(dossier))
            assert until('finished', 'review')['outcome'] == 'APPROVE'
            op('status')
            status = until('op', 'status')['result']
            assert status['previousReview'] == first
            second = status['review']
            assert second['id'] != first['id'] and second['binding']['tree'] == first['binding']['tree']
            assert second['finalUsage']['total']['totalTokens'] == 12
            # A continuation uses the still-loaded implementation root and invalidates approval.
            op('turn', prompt='Apply the requested in-scope revision.')
            until('finished', 'implementation')
            op('status')
            assert until('op', 'status')['result']['approval'] is None
            op('capture')
            changed = until('op', 'capture')['result']
            assert changed['tree'] != candidate['tree']
            dossier = write_dossier(case, task, changed,
                                    '1. Verified facts and sources: new fixture evidence.\n'
                                    '2. Questions for independent judgment: recheck changed inputs.\n'
                                    '3. Candidate or input changes: tracked now contains native revision.')
            op('review', tree=changed['tree'], dossier=str(dossier))
            assert until('finished', 'review')['outcome'] == 'APPROVE'
            op('status')
            status = until('op', 'status')['result']
            assert status['previousReview'] == second and 'previousReview' not in second
            assert status['review']['binding']['tree'] == changed['tree']
            assert status['approval'] == status['review']['id']
        op('close')
        until('op', 'close')
        assert proc.wait(timeout=10) == 0, proc.stderr.read()
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        starts = [c['params'] for c in calls if c.get('method') == 'thread/start']
        assert len(starts) == (4 if case == 'writers' else 2)
        assert starts[1]['model'] == 'gpt-6.2-astra'
        assert starts[1]['config']['model_reasoning_effort'] == 'high'
        assert starts[1]['sandbox'] == 'read-only'
        assert starts[1]['config']['features.apps'] is False
        assert starts[1]['config']['features.plugins'] is False
        assert starts[1]['config']['mcp_servers.write.enabled'] is False
        assert starts[1]['config']['mcp_servers.docs.enabled_tools'] == ['read']
        assert all('resume' not in c.get('method', '') and 'fork' not in c.get('method', '') for c in calls)
        reviews = [c['params'] for c in calls if c.get('method') == 'turn/start' and c['params']['threadId'] != 'root-0']
        for index, request in enumerate(reviews):
            prompt = request['input'][0]['text']
            summary = json.loads(re.search(r'Current validated evidence:\n(.*?)\n', prompt)[1])
            assert [item['gate'] for item in summary] == [gate['id'] for gate in gates]
            assert all(item['status'] == 'PASS' and Path(item['artifact']['path']).is_file()
                       and item['artifact']['sha256'] == hashlib.sha256(Path(item['artifact']['path']).read_bytes()).hexdigest()
                       for item in summary)
            previous = json.loads(re.search(r'Previous review:\n(.*?)\n', prompt)[1])
            assert previous is None if index == 0 else previous['id'] == (first if index == 1 else second)['id']
        if case == 'writers':
            assert any(c.get('method') == 'turn/interrupt' and c['params']['threadId'] == 'child-a' for c in calls)
            assert {c['params']['processId'] for c in calls if c.get('method') == 'thread/backgroundTerminals/terminate'} == {'101', '102'}
            assert any(c.get('method') == 'thread/list' and c['params'].get('cursor') for c in calls)
            assert any(c.get('method') == 'thread/turns/list' and c['params'].get('cursor') for c in calls)
            roles = json.loads((skill / 'config/roles.json').read_text())['roles']
            expected = {
                'economy': ('gpt-6-luna', 'low'),
                'standard': ('gpt-6.2-sol', 'medium'),
                'deep': ('gpt-6.2-sol', 'xhigh'),
                'writer': ('gpt-6.2-astra', 'xhigh'),
                'reviewer': ('gpt-6.2-astra', 'high'),
                'scout': ('gpt-6.2-sol', 'medium'),
                'visual': ('gpt-6.2-astra', 'xhigh'),
            }
            assert roles.keys() == expected.keys()
            schema = json.loads(Path(os.environ['CODEX_CONFIG_SCHEMA']).read_text())
            validator = Draft7Validator(schema)
            for name, (model, effort) in expected.items():
                role = roles[name]
                assert (role['model'], role['reasoningEffort'], role['verbosity']) == (model, effort, 'medium')
                config = starts[0]['config']
                actual = tomllib.loads(Path(config[f'agents.{name}.config_file']).read_text())
                validator.validate(actual)
                assert actual == {
                    'model': model, 'model_reasoning_effort': effort, 'model_verbosity': 'medium',
                    'developer_instructions': role['instructions'],
                }
                assert config[f'agents.{name}.description'] == role['instructions']
    print('connected .20 fixtures passed: review constraints, report retention, interruption, handoff, paged freeze, continuity and tool permissions')
