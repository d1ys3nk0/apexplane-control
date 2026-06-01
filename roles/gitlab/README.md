# gitlab

This role installs and configures GitLab Omnibus.

## Features
- Download GitLab GPG key.
- Convert GitLab GPG key.
- Update config.

## Configuration
Set these required inputs before applying the role: `gitlab_email_from`, `gitlab_email_sender`, `gitlab_external_url`, `gitlab_minio_root_pass`, `gitlab_minio_root_user`, `gitlab_registry_external_url`, `gitlab_s3_endpoint`, `gitlab_smtp_domain`, `gitlab_smtp_host`, `gitlab_smtp_pass`, `gitlab_smtp_user`, `gitlab_sre_email`.

| Variable | Default |
| --- | --- |
| `gitlab_ci_mode` | `<derived>` |
| `gitlab_debug_mode` | `<derived>` |
| `gitlab_nolog` | `<derived>` |
| `gitlab_email_from` | `~` |
| `gitlab_email_sender` | `~` |
| `gitlab_external_url` | `~` |
| `gitlab_minio_root_pass` | `~` |
| `gitlab_minio_root_user` | `~` |
| `gitlab_node_exporter_port` | `9100` |
| `gitlab_registry_external_url` | `~` |
| `gitlab_s3_endpoint` | `~` |
| `gitlab_smtp_domain` | `~` |
| `gitlab_smtp_host` | `~` |
| `gitlab_smtp_pass` | `~` |
| `gitlab_smtp_port` | `587` |
| `gitlab_smtp_user` | `~` |
| `gitlab_sre_email` | `~` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.gitlab
      vars:
        gitlab_email_from: <value>
        gitlab_email_sender: <value>
        gitlab_external_url: <value>
        gitlab_minio_root_pass: <value>
        gitlab_minio_root_user: <value>
        gitlab_registry_external_url: <value>
        gitlab_s3_endpoint: <value>
        gitlab_smtp_domain: <value>
        gitlab_smtp_host: <value>
        gitlab_smtp_pass: <value>
        gitlab_smtp_user: <value>
        gitlab_sre_email: <value>
```
