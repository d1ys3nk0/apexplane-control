# sentry

This role installs and configures Sentry self-hosted.

## Features
- Checkout the Sentry self-hosted repository.
- Pin the checkout to a configured Sentry version.
- Render `.env.custom` for the selected Compose profile and runtime settings.
- Render Sentry SMTP configuration.
- Render Sentry web and CSRF configuration.
- Run upstream install or upgrade when managed inputs change.
- Start the Docker Compose stack.

## Configuration
Set these required inputs before applying the role: `sentry_smtp_host`, `sentry_smtp_port`, `sentry_smtp_user`, `sentry_smtp_pass`, `sentry_csrf_trusted_origins`.

| Variable | Default |
| --- | --- |
| `sentry_ci_mode` | `<derived>` |
| `sentry_debug_mode` | `<derived>` |
| `sentry_nolog` | `<derived>` |
| `sentry_repo_url` | `https://github.com/getsentry/self-hosted.git` |
| `sentry_version` | `26.3.1` |
| `sentry_install_dir` | `/opt/sentry` |
| `sentry_install_parent_dir` | `/opt` |
| `sentry_compose_profiles` | `errors-only` |
| `sentry_event_retention_days` | `30` |
| `sentry_taskworker_concurrency` | `3` |
| `sentry_report_self_hosted_issues` | `true` |
| `sentry_smtp_backend` | `smtp` |
| `sentry_smtp_host` | `~` |
| `sentry_smtp_port` | `~` |
| `sentry_smtp_user` | `~` |
| `sentry_smtp_pass` | `~` |
| `sentry_smtp_use_tls` | `false` |
| `sentry_smtp_use_ssl` | `true` |
| `sentry_web_host` | `0.0.0.0` |
| `sentry_web_port` | `9000` |
| `sentry_csrf_trusted_origins` | `[]` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.sentry
      vars:
        sentry_smtp_host: smtp.example.com
        sentry_smtp_port: 465
        sentry_smtp_user: sentry@example.com
        sentry_smtp_pass: <smtp-password>
        sentry_csrf_trusted_origins:
          - https://sentry.example.com
```
