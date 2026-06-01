# mattermost

This role installs and configures Mattermost with optional PostgreSQL provisioning.

## Features
- Install Mattermost packages.
- Configure Mattermost PostgreSQL resources.
- Configure Mattermost services.
- Create temporary Mattermost config overrides file.
- Create temporary merged Mattermost config file.
- Render Mattermost config overrides.
- Merge Mattermost config overrides into current config.
- Install Mattermost config.
- Mattermost service is started and enabled.
- Download Mattermost GPG key.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
Set these required inputs before applying the role: `mattermost_email_feedback_name`, `mattermost_email_feedback_address`, `mattermost_email_reply_to_address`, `mattermost_smtp_host`, `mattermost_smtp_port`, `mattermost_smtp_connection_security`, `mattermost_listen_address`, `mattermost_pg_base`, `mattermost_pg_host`, `mattermost_pg_pass`, `mattermost_pg_port`, `mattermost_pg_user`, `mattermost_s3_access_key`, `mattermost_s3_bucket`, `mattermost_s3_endpoint`, `mattermost_s3_path_prefix`, `mattermost_s3_region`, `mattermost_s3_secret_key`, `mattermost_s3_ssl`, `mattermost_site_url`, `mattermost_support_email`.

| Variable | Default |
| --- | --- |
| `mattermost_ci_mode` | `<derived>` |
| `mattermost_debug_mode` | `<derived>` |
| `mattermost_nolog` | `<derived>` |
| `mattermost_supported_ubuntu_releases` | `<complex>` |
| `mattermost_apt_key_url` | `https://deb.packages.mattermost.com/pubkey.gpg` |
| `mattermost_apt_key_fingerprint` | `A1B31D46F0F3A10B02CF2D44F8F2C31744774B28` |
| `mattermost_apt_key_asc_path` | `/usr/share/keyrings/mattermost-archive-keyring.asc` |
| `mattermost_apt_keyring_path` | `/usr/share/keyrings/mattermost-archive-keyring.gpg` |
| `mattermost_package_name` | `mattermost` |
| `mattermost_config_path` | `/opt/mattermost/config/config.json` |
| `mattermost_email_feedback_name` | `~` |
| `mattermost_email_feedback_address` | `~` |
| `mattermost_email_reply_to_address` | `~` |
| `mattermost_smtp_auth_enabled` | `false` |
| `mattermost_smtp_user` | `''` |
| `mattermost_smtp_pass` | `''` |
| `mattermost_smtp_host` | `~` |
| `mattermost_smtp_port` | `~` |
| `mattermost_smtp_server_timeout` | `10` |
| `mattermost_smtp_connection_security` | `~` |
| `mattermost_smtp_skip_server_certificate_verification` | `false` |
| `mattermost_listen_address` | `~` |
| `mattermost_pg_base` | `~` |
| `mattermost_pg_host` | `~` |
| `mattermost_pg_pass` | `~` |
| `mattermost_pg_port` | `~` |
| `mattermost_pg_user` | `~` |
| `mattermost_pg_admin_pass` | `''` |
| `mattermost_pg_admin_user` | `''` |
| `mattermost_s3_access_key` | `~` |
| `mattermost_s3_bucket` | `~` |
| `mattermost_s3_endpoint` | `~` |
| `mattermost_s3_path_prefix` | `~` |
| `mattermost_s3_region` | `~` |
| `mattermost_s3_secret_key` | `~` |
| `mattermost_s3_ssl` | `~` |
| `mattermost_site_url` | `~` |
| `mattermost_support_email` | `~` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.mattermost
      vars:
        mattermost_email_feedback_name: <value>
        mattermost_email_feedback_address: <value>
        mattermost_email_reply_to_address: <value>
        mattermost_smtp_host: <value>
        mattermost_smtp_port: <value>
        mattermost_smtp_connection_security: <value>
        mattermost_listen_address: <value>
        mattermost_pg_base: <value>
        mattermost_pg_host: <value>
        mattermost_pg_pass: <value>
        mattermost_pg_port: <value>
        mattermost_pg_user: <value>
        mattermost_s3_access_key: <value>
        mattermost_s3_bucket: <value>
        mattermost_s3_endpoint: <value>
        mattermost_s3_path_prefix: <value>
        mattermost_s3_region: <value>
        mattermost_s3_secret_key: <value>
        mattermost_s3_ssl: <value>
        mattermost_site_url: <value>
        mattermost_support_email: <value>
```
