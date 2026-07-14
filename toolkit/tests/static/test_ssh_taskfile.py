from __future__ import annotations

from typing import cast

import yaml
from apc_target_static import target_repo_root


REPO_ROOT = target_repo_root()
ROOT_TASKFILE = REPO_ROOT / ".taskfiles" / "root.yml"


YamlMapping = dict[str, object]


def root_tasks() -> dict[str, YamlMapping]:
    data = yaml.safe_load(ROOT_TASKFILE.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    tasks = data["tasks"]
    assert isinstance(tasks, dict)
    assert all(isinstance(name, str) and isinstance(task, dict) for name, task in tasks.items())
    return cast("dict[str, YamlMapping]", tasks)


def task_script(task: YamlMapping) -> str:
    commands = task["cmds"]
    assert isinstance(commands, list)
    assert all(isinstance(command, str) for command in commands)
    return "\n".join(cast("list[str]", commands))


def required_vars(task: YamlMapping) -> list[str]:
    requires = task["requires"]
    assert isinstance(requires, dict)
    variables = cast("YamlMapping", requires)["vars"]
    assert isinstance(variables, list)
    assert all(isinstance(variable, str) for variable in variables)
    return cast("list[str]", variables)


def task_env(task: YamlMapping) -> YamlMapping:
    env = task["env"]
    assert isinstance(env, dict)
    return cast("YamlMapping", env)


def test_ssh_taskfile_uses_create_and_view_contract() -> None:
    tasks = root_tasks()
    assert "ssh-base64" not in tasks

    create_task = tasks["ssh:create"]
    view_task = tasks["ssh:view"]
    for task in (create_task, view_task):
        assert task["silent"] is True
        assert required_vars(task) == ["REALM", "USER"]
        assert task_env(task)["SSH_KEY_REALM"] == "{{.REALM}}"
        assert task_env(task)["SSH_KEY_USER"] == "{{.USER}}"

    create_script = task_script(create_task)
    assert 'rm -f "${key_path}" "${key_path}.pub"' in create_script
    assert 'key_path="assets/service_ssh_keys/${SSH_KEY_USER}.${SSH_KEY_REALM}"' in create_script
    assert "ssh-keygen -q -t rsa -b 2048" in create_script
    assert '-C "${SSH_KEY_USER}.${SSH_KEY_REALM}"' in create_script
    assert 'uv run ansible-vault encrypt "${key_path}"' in create_script

    view_script = task_script(view_task)
    assert 'key_path="assets/service_ssh_keys/${SSH_KEY_USER}.${SSH_KEY_REALM}"' in view_script
    assert 'test -f "${key_path}"' in view_script
    assert 'printf \'\\n<key type=ssh name=%s realm=%s>\\n\' "${SSH_KEY_USER}" "${SSH_KEY_REALM}"' in view_script
    assert 'uv run ansible-vault view "${key_path}"' in view_script
    assert "printf '\\n</key>\\n\\n'" in view_script
    assert "base64" in view_script
    assert "ssh-keygen" not in view_script
    assert "<key" not in create_script
    assert "deploy." not in f"{create_script}\n{view_script}"
