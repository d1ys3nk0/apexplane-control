# Loki

Explore labels:

```sh
curl -s "http://localhost:43100/loki/api/v1/labels" | jq
curl -s "http://localhost:43100/loki/api/v1/label/level/values" | jq .data
```

Query a service over a fixed range:

```sh
SERVICE="<service>"
START=$(date -u -d '72 hours ago' +%s)
END=$(date -u -d '71 hours ago' +%s)
curl -G 'http://localhost:43100/loki/api/v1/query_range' \
  --data-urlencode "query={service=\"$SERVICE\"}" \
  --data-urlencode "start=${START}000000000" \
  --data-urlencode "end=${END}000000000" \
  --data-urlencode "step=60s" \
  | jq
```

Keep labels and values minimal. High-cardinality labels make Loki expensive and harder to operate.
