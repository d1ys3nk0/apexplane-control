# GitLab Runner

Provision runner hosts with the `docker_gitlab_runner` role. The host playbook must install and start Docker before this role runs.

Set the role inputs in the consuming repository variables:

```yaml
docker_gitlab_runner_url: https://gitlab.example.com
docker_gitlab_runner_token: '{{ vv_runner_token }}'
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
