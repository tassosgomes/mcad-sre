# Grafana Alloy

Coletor compartilhado para receber OTLP das aplicações MCAD/ECAD e encaminhar
metrics, logs e traces para o Grafana Cloud.

## Local

```bash
docker network create ecad-observability-net
cp .env.example .env
docker compose --env-file .env up -d
```

Aplicações em container na mesma rede usam:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

Aplicações rodando no host usam:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

## Docker Swarm

Criar rede externa uma vez:

```bash
docker network create -d overlay --attachable mcad-observability-net
```

Criar config e secret:

```bash
docker config create mcad_observability_alloy_config alloy/config.swarm.alloy
printf '%s' '<GRAFANA_TOKEN>' | docker secret create mcad_observability_grafana_token -
```

Deploy:

```bash
set -a && . ./.env.swarm && set +a
docker stack deploy -c docker-stack.yml mcad-observability
```

Servicos no Swarm devem entrar em `mcad-observability-net` e usar:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://mcad-observability-alloy:4318
```

## Valores que precisamos receber

- `GRAFANA_OTLP_ENDPOINT`
- `GRAFANA_INSTANCE_ID`
- `GRAFANA_TOKEN` para secret local/Swarm
