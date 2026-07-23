# docker_swarm

This role initializes and joins Docker Swarm managers and workers.

## Features
- Configure Docker Swarm leader.
- Configure Docker Swarm manager.
- Configure Docker Swarm worker.
- Init a new swarm with default parameters.
- Collect Docker Swarm manager hosts.
- Store Docker Swarm leader host.
- Determine Docker Swarm leader IP to join cluster.
- Join as Docker Swarm {{ docker_swarm_join_role }}.
- Skip joining when the leader is outside the play limit and its join token is unavailable.
- Merge configured Docker Swarm node labels.

## Configuration
Set these required inputs before applying the role: `docker_swarm_cidr`, `docker_swarm_cluster_nodes_group`, `docker_swarm_mode`, `docker_swarm_vpc_cidr`.

| Variable | Default |
| --- | --- |
| `docker_swarm_advertise_ip` | `<derived>` |
| `docker_swarm_cidr` | `~` |
| `docker_swarm_cluster_nodes_group` | `~` |
| `docker_swarm_mode` | `~` |
| `docker_swarm_node_labels` | `{}` |
| `docker_swarm_vpc_addr` | `''` |
| `docker_swarm_vpc_cidr` | `~` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm
      vars:
        docker_swarm_cidr: <value>
        docker_swarm_cluster_nodes_group: <value>
        docker_swarm_mode: <value>
        docker_swarm_vpc_cidr: <value>
```
