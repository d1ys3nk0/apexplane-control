# Elastic

## Single Node Setup

Configure zero replicas for single-node installations:

```sh
curl -XPUT 'http://localhost:9200/_all/_settings' -H 'Content-Type: application/json' -d '{
  "index": {
    "number_of_replicas": 0
  }
}'

curl -fsS http://localhost:9200/_cluster/health | python3 -m json.tool
```

## Status

```sh
curl -fsS http://localhost:9200/_cat/health
curl -fsS http://localhost:9200/_cluster/health?pretty
curl -fsS http://localhost:9200/_nodes?pretty | less
curl -fsS http://localhost:9200/_nodes/stats?pretty | less
```
