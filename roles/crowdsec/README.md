# crowdsec

This role installs CrowdSec, AppSec collections, and the HAProxy SPOA bouncer components.

## Features
- Disable CrowdSec services.
- Gather service facts before disabling CrowdSec.
- Configure CrowdSec services.
- Create CrowdSec SPOA bouncer group.
- Create CrowdSec SPOA bouncer user.
- Install CrowdSec agent and HAProxy SPOA bouncer.
- Ensure CrowdSec config directories exist.
- Deploy acquisition config for HAProxy logs.
- Deploy acquisition config for CrowdSec AppSec.
- Update CrowdSec Hub index.
- Install CrowdSec Hub collections.
- Deploy CrowdSec SPOA bouncer config with AppSec forwarding.

## Configuration
Set these required inputs before applying the role: `crowdsec_bouncer_key`.

| Variable | Default |
| --- | --- |
| `crowdsec_ci_mode` | `<derived>` |
| `crowdsec_debug_mode` | `<derived>` |
| `crowdsec_nolog` | `<derived>` |
| `crowdsec_enabled` | `true` |
| `crowdsec_apt_key_url` | `https://packagecloud.io/crowdsec/crowdsec/gpgkey` |
| `crowdsec_apt_key_path` | `/etc/apt/keyrings/crowdsec.asc` |
| `crowdsec_apt_repo_url` | `https://packagecloud.io/crowdsec/crowdsec/ubuntu/` |
| `crowdsec_apt_repo_distribution` | `<derived>` |
| `crowdsec_apt_repo_component` | `main` |
| `crowdsec_collections` | `<complex>` |
| `crowdsec_spoa_system_group` | `crowdsec-spoa` |
| `crowdsec_spoa_system_user` | `<derived>` |
| `crowdsec_spoa_bouncer_name` | `haproxy-spoa-bouncer` |
| `crowdsec_appsec_config` | `crowdsecurity/appsec-default` |
| `crowdsec_appsec_url` | `http://127.0.0.1:7422` |
| `crowdsec_appsec_timeout` | `200ms` |
| `crowdsec_spoa_hosts` | `<complex>` |
| `crowdsec_bouncer_key` | `~` |
| `crowdsec_http_port` | `8080` |
| `crowdsec_spoa_port` | `9000` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.crowdsec
      vars:
        crowdsec_bouncer_key: <value>
```

## Operations
CrowdSec is deployed by the `crowdsec` role and enforced at HAProxy ALB through the HAProxy SPOA bouncer when both variables are enabled:

```yml
crowdsec_enabled: true
haproxy_alb_crowdsec_enabled: true
```

### What It Protects

- HTTP and HTTPS traffic that reaches HAProxy ALB.
- HAProxy request inspection through SPOE/SPOA.
- AppSec virtual patching, AppSec generic rules, HTTP CVE rules, and common HTTP scanner scenarios installed through CrowdSec collections.
- WordPress scanner scenarios from CrowdSec Hub.
- HAProxy log scenarios from journald acquisition.

CrowdSec does not protect SSH, database, Redis, RabbitMQ, Docker overlay, or other non-HAProxy traffic unless a consuming repository adds another bouncer.

Apart from the HAProxy ALB bouncer and AppSec/WAF rules, the shared roles only install and configure the local CrowdSec engine, collections, parsers, acquisition, `cscli`, and the SPOA bouncer service. They do not add separate network firewall rules or bouncers for other protocols.

### Blocking Risk

CrowdSec can block legitimate clients if a real user shares an IP with abusive traffic, trips an HTTP scenario, or matches an AppSec rule. The default collection list includes WordPress scanner scenarios; repositories that proxy real WordPress workloads must review whether those scenarios are appropriate. Enforcement is IP decision based at HAProxy ALB, so the practical impact is that requests from the decided IP can be denied until the decision expires or is deleted.

Before enabling it for production traffic, keep HAProxy logs visible, confirm the project toggle value, and be ready to inspect and delete decisions with `cscli`.

### Where to Check

Run commands on every host that runs CrowdSec. The decision database is local to that host unless a repository explicitly configures a central CrowdSec LAPI.

List active decisions:

```sh
sudo cscli decisions list
sudo cscli decisions list --ip 1.2.3.4
```

Inspect why an IP was banned:

```sh
sudo cscli alerts list --ip 1.2.3.4 --limit 0
sudo cscli alerts inspect <alert_id> --details
```

Check logs:

```sh
sudo journalctl -u crowdsec --since "2 hours ago"
sudo journalctl -u crowdsec-spoa-bouncer --since "2 hours ago"
sudo journalctl -u haproxy --since "2 hours ago"
```

### Unban

Delete one IP decision:

```sh
sudo cscli decisions delete --ip 1.2.3.4
```

Other useful forms:

```sh
sudo cscli decisions delete --id <decision_id>
sudo cscli decisions delete --range 1.2.3.0/24
sudo cscli decisions delete --all
```

The HAProxy bouncer refreshes decisions from local CrowdSec periodically. With the default role config, allow roughly 10 seconds for an unban to stop being enforced.

### Web UI

The shared role does not install a local web UI. Use `cscli` on the protected hosts by default.

CrowdSec Console can be enabled separately by enrolling machines, but that is a project-level operational decision because it introduces an external management surface.
