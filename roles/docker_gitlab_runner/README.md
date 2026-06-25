# docker_gitlab_runner

This role runs a GitLab Runner in a standalone Docker container.

## Features
- Ensure GitLab runner config directory exists.
- Write GitLab runner config.
- Start GitLab runner container.

## Configuration
Set these required inputs before applying the role: `docker_gitlab_runner_url`, `docker_gitlab_runner_token`.

| Variable | Default |
| --- | --- |
| `docker_gitlab_runner_container_name` | `gitlab-runner` |
| `docker_gitlab_runner_ci_mode` | `<derived>` |
| `docker_gitlab_runner_debug_mode` | `<derived>` |
| `docker_gitlab_runner_nolog` | `<derived>` |
| `docker_gitlab_runner_image_name` | `gitlab/gitlab-runner` |
| `docker_gitlab_runner_image_tag` | `<required>` |
| `docker_gitlab_runner_image_full` | `<derived>` |
| `docker_gitlab_runner_config_dir` | `/srv/gitlab-runner/config` |
| `docker_gitlab_runner_config_path` | `<derived>` |
| `docker_gitlab_runner_url` | `~` |
| `docker_gitlab_runner_token` | `~` |
| `docker_gitlab_runner_name` | `<derived>` |
| `docker_gitlab_runner_executor` | `docker` |
| `docker_gitlab_runner_docker_image_name` | `docker` |
| `docker_gitlab_runner_docker_image_tag` | `<required>` |
| `docker_gitlab_runner_docker_image_full` | `<derived>` |
| `docker_gitlab_runner_concurrency` | `1` |
| `docker_gitlab_runner_session_timeout` | `1800` |
| `docker_gitlab_runner_check_interval` | `0` |
| `docker_gitlab_runner_shutdown_timeout` | `0` |
| `docker_gitlab_runner_docker_tls_verify` | `false` |
| `docker_gitlab_runner_docker_privileged` | `false` |
| `docker_gitlab_runner_docker_disable_entrypoint_overwrite` | `false` |
| `docker_gitlab_runner_docker_oom_kill_disable` | `false` |
| `docker_gitlab_runner_docker_disable_cache` | `false` |
| `docker_gitlab_runner_docker_volumes` | `<complex>` |
| `docker_gitlab_runner_docker_shm_size` | `0` |
| `docker_gitlab_runner_docker_network_mtu` | `0` |
| `docker_gitlab_runner_docker_extra_hosts` | `<complex>` |
| `docker_gitlab_runner_docker_pull_policy` | `always` |
| `docker_gitlab_runner_docker_allowed_pull_policies` | `<complex>` |
| `docker_gitlab_runner_service_mem_res` | `1000M` |
| `docker_gitlab_runner_service_mem_lim` | `1500M` |
| `docker_gitlab_runner_service_mem_swp` | `2000M` |
| `docker_gitlab_runner_mem_res` | `200M` |
| `docker_gitlab_runner_mem_lim` | `300M` |
| `docker_gitlab_runner_mem_swp` | `400M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_gitlab_runner
      vars:
        docker_gitlab_runner_url: <value>
        docker_gitlab_runner_token: <value>
```

## Operations
Provision runner hosts with the `docker_gitlab_runner` role. The host playbook must install and start Docker before this role runs.

Set the required role inputs in the caller variables:

```yaml
docker_gitlab_runner_url: https://gitlab.example.com
docker_gitlab_runner_token: <runner-token>
```

The role writes `/srv/gitlab-runner/config/config.toml`, starts the `gitlab-runner` container, mounts Docker socket access for Docker executor jobs, and verifies the runner after the container is running.

Useful baseline values:

```toml
concurrent = 1
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800
```

Tune runner behavior through role variables, not by manually editing `config.toml` on the host.
