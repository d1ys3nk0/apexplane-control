# CrowdSec

CrowdSec is deployed by the `crowdsec` role and enforced at HAProxy ALB through the HAProxy SPOA bouncer when both variables are enabled:

```yml
crowdsec_enabled: true
haproxy_alb_crowdsec_enabled: true
```

Many consuming repositories map both variables to a project toggle such as `gv_crowdsec_enabled`.

## What It Protects

- HTTP and HTTPS traffic that reaches HAProxy ALB.
- HAProxy request inspection through SPOE/SPOA.
- AppSec virtual patching and HTTP CVE rules installed through CrowdSec collections.
- HAProxy log scenarios from journald acquisition.

CrowdSec does not protect SSH, database, Redis, RabbitMQ, Docker overlay, or other non-HAProxy traffic unless a consuming repository adds another bouncer.

In consuming repositories, check the project-level CrowdSec toggle that maps into `crowdsec_enabled` and `haproxy_alb_crowdsec_enabled` for the current default. When that toggle is false, CrowdSec and the HAProxy ALB bouncer are not expected to block or protect traffic.

Apart from the HAProxy ALB bouncer and AppSec/WAF rules, the shared roles only install and configure the local CrowdSec engine, collections, parsers, acquisition, `cscli`, and the SPOA bouncer service. They do not add separate network firewall rules or bouncers for other protocols.

## Blocking Risk

CrowdSec can block legitimate clients if a real user shares an IP with abusive traffic, trips an HTTP scenario, or matches an AppSec rule. Enforcement is IP decision based at HAProxy ALB, so the practical impact is that requests from the decided IP can be denied until the decision expires or is deleted.

Before enabling it for production traffic, keep HAProxy logs visible, confirm the project toggle value, and be ready to inspect and delete decisions with `cscli`.

## Where to Check

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

## Unban

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

## Web UI

The shared role does not install a local web UI. Use `cscli` on the protected hosts by default.

CrowdSec Console can be enabled separately by enrolling machines, but that is a project-level operational decision because it introduces an external management surface.
