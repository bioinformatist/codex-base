"""Deterministic current App Server fixture. Never calls a model or external service."""
import json
import os
from pathlib import Path
import re
import sys
import time

threads = {}
terminals = {}
archived = set()
unloaded = set()
close_terminal_lists = 0
case = os.environ.get('NATIVE_FIXTURE_CASE', '')
log = os.environ.get('NATIVE_FIXTURE_LOG')


def send(value):
    print(json.dumps(value), flush=True)


def event(method, **params):
    send({'method': method, 'params': params})


def thread(name):
    data = threads[name]
    turns = data['turns']
    config = data.get('config', {})
    status = ('notLoaded' if name in unloaded else
              'active' if data.get('unidentified_activity') or any(t['status'] == 'inProgress' for t in turns)
              else 'idle')
    return {'id': name, 'sessionId': name if name in unloaded else data.get('session', name),
            'parentThreadId': data.get('parent'), 'ephemeral': False,
            'model': data.get('model'), 'reasoningEffort': config.get('model_reasoning_effort'),
            'cwd': data['cwd'], 'turns': [], 'status': {'type': status}}


def descends(name, ancestor):
    while (name := threads[name].get('parent')) is not None:
        if name == ancestor:
            return True
    return False


def record():
    state = Path(os.environ['XDG_STATE_HOME']) / 'codex-improve-v20/tasks'
    return json.loads((state / os.environ['IMPROVE_TASK_ID'] / 'record.json').read_text().splitlines()[0])


def page(data, params):
    offset = int(params.get('cursor') or 0)
    return {'data': data[offset:offset + 1], 'nextCursor': str(offset + 1) if offset + 1 < len(data) else None}


