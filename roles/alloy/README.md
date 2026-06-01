# alloy

This role installs and configures Grafana Alloy as a system service.

## Features
- Ensure apt keyring directory exists.
- Install Alloy.
- Ensure Alloy config directory exists.
- Store detected Alloy supplemental groups.
- Ensure Alloy systemd override directory exists.
- Deploy Alloy systemd override.
- Upload Alloy config.
- Upload Alloy service defaults.
- Restart Alloy after environment or permissions change.
- Enable and start Alloy service.

## Configuration
Set these required inputs before applying the role: `alloy_cluster_name`, `alloy_cluster_realm`, `alloy_cluster_platform`.

| Variable | Default |
| --- | --- |
| `alloy_ci_mode` | `<derived>` |
| `alloy_debug_mode` | `<derived>` |
| `alloy_nolog` | `<derived>` |
| `alloy_logs_ep` | `''` |
| `alloy_logs_basic_auth_user` | `''` |
| `alloy_logs_basic_auth_password` | `''` |
| `alloy_logs_url` | `<derived>` |
| `alloy_logs_user` | `<derived>` |
| `alloy_logs_pass` | `<derived>` |
| `alloy_metrics_ep` | `''` |
| `alloy_metrics_basic_auth_user` | `''` |
| `alloy_metrics_basic_auth_password` | `''` |
| `alloy_metrics_url` | `<derived>` |
| `alloy_metrics_user` | `<derived>` |
| `alloy_metrics_pass` | `<derived>` |
| `alloy_traces_ep` | `''` |
| `alloy_traces_basic_auth_user` | `''` |
| `alloy_traces_basic_auth_password` | `''` |
| `alloy_traces_url` | `<derived>` |
| `alloy_traces_user` | `<derived>` |
| `alloy_traces_pass` | `<derived>` |
| `alloy_traces_tls_insecure` | `true` |
| `alloy_cluster_name` | `~` |
| `alloy_cluster_realm` | `~` |
| `alloy_cluster_platform` | `~` |
| `alloy_metrics_extra_targets` | `[]` |
| `alloy_apt_repo_url` | `https://apt.grafana.com` |
| `alloy_web_port` | `12345` |
| `alloy_otlp_grpc_port` | `4317` |
| `alloy_otlp_http_port` | `4318` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.alloy
      vars:
        alloy_cluster_name: <value>
        alloy_cluster_realm: <value>
        alloy_cluster_platform: <value>
```
