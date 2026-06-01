# docker_elastic

This role runs Elasticsearch in a standalone Docker container.

## Features
- Show Elastic memory limit.
- Create docker volumes.
- Start elastic container.
- Run extra single-node Elastic instances.
- Create extra elastic docker volume.
- Start extra elastic container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_elastic_ci_mode` | `<derived>` |
| `docker_elastic_debug_mode` | `<derived>` |
| `docker_elastic_nolog` | `<derived>` |
| `docker_elastic_mode` | `single` |
| `docker_elastic_env_common` | `&docker_elastic_env_common` |
| `docker_elastic_env_cluster_mode` | `<complex>` |
| `docker_elastic_env_single_mode` | `<complex>` |
| `docker_elastic_admin_pass` | `''` |
| `docker_elastic_cluster_nodes_group` | `''` |
| `docker_elastic_cluster_name` | `elastic` |
| `docker_elastic_extra_instances` | `[]` |
| `docker_elastic_image_name` | `elasticsearch` |
| `docker_elastic_image_tag` | `7.17.3` |
| `docker_elastic_image_full` | `<derived>` |
| `docker_elastic_data_volume` | `elastic-data` |
| `docker_elastic_mem_res` | `1000M` |
| `docker_elastic_mem_lim` | `1500M` |
| `docker_elastic_mem_swp` | `2000M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_elastic
```

## Operations
### Single Node Setup

Configure zero replicas for single-node installations:

```sh
curl -XPUT 'http://localhost:9200/_all/_settings' -H 'Content-Type: application/json' -d '{
  "index": {
    "number_of_replicas": 0
  }
}'

curl -fsS http://localhost:9200/_cluster/health | python3 -m json.tool
```

### Status

```sh
curl -fsS http://localhost:9200/_cat/health
curl -fsS http://localhost:9200/_cluster/health?pretty
curl -fsS http://localhost:9200/_nodes?pretty | less
curl -fsS http://localhost:9200/_nodes/stats?pretty | less
```