for raw in sys.stdin:
    message = json.loads(raw)
    if log:
        with open(log, 'a') as stream:
            stream.write(json.dumps(message) + '\n')
    if 'method' not in message or 'id' not in message:
        continue
    method, params = message['method'], message.get('params', {})
    notifications = []
    disconnect_start = False
    if method == 'initialize':
        result = {}
    elif method == 'model/list':
        result = page([{'model': model, 'supportedReasoningEfforts': [
            {'reasoningEffort': effort} for effort in ('low', 'medium', 'high', 'xhigh')]}
            for model in ('gpt-6-luna', 'gpt-6.2-sol', 'gpt-6.2-astra')], params)
    elif method == 'config/read':
        result = {'config': {'mcp_servers': {'docs': {}, 'write': {}}}}
    elif method == 'thread/start':
        pending = record()['roots'][-1]
        assert pending['status'] == 'pending' and pending['cwd'] == params['cwd']
        root = f'root-{len([t for t in threads if t.startswith("root-")])}'
        review = params['sandbox'] == 'read-only'
        config = params['config']
        assert config['features.subagent_default_context_limits'] is True
        assert config['features.rollout_budget.enforce_limit'] is True
        assert config['features.rollout_budget.limit_tokens'] > 0
        threads[root] = {'turns': [], 'cwd': params['cwd'], 'model': params['model'], 'review': review, 'config': config}
        if case == 'lost-thread-start':
            event('thread/started', thread=thread(root))
            sys.exit(0)
        if case in ('active-close', 'foreign-family', 'partial-child', 'unloaded-child',
                    'unload-reused-child', 'parent-rejected'):
            threads['child-a'] = {'turns': [], 'cwd': params['cwd'], 'parent': root, 'materialized': True,
                                  'session': 'other-session' if case == 'foreign-family' else root,
                                  'unidentified_activity': case == 'active-close'}
        result = {'thread': thread(root), 'model': 'wrong-model' if case == 'wrong-model' else params['model'], 'cwd': params['cwd'],
                  'reasoningEffort': 'low' if case == 'wrong-effort' else config['model_reasoning_effort'], 'approvalPolicy': 'never',
                  'sandbox': {'type': 'readOnly' if review else 'workspaceWrite', 'networkAccess': False},
                  'activePermissionProfile': {'id': 'read-only' if review else 'workspace-write'}}
    elif method == 'turn/start':
        root = params['threadId']
        data = threads[root]
        assert params['effort'] == data['config']['model_reasoning_effort']
        for item in params['input'][1:]:
            assert item['type'] == 'localImage'
            path = Path(item['path'])
            assert path.read_bytes().startswith(b'\x89PNG') and path.stat().st_mode & 0o777 == 0o400
        turn = {'id': f'turn-{len(data["turns"])}', 'status': 'inProgress', 'items': [], 'error': None}
        data['turns'].append(turn)
        disconnect_start = (case == 'disconnect-start-review' and data['review']
                            or case == 'disconnect-start-implementation' and not data['review'] and len(data['turns']) == 2)
        result = {'turn': dict(turn)}
        if data['review']:
            if case == 'writers' and root == 'root-1':
                threads['review-child'] = {'turns': [], 'cwd': data['cwd'], 'parent': root,
                                           'session': root, 'materialized': True}
            prompt = params['input'][0]['text']
            routing = json.loads(re.search(r'```json codex-improve-routing\n(.*?)\n```', prompt, re.S)[1])
            gates = json.loads(re.search(r'```json codex-improve-gates\n(.*?)\n```', prompt, re.S)[1])['gates']
            checks = sorted(['scope', *routing['requiredEvidence']])
            deferred = sorted(g['id'] for g in gates if g['class'] == 'deferred acceptance')
            schema = params['outputSchema']['properties']
            assert schema['coverage']['minItems'] == schema['coverage']['maxItems'] == len(checks)
            for name in ('coverage', 'findings'):
                assert schema[name]['items']['properties']['check']['enum'] == checks
            assert schema['deferred_acceptance']['maxItems'] == len(deferred)
            if deferred:
                assert schema['deferred_acceptance']['items']['properties']['check']['enum'] == deferred
            assert json.loads(re.search(r'Review checks:\n(.*?)\n', prompt)[1]) == {
                'coverage': checks, 'deferred_acceptance': deferred}
            verdict = {'revise': 'REVISE', 'block': 'BLOCK'}.get(case, 'APPROVE')
            coverage = [{'check': check, 'status': 'PASS', 'evidence': 'current fixture'}
                        for check in ['scope', *routing['requiredEvidence']]]
            if case == 'invalid':
                coverage[3]['check'] = 'G2'
            findings, blockers = [], []
            if verdict == 'REVISE':
                coverage[0]['status'] = 'FAIL'
                findings = [{'check': 'scope', 'severity': 'medium', 'location': 'tracked:1',
                             'claim': 'fixture finding', 'evidence': 'fixture read', 'action': 'revise'}]
            if verdict == 'BLOCK':
                coverage[0]['status'] = 'BLOCKED'
                blockers = [{'item': 'fixture blocker', 'impact': 'cannot approve'}]
            report = {'verdict': verdict, 'summary': 'fixture review', 'findings': findings,
                      'coverage': coverage, 'review_blockers': blockers,
                      'deferred_acceptance': [{'check': check, 'owner': 'coordinator', 'reason': 'after publication',
                                               'evidence_required': 'exact candidate CI'} for check in deferred]}
        else:
            Path(data['cwd'], 'tracked').write_text('native change' if len(data['turns']) == 1 else 'native revision')
            report = {'status': 'COMPLETE', 'steps': ['changed; ponytail=lean'],
                      'stoppedBecause': None, 'filesChanged': ['tracked'],
                      'notes': ['pending submission report'] if disconnect_start else []}
            if case == 'executor-stopped':
                report.update(status='STOPPED', stoppedBecause='fixture scope conflict')
            if case in ('writers', 'unconfirmed') and 'child-a' not in threads:
                for name in ('child-a', 'child-b', 'nested-c'):
                    threads[name] = {'turns': [], 'cwd': data['cwd'], 'session': root, 'materialized': True,
                                     'parent': 'child-b' if name == 'nested-c' else root}
                threads['child-a']['turns'] = [{'id': 'done-turn', 'status': 'completed', 'items': [], 'error': None},
                                             {'id': 'child-turn', 'status': 'inProgress', 'items': [], 'error': None}]
                terminals['child-b'] = ['101', '102']
                threads['foreign'] = {'turns': [], 'cwd': data['cwd'], 'materialized': True}
        notifications.append(('turn/started', {'threadId': root, 'turn': dict(turn)}))
        if case == 'unload-reused-child' and len(data['turns']) == 2:
            child_turn = {'id': 'child-turn', 'status': 'inProgress', 'items': [], 'error': None}
            threads['child-a']['turns'].append(child_turn)
            unloaded.add('child-a')
            notifications.extend([('turn/started', {'threadId': 'child-a', 'turn': child_turn}),
                                  ('thread/closed', {'threadId': 'child-a'})])
        if case not in ('hold', 'review-running') or data['review']:
            text = 'invalid final' if case == 'invalid-implementation' and not data['review'] else json.dumps(report)
            item = {'id': 'final', 'type': 'agentMessage', 'phase': 'final_answer', 'text': text}
            turn['items'] = [item]
            turn['status'] = 'completed'
            if (data['review'] and (case == 'budget' or case == 'writers' and root == 'root-1')
                    or case in ('implementation-budget', 'interrupted-no-evidence') and not data['review']):
                turn['status'] = 'failed'
                turn['error'] = {'codexErrorInfo': 'sessionBudgetExceeded', 'message': 'budget reached'}
            if case == 'timeout' and data['review']:
                turn['status'] = 'failed'
                turn['error'] = {'codexErrorInfo': 'other', 'message': 'request timed out'}
            if case == 'cancelled' and data['review']:
                turn['status'] = 'interrupted'
            if case in ('failed-empty', 'failed-report') and data['review']:
                turn['status'] = 'failed'
                turn['error'] = {'codexErrorInfo': 'other', 'message': 'fixture failure'}
            if case == 'failed-empty' and data['review']:
                turn['items'] = []
            else:
                notifications.append(('item/completed', {'threadId': root, 'turnId': turn['id'], 'item': item}))
            notifications.append(('thread/tokenUsage/updated', {'threadId': root, 'turnId': turn['id'],
                                                               'tokenUsage': {'total': {'totalTokens': 12}}}))
            if case in ('cancel-review', 'disconnect-review') and data['review'] or disconnect_start:
                turn['status'] = 'inProgress'
            else:
                notifications.append(('turn/completed', {'threadId': root, 'turn': dict(turn)}))
            if case == 'unloaded':
                notifications.append(('thread/status/changed', {'threadId': root, 'status': {'type': 'notLoaded'}}))
    elif method == 'thread/list':
        assert params['modelProviders'] == [] and set(params['sourceKinds']) == {
            'cli', 'vscode', 'exec', 'appServer', 'subAgent', 'subAgentReview', 'subAgentCompact',
            'subAgentThreadSpawn', 'subAgentOther', 'unknown'}
        ancestor = params.get('ancestorThreadId')
        if case == 'unloaded-child' and ancestor == 'root-0' and not threads['child-a']['turns']:
            # The child reappears before the loaded list is read.
            event('thread/closed', threadId='child-a')
            turn = {'id': 'reopened-turn', 'status': 'inProgress', 'items': [], 'error': None}
            event('turn/started', threadId='child-a', turn=turn)
            turn['status'] = 'completed'
            threads['child-a']['turns'].append(turn)
            event('turn/completed', threadId='child-a', turn=turn)
        result = page([thread(t) for t, data in threads.items()
                       if params['archived'] == (t in archived)
                       and (t in archived or data['turns'] or data.get('materialized'))
                       and (descends(t, ancestor) if ancestor else data['cwd'] in params['cwd'])], params)
        if case == 'late-close-child' and close_terminal_lists == 4 and ancestor == 'root-0' and params['archived']:
            # Appear only after the last freeze-family response has been assembled.
            threads['child-a'] = {'turns': [], 'cwd': threads[ancestor]['cwd'], 'parent': ancestor,
                                  'session': ancestor, 'materialized': True}
    elif method == 'thread/loaded/list':
        loaded = [t for t in threads if t not in unloaded]
        if case == 'lost' and threads.get('root-0', {}).get('turns'):
            loaded = []
        if case == 'lost-during-review' and 'root-1' in threads:
            loaded.remove('root-0')
        result = page(loaded, params)
    elif method == 'thread/read':
        assert not params.get('includeTurns')
        result = {'thread': thread(params['threadId'])}
    elif method == 'thread/turns/list':
        name = params['threadId']
        data = threads[name]
        if not (data['turns'] or data.get('materialized') or name in archived) or case == 'history-unavailable':
            send({'id': message['id'], 'error': {'code': -32600, 'message':
                  f'thread {name} is not materialized yet; thread/turns/list is unavailable before first user message'}})
            continue
        result = page(data['turns'], params)
    elif method == 'turn/interrupt':
        result = {}
        for turn in threads[params['threadId']]['turns']:
            if turn['id'] == params['turnId']:
                turn['status'] = 'completed' if case == 'cancel-review' else 'interrupted'
                notifications.append(('turn/completed', {'threadId': params['threadId'], 'turn': dict(turn)}))
    elif method == 'thread/backgroundTerminals/list':
        name = params['threadId']
        assert name not in unloaded
        if case in ('late-close-activity', 'late-close-child'):
            close_terminal_lists += 1
            # In the second snapshot, start a turn after its history was read.
            if (case == 'late-close-activity' and close_terminal_lists == 6
                    or case == 'late-close-child' and name == 'child-a' and close_terminal_lists == 7):
                turn = {'id': 'late-turn', 'status': 'inProgress', 'items': [], 'error': None}
                threads[name]['turns'].append(turn)
                event('turn/started', threadId=name, turn=turn)
        result = page([{'processId': process} for process in terminals.get(name, [])], params)
    elif method == 'thread/backgroundTerminals/terminate':
        result = {'terminated': case != 'unconfirmed'}
        # A disappearing process is not a confirmed native termination response.
        terminals[params['threadId']].remove(params['processId'])
    elif method == 'thread/archive':
        target = params['threadId']
        saved = record()
        assert saved['phase'] == 'closed' and target in saved['closeFreeze']
        assert target not in archived and target != 'foreign'
        if case == 'parent-rejected' and target == 'root-0':
            send({'id': message['id'], 'error': {'code': -32603, 'message': 'fixture parent archive rejected'}})
            continue
        if case == 'partial-child' and target == 'child-a':
            send({'id': message['id'], 'error': {'code': -32603, 'message': 'fixture child archive failed'}})
            continue
        for name in threads:
            if name != target and not descends(name, target):
                continue
            assert name in saved['closeFreeze'] and not terminals.get(name)
            assert all(t['status'] != 'inProgress' for t in threads[name]['turns'])
            if name not in unloaded:
                unloaded.add(name)
                notifications.extend([('thread/status/changed', {'threadId': name, 'status': {'type': 'notLoaded'}}),
                                      ('thread/closed', {'threadId': name})])
            if name != 'child-a' or target != 'root-0' or case not in ('writers', 'partial-child'):
                archived.add(name)
        if case == 'archive-stall':
            for name, value in notifications:
                event(name, **value)
            # Keep the pipes open after the side effect and send no matching response.
            for _ in range(42):
                event('thread/archived', threadId=target)
                time.sleep(0.75)
            continue
        result = {}
    elif method == 'mcpServerStatus/list':
        config = threads[params['threadId']]['config']
        tools = config.get('mcp_servers.docs.enabled_tools', [])
        if case == 'extra-tool':
            tools = [*tools, 'write']
        result = page([{'name': 'docs', 'toolsError': None, 'tools': {tool: {
            'name': tool, 'inputSchema': {'type': 'object'},
            'annotations': {'readOnlyHint': case != 'write-tool', 'destructiveHint': False}}
            for tool in tools}}] if tools else [], params)
    else:
        send({'id': message['id'], 'error': {'code': -32601, 'message': method}})
        continue
    if not disconnect_start:
        send({'id': message['id'], 'result': result})
    for name, value in notifications:
        event(name, **value)
    if disconnect_start or method == 'turn/start' and case == 'disconnect-review' and threads[params['threadId']]['review']:
        sys.exit(0)

if case == 'shutdown-stall':
    time.sleep(60)
elif case == 'shutdown-wrapper':
    release = Path(log).with_suffix('.release')
    deadline = time.monotonic() + 12
    while not release.exists() and time.monotonic() < deadline:
        time.sleep(0.05)
