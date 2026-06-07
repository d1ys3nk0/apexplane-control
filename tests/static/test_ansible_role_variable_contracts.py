from __future__ import annotations

from pathlib import Path

from ansible_role_variable_contracts import run


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_repository_role_variable_contracts_pass() -> None:
    assert run(repo_root=REPO_ROOT) == []


def test_repeated_task_accumulations_require_role_vars(tmp_path: Path) -> None:
    role_dir = tmp_path / "roles" / "example"
    (role_dir / "tasks").mkdir(parents=True)
    (role_dir / "tasks" / "main.yml").write_text(
        """---

- name: Accumulate example values once
  ansible.builtin.set_fact:
    example_values: '{{ example_values + [item] }}'
  loop: '{{ [1] }}'

- name: Accumulate example values twice
  ansible.builtin.set_fact:
    example_values: '{{ example_values + [item] }}'
  loop: '{{ [2] }}'
""",
        encoding="utf-8",
    )

    assert run(repo_root=tmp_path) == [
        "roles/example/tasks/main.yml:5: derive repeated accumulated variable example_values in roles/example/vars/main.yml"
    ]
