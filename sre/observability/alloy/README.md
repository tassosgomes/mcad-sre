# Grafana Alloy

Coletor compartilhado para receber OTLP das aplicações MCAD/ECAD, coletar logs
de containers Docker selecionados e encaminhar metrics, logs e traces para o
Grafana Cloud.

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

Para atualizar a configuracao do Alloy sem reutilizar um Docker config antigo,
crie um config versionado e aponte `MCAD_OBSERVABILITY_ALLOY_CONFIG` para ele:

```bash
docker config create mcad_observability_alloy_config_20260516_logs alloy/config.swarm.alloy
export MCAD_OBSERVABILITY_ALLOY_CONFIG=mcad_observability_alloy_config_20260516_logs
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

Para coletar logs de `stdout/stderr`, marque o container com labels de opt-in:

```yaml
labels:
  mcad.observability.logs: enabled
  mcad.observability.service_name: nome-do-servico
  mcad.observability.service_namespace: mcad
  mcad.observability.environment: prod
```

O Alloy precisa do Docker socket montado como leitura para descobrir containers
e ler logs. Por isso a stack roda no manager, usa `user: root` no container do
Alloy e monta `/var/run/docker.sock:/var/run/docker.sock:ro`.

## Valores que precisamos receber

- `GRAFANA_OTLP_ENDPOINT`
- `GRAFANA_LOKI_ENDPOINT`
- `GRAFANA_INSTANCE_ID` para OTLP Gateway
- `GRAFANA_LOKI_INSTANCE_ID` para Loki Basic Auth
- `GRAFANA_TOKEN` para Loki Basic Auth via env e para criar secret local/Swarm

No Swarm, o OTLP continua lendo o token pela Docker secret
`mcad_observability_grafana_token`. O Loki usa `GRAFANA_TOKEN` via variavel de
ambiente porque o endpoint direto de Loki exige o par Basic Auth recomendado na
documentacao do Grafana Cloud. Isso deixa o token visivel em
`docker service inspect`; trocar para uma secret separada de Loki e a opcao mais
segura quando quisermos endurecer essa configuracao.
