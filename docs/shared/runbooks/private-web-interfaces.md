# Private web interfaces

Consumer Taskfiles expose named cluster tasks for deployed private interfaces:

- `dockhand` forwards loopback port `3000` and opens `/`.
- `haproxy` forwards loopback port `8404` and opens `/_stats;norefresh`.
- `traefik` forwards loopback port `1080` and opens `/dashboard/`.
- `wg-easy` forwards loopback port `51821` and opens `/`.

Pass exactly one host selector after `--`. A two-digit selector expands through the task realm, platform, and cluster; an exact inventory hostname is also accepted:

```bash
task prd:ycl:app:traefik -- 01
task prd:ycl:app:traefik -- prd-ycl-app01
```

The launcher verifies that the selected host belongs to the cluster inventory, resolves the target and optional jump host from inventory plus `.env` and `.env.local`, refuses an occupied local port, and starts a foreground SSH local forward. It opens the browser only after the forward accepts connections. Ctrl-C stops the SSH process and removes its temporary SSH configuration.

Only use a service task exposed for that cluster. An unavailable service, invalid selector, missing SSH input, failed SSH connection, or failed local forward terminates with an explicit error.
