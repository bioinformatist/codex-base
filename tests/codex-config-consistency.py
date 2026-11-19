"""Validate actual managed/merged TOML and documented fragments against the pinned CLI."""
import json
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import tomllib

from jsonschema import Draft7Validator


schema_path, source, managed_path, merge_helper = map(Path, sys.argv[1:])
schema = json.loads(schema_path.read_text())
assert schema['$schema'] == 'http://json-schema.org/draft-07/schema#'
Draft7Validator.check_schema(schema)
validator = Draft7Validator(schema)


def assert_managed(config):
    validator.validate(config)
    assert config['model'] == 'gpt-6.2-sol'
    assert config['model_reasoning_effort'] == 'medium'
    assert config['model_verbosity'] == 'medium'
    assert config['plan_mode_reasoning_effort'] == 'high'
    assert config['sandbox_mode'] == 'workspace-write'
    assert config['approval_policy'] == 'on-request'
    assert config['web_search'] == 'live'
    assert config['mcp_oauth_credentials_store'] == 'file'
    assert config['features']['context_management']['experimental_mode'] is True
    assert config['features']['code_mode']['enabled'] is True
    assert config['features']['default_mode_request_user_input'] is True
    assert config['features']['memories'] is True
    assert config['features']['hooks'] is True


managed = tomllib.loads(managed_path.read_text())
assert_managed(managed)
assert 'personality' not in managed
assert not {'token_budget', 'subagent_default_context_limits',
            'defer_mailbox_preemption', 'login_shell_package_path'} & managed['features'].keys()

errors = list(validator.iter_errors({**managed, 'codex_base_unknown_key': True}))
assert len(errors) == 1 and errors[0].validator == 'additionalProperties'

for name in ('docs/configuration.md', 'docs/configuration.zh-CN.md'):
    fragments = re.findall(r'```toml\n(.*?)```', (source / name).read_text(), re.S)
    assert len(fragments) == 1, name
    validator.validate(tomllib.loads(fragments[0]))


def run_merge(target):
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call([str(merge_helper), str(managed_path), str(target)])
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    config = tomllib.loads(target.read_text())
    assert_managed(config)
    return config


with tempfile.TemporaryDirectory() as td:
    # Merge into an absent configuration.
    empty_target = Path(td) / '.codex/config.toml'
    assert not empty_target.exists()
    empty = run_merge(empty_target)
    assert 'personality' not in empty
    assert 'model_context_window' not in empty
    assert 'model_auto_compact_token_limit' not in empty

    # Managed values win without erasing user fields, including a deprecated key.
    existing_path = Path(td) / 'existing.toml'
    existing_path.write_text('''personality = "pragmatic"
model_context_window = 123456
model_auto_compact_token_limit = 100000
[mcp_servers.custom]
url = "https://custom.example/mcp"
[history]
persistence = "none"

[features]
shell_snapshot = false
context_management.experimental_mode = false
default_mode_request_user_input = false

[features.code_mode]
enabled = false
default_exec_yield_time_ms = 250
''')
    merged = run_merge(existing_path)
    assert merged['features']['shell_snapshot'] is False
    assert merged['features']['code_mode']['default_exec_yield_time_ms'] == 250
    assert merged['history'] == {'persistence': 'none'}
    assert merged['personality'] == 'pragmatic'
    assert merged['model_context_window'] == 123456
    assert merged['model_auto_compact_token_limit'] == 100000
    assert merged['mcp_servers']['custom'] == {'url': 'https://custom.example/mcp'}
    assert run_merge(existing_path) == merged

print('Draft 07: actual managed/merged TOML and bilingual fragments passed; unknown key rejected')
print('personality is schema-accepted and preserved, but no longer selects a style in Codex 0.170.0')
