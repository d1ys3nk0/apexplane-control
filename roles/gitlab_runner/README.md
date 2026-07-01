# gitlab_runner

This role installs and configures GitLab Runner.

## Features
- Install GitLab Runner from the official apt repository in dedicated mode.
- Optionally run GitLab Runner in a standalone Docker container.
- Render GitLab Runner `config.toml` from role variables.
- Restart or start the runner after config changes.
- Verify the runner process after setup.

## Configuration
Set these required inputs before applying the role: `gitlab_runner_url`, `gitlab_runner_token`, `gitlab_runner_docker_image_tag`.

| Variable | Default |
| --- | --- |
| `gitlab_runner_mode` | `dedicated` |
| `gitlab_runner_url` | `~` |
| `gitlab_runner_token` | `~` |
| `gitlab_runner_name` | `<derived>` |
| `gitlab_runner_executor` | `docker` |
| `gitlab_runner_concurrency` | `1` |
| `gitlab_runner_check_interval` | `0` |
| `gitlab_runner_shutdown_timeout` | `0` |
| `gitlab_runner_session_timeout` | `1800` |
| `gitlab_runner_output_limit` | `''` |
| `gitlab_runner_config_dir` | `<derived>` |
| `gitlab_runner_config_path` | `<derived>` |
| `gitlab_runner_apt_key_url` | `https://packages.gitlab.com/runner/gitlab-runner/gpgkey` |
| `gitlab_runner_apt_key_asc_path` | `/usr/share/keyrings/runner_gitlab-runner-archive-keyring.asc` |
| `gitlab_runner_apt_keyring_path` | `/usr/share/keyrings/runner_gitlab-runner-archive-keyring.gpg` |
| `gitlab_runner_apt_repo_url` | `<derived>` |
| `gitlab_runner_apt_repo_distribution` | `<derived>` |
| `gitlab_runner_apt_repo_component` | `main` |
| `gitlab_runner_package_version` | `''` |
| `gitlab_runner_package_state` | `present` |
| `gitlab_runner_service_name` | `gitlab-runner` |
| `gitlab_runner_dedicated_config_dir` | `/etc/gitlab-runner` |
| `gitlab_runner_container_name` | `gitlab-runner` |
| `gitlab_runner_image_name` | `gitlab/gitlab-runner` |
| `gitlab_runner_image_tag` | `<required in docker mode>` |
| `gitlab_runner_image_full` | `<derived>` |
| `gitlab_runner_docker_config_dir` | `/srv/gitlab-runner/config` |
| `gitlab_runner_container_mem_res` | `200M` |
| `gitlab_runner_container_mem_lim` | `300M` |
| `gitlab_runner_container_mem_swp` | `400M` |
| `gitlab_runner_docker_image_name` | `docker` |
| `gitlab_runner_docker_image_tag` | `<required>` |
| `gitlab_runner_docker_image_full` | `<derived>` |
| `gitlab_runner_docker_tls_verify` | `false` |
| `gitlab_runner_docker_privileged` | `false` |
| `gitlab_runner_docker_disable_entrypoint_overwrite` | `false` |
| `gitlab_runner_docker_oom_kill_disable` | `false` |
| `gitlab_runner_docker_disable_cache` | `false` |
| `gitlab_runner_docker_volumes` | `<complex>` |
| `gitlab_runner_docker_shm_size` | `0` |
| `gitlab_runner_docker_network_mtu` | `0` |
| `gitlab_runner_docker_extra_hosts` | `<complex>` |
| `gitlab_runner_docker_pull_policy` | `always` |
| `gitlab_runner_docker_allowed_pull_policies` | `<complex>` |
| `gitlab_runner_docker_service_mem_res` | `1000M` |
| `gitlab_runner_docker_service_mem_lim` | `1500M` |
| `gitlab_runner_docker_service_mem_swp` | `2000M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.gitlab_runner
      vars:
        gitlab_runner_url: https://gitlab.example.com
        gitlab_runner_token: <runner-token>
        gitlab_runner_docker_image_tag: '29.5.0'
```

## Operations
Dedicated mode is the default. It installs the `gitlab-runner` package, writes `/etc/gitlab-runner/config.toml`, restarts `gitlab-runner` when the rendered config changes, and verifies the runner.

Docker mode is opt-in:

```yaml
gitlab_runner_mode: docker
gitlab_runner_image_tag: v18.11.3
```

In Docker mode the role writes `/srv/gitlab-runner/config/config.toml`, starts the `gitlab-runner` container, mounts Docker socket access for Docker executor jobs, and verifies the runner after the container is running.

Set `gitlab_runner_package_version` to pin the dedicated runner package version. When it is unset, apt installs the current repository package with state `present`.

Tune runner behavior through role variables, not by manually editing `config.toml` on the host.
