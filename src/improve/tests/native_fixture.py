"""Deterministic current App Server fixture. Never calls a model or external service."""
import json
import os
from pathlib import Path
import re
import sys

threads = {}
terminals = {}
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
    return {'id': name, 'sessionId': name if name.startswith('root-') else 'root-0',
            'model': data.get('model'), 'reasoningEffort': config.get('model_reasoning_effort'),
            'cwd': data['cwd'], 'turns': [],
            'status': {'type': 'active' if any(t['status'] == 'inProgress' for t in turns) else 'idle'}}


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
        root = f'root-{len([t for t in threads if t.startswith("root-")])}'
        review = params['sandbox'] == 'read-only'
        config = params['config']
        assert config['features.rollout_budget.enforce_limit'] is True
        assert config['features.rollout_budget.limit_tokens'] > 0
        threads[root] = {'turns': [], 'cwd': params['cwd'], 'model': params['model'], 'review': review, 'config': config}
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
                    threads[name] = {'turns': [], 'cwd': data['cwd'], 'review': False}
                threads['child-a']['turns'] = [{'id': 'done-turn', 'status': 'completed', 'items': [], 'error': None},
                                             {'id': 'child-turn', 'status': 'inProgress', 'items': [], 'error': None}]
                terminals['child-b'] = ['101', '102']
        notifications.append(('turn/started', {'threadId': root, 'turn': dict(turn)}))
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
        result = page([{'id': t} for t in threads if not t.startswith('root-')]
                      if params['ancestorThreadId'] == 'root-0' and not params['archived'] else [], params)
    elif method == 'thread/loaded/list':
        loaded = list(threads)
        if case == 'lost' and threads.get('root-0', {}).get('turns'):
            loaded = []
        if case == 'lost-during-review' and 'root-1' in threads:
            loaded.remove('root-0')
        result = page(loaded, params)
    elif method == 'thread/read':
        assert not params.get('includeTurns')
        result = {'thread': thread(params['threadId'])}
    elif method == 'thread/turns/list':
        result = page(threads[params['threadId']]['turns'], params)
    elif method == 'turn/interrupt':
        result = {}
        for turn in threads[params['threadId']]['turns']:
            if turn['id'] == params['turnId']:
                turn['status'] = 'completed' if case == 'cancel-review' else 'interrupted'
                notifications.append(('turn/completed', {'threadId': params['threadId'], 'turn': dict(turn)}))
    elif method == 'thread/backgroundTerminals/list':
        result = page([{'processId': process} for process in terminals.get(params['threadId'], [])], params)
    elif method == 'thread/backgroundTerminals/terminate':
        result = {'terminated': case != 'unconfirmed'}
        # A disappearing process is not a confirmed native termination response.
        terminals[params['threadId']].remove(params['processId'])
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
