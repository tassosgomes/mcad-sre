# Plano de observabilidade com Grafana Cloud

## Objetivo

Projetar uma estratégia única de observabilidade para os projetos `mcad`,
`ecad-authz` e `ecad-auditoria`, com foco em reduzir tempo de debug em
incidentes, correlacionar requisições entre serviços e tornar a configuração do
Grafana Cloud reprodutível.

O plano cobre:

- configuração do Grafana Cloud como código;
- topologia de coleta com Grafana Alloy;
- mudanças necessárias em aplicações Java/Spring Boot, .NET, Node/Fastify e
  frontends React;
- métricas, logs, traces, health checks, alertas, SLOs e sintéticos;
- decisões, motivações e sequência de implementação.

## Resumo executivo

A decisão principal é usar o Grafana Cloud como backend gerenciado para
métricas, logs e traces, manter as aplicações falando OpenTelemetry/OTLP e usar
Grafana Alloy como o limite operacional entre aplicações e Grafana Cloud.

Terraform deve ser usado para provisionar a parte de controle do Grafana:
folders, dashboards, alertas, notification policies, SLOs, sintéticos e, se
necessário, o próprio stack Grafana Cloud. A configuração sensível, como tokens
de ingestão, deve ficar fora do repositório e entrar por Docker Secret,
secret manager ou variáveis protegidas de CI.

O `ecad-authz` já tem a base mais madura: stack Alloy, envio OTLP para Grafana
Cloud e instrumentação Spring Boot com métricas, traces e logs. O plano é
centralizar esse padrão em `sre`, evoluir o Alloy para capturar também logs de
containers e métricas de infraestrutura, e replicar a instrumentação nas demais
aplicações.

## Inventário atual

### `ecad-authz`

Componentes relevantes:

- backend Spring Boot multi-módulo (`authz-bootstrap`, `authz-api`,
  `authz-infra`, `authz-domain`);
- frontend pnpm/Vite/module federation;
- Postgres, Redis, Keycloak local e RabbitMQ;
- stack de observabilidade em `ecad-authz/infra/observability`;
- stack de produção em Docker Swarm já conectando `mcad-authz-api` à rede
  `mcad-observability-net`.

Estado de observabilidade:

- já existe Alloy recebendo OTLP em `4317` e `4318` e enviando para Grafana
  Cloud;
- `authz-bootstrap` já usa Actuator, Prometheus, Micrometer OTLP,
  Micrometer Tracing, exporter OTLP e appender Logback OpenTelemetry;
- `application.yaml` já define `service.name`, `service.namespace`,
  `service.version`, `deployment.environment` e endpoints OTLP;
- há métricas de domínio importantes, como decisão de autorização, cache e
  outbox;
- frontend possui o pacote `@ecad/observability` com OpenTelemetry Web,
  Web Vitals e captura de erro.

Lacunas:

- a stack Alloy atual só cobre OTLP; ainda não coleta logs de containers,
  métricas de host/container nem exporters de dependências;
- a configuração fica dentro do repositório `ecad-authz`, mas deve virar
  plataforma compartilhada em `sre`;
- o `sample-pilot` tem Actuator/Prometheus, mas não está no mesmo padrão OTLP
  completo do `authz-bootstrap`.

### `mcad`

Componentes relevantes:

- `frontend`: React/Vite;
- `services/bff`: Fastify, proxy para APIs e authz;
- `services/ai-orchestrator`: Fastify + Mastra/OpenAI;
- `services/identity-sync-api`: Fastify + RabbitMQ;
- `services/cadastro-api`: .NET 8 + EF Core + Postgres + RabbitMQ;
- `services/identificacao-api`: .NET 8 + EF Core + Postgres + RabbitMQ +
  S3/MinIO/R2;
- `services/arrecadacao-api`: Spring Boot + Postgres + RabbitMQ + Redis +
  SDKs AuthZ/Auditoria;
- `services/distribuicao-api`: Spring Boot + Postgres + RabbitMQ +
  integração com Cadastro;
- infra local e produção via Docker Compose/Swarm.

Estado de observabilidade:

- .NET APIs expõem `/health`, mas não têm OpenTelemetry, métricas de runtime,
  logs estruturados padronizados nem readiness separado;
- Spring APIs usam Actuator, mas `arrecadacao-api` só expõe `health,info` e
  `distribuicao-api` expõe `health,info,metrics`; nenhuma segue ainda o padrão
  OTLP do AuthZ;
- há métricas Micrometer customizadas em Arrecadação e Distribuição, mas elas
  não chegam ao Grafana Cloud sem scrape/export;
- BFF e Identity Sync têm health checks e logs Fastify, mas não têm OTel,
  métricas Prometheus/OTLP nem propagação padronizada de trace;
- AI Orchestrator tem `/metrics`, mas hoje é um snapshot JSON em memória, não
  um endpoint Prometheus nem OTLP;
- frontend MCAD não usa o pacote de observabilidade existente no `ecad-authz`.

Lacunas:

- `mcad/docker-stack.yml` não conecta os serviços à rede
  `mcad-observability-net`;
- não há endpoint comum de OTLP para os serviços em produção;
- faltam logs correlacionáveis com `trace_id`, `span_id` e `correlation_id`;
- faltam alertas e SLOs orientados a jornadas reais.

### `ecad-auditoria`

Componentes relevantes:

- `audit-service`: Spring Boot + Oracle + RabbitMQ + relatórios assíncronos;
- SDK Java e .NET para produtores de eventos de auditoria com transactional
  outbox;
- `demo-backend` e `demo-frontend`;
- Docker Compose local e stack Swarm para o `audit-service`.

Estado de observabilidade:

- `audit-service` expõe Actuator com `health,info,metrics,prometheus`;
- logs do `audit-service` usam formato estruturado ECS no console;
- healthcheck de Swarm usa `/actuator/health/readiness`;
- documentação técnica já menciona observabilidade, Actuator, métricas e
  tracing como requisito.

Lacunas:

- `audit-service` ainda não envia traces, logs e métricas por OTLP;
- a stack Swarm de auditoria não entra na rede `mcad-observability-net`;
- faltam métricas de negócio para ingestão, DLQ, deduplicação, geração de PDF,
  jobs pendentes e atrasos de outbox;
- SDKs de produtores devem carregar `traceId`/`correlationId` no evento para
  permitir navegar de uma ação de usuário para o evento de auditoria.

## Decisões arquiteturais

### 1. Grafana Cloud como backend gerenciado

Decisão: usar Grafana Cloud para Mimir, Loki, Tempo, dashboards, alerting,
SLOs e Synthetic Monitoring.

Motivação:

- evita operar Prometheus, Loki e Tempo localmente em produção;
- reduz carga operacional e risco de perda de dados por storage mal
  dimensionado;
- permite começar com recursos gerenciados e manter portabilidade via
  OpenTelemetry e Terraform.

### 2. Terraform para plano de controle

Decisão: provisionar Grafana Cloud com Terraform em `sre/terraform/grafana-cloud`.

Motivação:

- dashboards, alertas e notification policies precisam ser versionados;
- facilita revisão de mudanças críticas em alertas;
- reduz drift entre ambientes;
- permite recriar folders, dashboards e SLOs em outro stack, caso necessário.

Recomendação prática:

- se o stack Grafana Cloud já existe, Terraform deve inicialmente gerenciar
  somente recursos dentro do stack;
- criar o stack via Terraform apenas se houver token de Cloud Portal com escopo
  adequado e decisão explícita de gerir a conta inteira por IaC;
- armazenar state em backend remoto com criptografia. Não commitar state local.

### 3. Grafana Alloy como coletor compartilhado

Decisão: manter aplicações enviando OTLP para Alloy; Alloy autentica e envia ao
Grafana Cloud.

Motivação:

- aplicações não precisam carregar token do Grafana Cloud;
- Alloy permite batching, retry, enriquecimento de atributos, sampling,
  redaction e roteamento;
- é o caminho recomendado para produção em vez de cada app enviar diretamente
  ao endpoint Cloud;
- simplifica futura migração para Kubernetes, onde Alloy vira DaemonSet ou
  Deployment.

O Alloy atual em `ecad-authz` deve virar base para `sre/observability/alloy`.
Na primeira fase ele pode continuar single replica, mas o alvo de produção é
rodar Alloy em modo global por host no Swarm para coletar logs e métricas de
containers de forma local.

### 4. OTLP como contrato principal

Decisão: todas as aplicações devem emitir traces, métricas e logs via
OpenTelemetry/OTLP quando possível.

Motivação:

- evita acoplamento forte a Grafana;
- padroniza Java, .NET, Node e frontend;
- permite correlação nativa entre serviço, log e trace;
- reduz a necessidade de múltiplos exporters por runtime.

Prometheus scrape continua válido como fallback para Actuator, RabbitMQ,
Postgres, Redis e outros exporters, mas o contrato novo para aplicações deve
ser OTLP.

### 5. Logs estruturados em stdout

Decisão: toda aplicação deve logar JSON estruturado em stdout/stderr, com
campos de correlação e sem PII sensível.

Motivação:

- Docker/Swarm já centraliza stdout/stderr dos containers;
- Alloy pode coletar logs via Docker e enviar ao Loki;
- logs continuam úteis mesmo quando o appender OTLP falha;
- correlação com traces melhora o debug sem exigir busca textual manual.

Campos mínimos:

- `timestamp`
- `level`
- `service.name` ou `service`
- `deployment.environment`
- `trace_id`
- `span_id`
- `correlation_id` ou `x_mcad_request_id`
- `user_id_hash` quando necessário, nunca e-mail/CPF/token bruto
- `http.method`, `http.route`, `http.status_code`
- `error.type`, `error.message`

### 6. Baixa cardinalidade por padrão

Decisão: labels de métrica devem ser controladas e documentadas.

Motivação:

- Mimir/Grafana Cloud cobra e opera melhor com cardinalidade previsível;
- `user_id`, `email`, `documento`, `request_id`, `trace_id`, IDs de entidade e
  mensagens de erro não devem virar labels;
- esses valores podem aparecer como atributos de span ou campos de log
  redigidos, não como séries temporais.

Labels permitidos por padrão:

- `service.name`
- `service.namespace`
- `deployment.environment`
- `operation`
- `http.route`
- `http.method`
- `http.status_code` ou classe `2xx/4xx/5xx`
- `upstream`
- `queue`
- `status`
- `error.type` com enum controlado

### 7. Sampling explícito

Decisão: sampling deve ser configurado por ambiente.

Motivação:

- em dev/hml, coletar 100% de traces ajuda validação;
- em prod, 10% pode ser suficiente para tráfego normal, com 100% para erros;
- sampling no Alloy permite política central sem recompilar apps.

Fase inicial:

- `dev`: `OTEL_TRACES_SAMPLER_ARG=1.0`;
- `hml`: `0.5`;
- `prod`: `0.1`, mantendo todos os spans de erro quando tail sampling for
  habilitado no Alloy.

### 8. SLOs e sintéticos baseados em jornada

Decisão: alertas críticos devem medir jornadas e sintomas, não só causas.

Motivação:

- CPU alta raramente diz ao time o impacto do usuário;
- sintéticos detectam indisponibilidade de DNS/TLS/Traefik/app antes de o
  usuário abrir chamado;
- SLOs dão linguagem comum para disponibilidade, latência e burn rate.

## Arquitetura alvo

```text
Browser / Jobs / APIs
  |
  | traceparent + x-mcad-request-id
  v
Frontend -> BFF -> APIs Java/.NET/Node -> Postgres/RabbitMQ/Oracle/Redis/S3
             |           |                     |
             |           | OTLP                | exporters / scrape
             v           v                     v
          Grafana Alloy compartilhado no Swarm
             |
             | OTLP HTTPS + Basic Auth / Loki / Mimir
             v
        Grafana Cloud: Metrics + Logs + Traces + Dashboards + Alerting + SLO
```

Em produção Swarm:

- uma stack `mcad-observability` central, versionada em `sre`;
- rede overlay externa `mcad-observability-net`;
- serviços Java/.NET/Node conectados à rede e apontando para Alloy;
- token do Grafana Cloud em Docker Secret;
- configs do Alloy em Docker Config;
- Alloy com acesso controlado ao Docker socket para logs/containers;
- UI do Alloy sem exposição pública; acesso apenas para debug operacional.

## Estrutura recomendada em `sre`

```text
sre/
  plano-observabilidade-grafana-cloud.md
  terraform/
    grafana-cloud/
      versions.tf
      providers.tf
      variables.tf
      folders.tf
      contact-points.tf
      notification-policies.tf
      dashboards.tf
      alerts.tf
      slos.tf
      synthetics.tf
      dashboards/
        service-overview.json
        authz.json
        audit-service.json
        node-services.json
        dotnet-services.json
        infra-swarm.json
  observability/
    alloy/
      config.local.alloy
      config.swarm.alloy
      docker-compose.yml
      docker-stack.yml
      README.md
  runbooks/
    api-error-rate.md
    queue-backlog.md
    audit-ingestion.md
    authz-deny-spike.md
    otel-pipeline.md
```

## Terraform no Grafana Cloud

### Providers

Usar o provider oficial `grafana/grafana`.

Dois modos devem ser suportados:

1. **Stack existente**: receber `grafana_url` e `grafana_service_account_token`
   por variável sensível e gerenciar recursos dentro do Grafana.
2. **Stack gerenciado por Terraform**: usar Cloud Access Policy Token para
   criar stack e service account token. Esse modo exige mais governança e deve
   ser adotado depois do baseline.

Variáveis sensíveis:

- `GRAFANA_CLOUD_ACCESS_POLICY_TOKEN`
- `GRAFANA_AUTH`
- `GRAFANA_SM_ACCESS_TOKEN` para Synthetic Monitoring, se usado por Terraform
- webhooks de Slack/Teams/PagerDuty/IRM

Nenhuma delas deve ficar em `.tfvars` commitado.

### Remote state no Cloudflare R2

Decisão: usar Cloudflare R2 como backend remoto do Terraform é viável para este
repositório.

Motivação:

- R2 expõe API S3-compatible, então o backend `s3` do Terraform consegue gravar
  o state sem depender de AWS S3;
- centraliza o state fora do repositório Git, evitando commitar dados sensíveis;
- R2 suporta versionamento de objetos, importante para recuperar state em caso
  de erro humano;
- o backend `s3` atual do Terraform suporta lock via arquivo com
  `use_lockfile = true`, evitando a dependência antiga de DynamoDB para locking.

Requisitos operacionais:

- bucket R2 dedicado para state, por exemplo `mcad-terraform-state`;
- Object Versioning habilitado no bucket;
- Access Key R2 específica para Terraform, com permissão mínima no bucket de
  state;
- credenciais injetadas via variáveis protegidas de CI/local shell, nunca no
  arquivo `backend.tf`;
- um `key` por stack/ambiente, por exemplo
  `grafana-cloud/prod/terraform.tfstate`.

Exemplo de backend:

```hcl
terraform {
  backend "s3" {
    bucket = "mcad-terraform-state"
    key    = "grafana-cloud/prod/terraform.tfstate"
    region = "auto"

    endpoints = {
      s3 = "https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com"
    }

    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
```

Credenciais recomendadas na execução:

```bash
export AWS_ACCESS_KEY_ID="<R2_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<R2_SECRET_ACCESS_KEY>"
terraform init -reconfigure
```

Observação: `use_lockfile = true` cria um objeto `.tflock` ao lado do state. A
chave R2 precisa conseguir ler, criar e apagar esse lock file.

### Folders

Criar folders por domínio operacional:

- `MCAD / Overview`
- `MCAD / Services`
- `MCAD / Infra`
- `ECAD AuthZ`
- `ECAD Auditoria`
- `SLOs`
- `Synthetic Monitoring`

Motivação: separar ownership e reduzir ruído. Debug de serviço, debug de
infra e acompanhamento executivo de SLO não devem competir no mesmo dashboard.

### Dashboards iniciais

1. **Service Overview**
   - RED: request rate, error rate, duration p50/p95/p99;
   - saturação de threads/event loop/conexões;
   - logs recentes por severidade;
   - traces exemplares por erro e latência alta.

2. **MCAD APIs**
   - Cadastro, Identificação, Arrecadação, Distribuição;
   - latência por rota;
   - taxa de erro por rota;
   - dependências: Postgres, RabbitMQ, AuthZ, Audit, S3/MinIO/R2;
   - outbox pendente e falhas de publicação.

3. **BFF e Node Services**
   - latência por upstream;
   - erros por upstream;
   - event loop lag, heap, GC, handles;
   - status de readiness;
   - AI tool calls, workflow runs, OpenAI/provider failures.

4. **AuthZ**
   - decisões allowed/denied;
   - latência hit/miss;
   - cache hit ratio;
   - Redis;
   - outbox;
   - erros de validação JWT/JWKS/issuer.

5. **Auditoria**
   - ingestão HTTP/AMQP;
   - duplicados;
   - DLQ;
   - relatórios pendentes/running/failed;
   - duração de geração de PDF;
   - Oracle pool e query latency.

6. **Infra Swarm**
   - container restarts;
   - CPU/memória por serviço;
   - uso de disco por host;
   - rede;
   - Alloy pipeline health;
   - Traefik 4xx/5xx, TLS e upstream failures.

### Alertas

Gerenciar alertas com `grafana_rule_group`.

Labels obrigatórias:

- `team`
- `service`
- `severity`
- `environment`
- `runbook_url`

Severidades:

- `critical`: impacto direto no usuário ou perda de dados;
- `warning`: degradação relevante ou risco crescente;
- `info`: diagnóstico ou anomalia sem ação imediata.

Alertas iniciais:

- **SyntheticDownCritical**: rota pública crítica falhando por 3 checks.
- **High5xxRate**: erro 5xx acima de 2% por 10 min em API pública.
- **HighLatencyP95**: p95 acima do orçamento por 10 min.
- **ServiceNoTelemetry**: serviço sem métricas/logs/traces por 10 min.
- **ContainerRestartLoop**: restarts recorrentes no Swarm.
- **AlloyExporterFailures**: falhas de envio ao Grafana Cloud.
- **PostgresConnectionsHigh**: uso de conexões acima de 80%.
- **RabbitQueueBacklog**: fila com backlog acima do threshold do domínio.
- **RabbitDLQNonZero**: DLQ com mensagens novas.
- **AuditIngestionFailures**: falhas de ingestão ou deduplicação anormal.
- **OutboxOldestEventTooOld**: evento mais antigo pendente acima do limite.
- **AuthzDenySpike**: aumento abrupto de denies não explicado por deploy.
- **AIProviderUnavailable**: AI Orchestrator sem provider configurado ou
  upstream retornando erro.

Motivação: alertar sintomas primeiro, causas depois. Um alerta de fila só é
critical se ameaça SLO ou perda de dados; caso contrário começa como warning.

### Notification policies

Definir uma política raiz com agrupamento por:

- `environment`
- `team`
- `service`
- `severity`

Rotas sugeridas:

- `critical`: canal de incidente/on-call;
- `warning`: canal do time dono;
- `info`: canal de observabilidade ou somente dashboard.

Adicionar mute timings para janelas de manutenção conhecidas e labels de
deploy quando houver rollout planejado.

### SLOs

Provisionar com `grafana_slo` quando o plugin SLO estiver disponível no stack.

SLOs iniciais:

- **MCAD Frontend disponibilidade**: 99.5% mensal para carregamento e rotas
  principais via sintético.
- **BFF disponibilidade**: 99.9% mensal em `/health/ready` e rotas `/api/*`.
- **APIs core**: 99.9% mensal para Cadastro, Identificação, Arrecadação e
  Distribuição.
- **AuthZ decisão**: 99.9% das decisões com resposta válida e p95 abaixo do
  limite definido pelo produto.
- **Auditoria ingestão**: 99.9% dos eventos aceitos ou marcados como duplicados
  sem erro de persistência.
- **Identity Sync**: 99.5% de webhooks aceitos/publicados.
- **AI Orchestrator**: 99.0% para endpoints próprios, separado de falhas do
  provedor externo.

Motivação: separar disponibilidade própria de dependências externas evita
penalizar o serviço errado e melhora priorização de incidentes.

### Synthetic Monitoring

Provisionar checks com Terraform para:

- `https://mcad.tasso.dev.br`;
- BFF `/health/ready`;
- Cadastro `/health`;
- Identificação `/health`;
- Arrecadação `/actuator/health/readiness`;
- Distribuição `/actuator/health/readiness` depois de habilitado;
- AuthZ `/actuator/health/readiness`;
- Audit Service `/actuator/health/readiness`;
- fluxos autenticados sintéticos em uma fase posterior, com usuário técnico e
  cuidado de segredo.

Motivação: sintéticos cobrem DNS, TLS, Traefik, roteamento e disponibilidade
externa, que métricas internas não veem.

## Grafana Alloy

### Baseline atual

O `ecad-authz/infra/observability/alloy/config.swarm.alloy` já recebe OTLP
gRPC/HTTP, faz batch e exporta para o endpoint OTLP do Grafana Cloud usando
Basic Auth com token em Docker Secret. Esse desenho deve ser mantido.

### Evolução recomendada

Adicionar ao Alloy central:

- `otelcol.processor.resourcedetection` para preencher `host.name` e atributos
  de ambiente;
- `otelcol.processor.memory_limiter` para proteger o coletor;
- `otelcol.processor.batch` separado por sinal quando necessário;
- `otelcol.processor.transform` para:
  - copiar `deployment.environment` e `service.version` para métricas;
  - remover atributos de alta cardinalidade;
  - redigir atributos sensíveis;
- `loki.source.docker` para logs de containers;
- `prometheus.exporter.cadvisor` para métricas de containers Linux;
- `prometheus.exporter.postgres` para Postgres local;
- scrape do RabbitMQ via plugin `rabbitmq_prometheus` quando disponível;
- scrape/export de Redis;
- blackbox checks internos quando sintéticos externos não bastarem;
- métricas do próprio Alloy e alertas de pipeline.

Para CloudAMQP, preferir métricas nativas/API do provedor ou habilitar endpoint
Prometheus, se o plano permitir. Se isso não for possível, compensar com
métricas das aplicações consumidoras/produtoras: publish failures, backlog
observado, DLQ, retry e idade do evento mais antigo.

### Segurança

- Não expor `4317`, `4318` e `12345` publicamente em produção.
- Browser nunca deve receber token do Grafana Cloud.
- Token de ingestão deve ter escopos mínimos: `metrics:write`, `logs:write`,
  `traces:write`.
- Usar Docker Secret ou secret manager; nunca `.env` commitado.
- Restringir leitura do Docker socket ao Alloy e considerar um socket proxy
  read-only se a superfície de risco for inaceitável.

## Configurações comuns nas aplicações

### Variáveis padrão

Todas as aplicações backend devem aceitar:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://mcad-observability-alloy:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_SERVICE_NAME=<nome-do-servico>
OTEL_RESOURCE_ATTRIBUTES=service.namespace=mcad,deployment.environment=<env>,service.version=<versao>
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

Para Spring Boot que usa `management.otlp.*`, manter compatibilidade com o
padrão já usado no AuthZ:

```text
management.otlp.tracing.endpoint=${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces
management.otlp.metrics.export.url=${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/metrics
management.otlp.logging.endpoint=${OTEL_EXPORTER_OTLP_ENDPOINT}/v1/logs
```

### Propagação

Padronizar:

- aceitar e propagar W3C `traceparent` e `tracestate`;
- aceitar e propagar `x-mcad-request-id`;
- gerar `x-mcad-request-id` no BFF se ausente;
- gravar esse ID em logs, spans e respostas;
- incluir `traceId`/`correlationId` nos eventos de auditoria.

Motivação: durante debug, o operador deve conseguir sair de um erro do
frontend para o BFF, API, evento RabbitMQ, auditoria e logs da dependência.

### Health checks

Padronizar endpoints:

- `liveness`: processo vivo, sem checar dependências externas;
- `readiness`: dependências mínimas para receber tráfego;
- `startup`: opcional para apps com migração demorada.

Spring:

- `/actuator/health/liveness`
- `/actuator/health/readiness`

.NET e Node:

- `/health/live`
- `/health/ready`

Motivação: liveness não deve reiniciar processo por falha temporária de
Postgres/RabbitMQ; readiness deve tirar o serviço do tráfego quando ele não
consegue operar.

## Plano por tecnologia

### Spring Boot

Aplicações:

- `ecad-authz/backend/authz-bootstrap` (já avançado);
- `mcad/services/arrecadacao-api`;
- `mcad/services/distribuicao-api`;
- `ecad-auditoria/audit-service`;
- `ecad-auditoria/demo-backend`;
- `ecad-authz/backend/sample-pilot`.

Implementação:

- replicar o padrão do `authz-bootstrap`;
- adicionar `micrometer-registry-otlp`, `micrometer-tracing-bridge-otel` e
  `opentelemetry-exporter-otlp`;
- manter `micrometer-registry-prometheus` como fallback e debug local;
- adicionar appender OTel para logs ou garantir JSON stdout com `traceId` e
  `spanId`;
- expor `health,info,metrics,prometheus`;
- configurar `management.opentelemetry.resource-attributes`;
- publicar histogramas de HTTP, DB e chamadas externas;
- adicionar métricas de domínio onde faltam.

Métricas específicas:

- Arrecadação:
  - outbox pending/failed/oldest age;
  - eventos RabbitMQ publicados/falhados;
  - latência de decisão AuthZ;
  - redis cache hit/miss;
  - fluxo de verba/licença/pagamento por status.
- Distribuição:
  - duração de cálculo;
  - falhas por etapa;
  - latência de consulta ao Cadastro;
  - consumo de eventos de Arrecadação;
  - eventos rejeitados/DLQ.
- Auditoria:
  - eventos ingeridos por canal HTTP/AMQP;
  - duplicados;
  - falhas de validação;
  - DLQ;
  - jobs de relatório por status;
  - duração de PDF;
  - tamanho e idade da fila de jobs.

### .NET 8

Aplicações:

- `mcad/services/cadastro-api`;
- `mcad/services/identificacao-api`;
- SDKs .NET de AuthZ/Auditoria como propagadores de contexto.

Implementação:

- adicionar OpenTelemetry para ASP.NET Core, HttpClient, EF Core, Runtime e
  Process;
- exportar traces, metrics e logs via OTLP para Alloy;
- usar logs JSON estruturados com `trace_id`, `span_id` e `correlation_id`;
- separar `/health/live` e `/health/ready`;
- readiness deve validar Postgres, RabbitMQ e S3/MinIO/R2 quando aplicável;
- instrumentar hosted services de outbox e consumidores RabbitMQ;
- propagar `traceparent` em chamadas HTTP e mensagens RabbitMQ.

Métricas específicas:

- Cadastro:
  - operações CRUD por entidade;
  - chamadas ISWC por resultado;
  - outbox pendente/falha;
  - RabbitMQ publish failures;
  - EF Core query duration.
- Identificação:
  - upload/processamento CSV;
  - pendências detectadas;
  - chamadas ao Cadastro;
  - storage S3/MinIO/R2 latency/error;
  - outbox e consumidores RabbitMQ.

### Node/Fastify

Aplicações:

- `mcad/services/bff`;
- `mcad/services/identity-sync-api`;
- `mcad/services/ai-orchestrator`.

Implementação:

- adicionar OpenTelemetry SDK Node;
- instrumentar Fastify/HTTP/fetch;
- exportar OTLP para Alloy;
- usar logger JSON com redaction;
- incluir `trace_id`, `span_id`, `request_id`, `upstream`, `route`,
  `status_code`;
- expor `/health/live` e `/health/ready`;
- instrumentar RabbitMQ no Identity Sync;
- converter `/metrics` do AI Orchestrator para Prometheus ou OTLP metrics.

Métricas específicas:

- BFF:
  - latência por upstream;
  - erro por upstream;
  - cache `/api/me` hit/miss;
  - renovação de token/401;
  - request body limit rejections.
- Identity Sync:
  - webhooks recebidos/ignorados/rejeitados;
  - falhas de assinatura;
  - eventos publicados no RabbitMQ;
  - backfill de usuários;
  - estado da conexão RabbitMQ.
- AI Orchestrator:
  - requests de chat;
  - latência de chat;
  - tool calls por ferramenta/status;
  - workflows por status;
  - authz denied;
  - erros de provider OpenAI;
  - tokens/custo se disponível pela camada de SDK.

### Frontend React

Aplicações:

- `mcad/frontend`;
- `ecad-authz/frontend/apps/shell` e MFEs.

Implementação:

- para AuthZ frontend, manter `@ecad/observability` e revisar endpoint de
  produção;
- para MCAD frontend, reutilizar o pacote `@ecad/observability` ou extrair uma
  biblioteca comum;
- coletar Web Vitals, erros não tratados, rejeições de Promise e traces de
  fetch;
- propagar `traceparent` e `x-mcad-request-id` em chamadas ao BFF/APIs;
- adicionar configuração runtime `OTLP`/Faro sem rebuild da imagem;
- não enviar OTLP direto para um Alloy público sem autenticação/rate limit.

Opções de ingestão frontend:

1. **Grafana Faro / Frontend Observability**: recomendado para RUM no Grafana
   Cloud, com SDK próprio para browser e produto gerenciado.
2. **Endpoint proxy no BFF**: browser envia spans/eventos ao BFF, que valida
   origem, aplica rate limit e encaminha ao Alloy.
3. **Alloy público com CORS restrito**: somente se houver autenticação,
   allowlist, rate limit e isolamento. Evitar como primeira opção.

Motivação: o browser é ambiente não confiável. Nenhum segredo de Grafana Cloud
deve chegar ao cliente.

## Alterações nos stacks

### `ecad-authz`

- migrar `infra/observability` para `sre/observability` ou manter temporariamente
  e declarar `sre` como fonte futura;
- manter `mcad-authz-api` conectado a `mcad-observability-net`;
- adicionar dashboards/alerts Terraform;
- adicionar collection de logs Docker no Alloy central.

### `mcad`

Em `mcad/docker-stack.yml`:

- declarar rede externa `mcad-observability-net`;
- conectar `mcad-cadastro-api`, `mcad-identificacao-api`,
  `mcad-arrecadacao-api`, `mcad-distribuicao-api`, `mcad-bff` e
  `mcad-identity-sync-api`;
- adicionar env vars OTEL por serviço;
- adicionar healthchecks para APIs .NET e Spring que ainda não têm;
- adicionar `AI_ORCHESTRATOR` no stack de produção se ele for parte do produto
  em produção; hoje aparece no compose dev, mas não no stack Swarm.

Em `docker-compose.dev.yml`:

- usar `ecad-observability-net` externa, igual ao AuthZ;
- serviços em container usam `http://alloy:4318`;
- serviços rodando no host usam `http://localhost:4318`.

### `ecad-auditoria`

Em `ecad-auditoria/infra/swarm/audit-service-stack.yml`:

- conectar `audit-service` à rede `mcad-observability-net`;
- adicionar `OTEL_EXPORTER_OTLP_ENDPOINT`;
- adicionar `OTEL_SERVICE_NAME=audit-service`;
- adicionar `OTEL_RESOURCE_ATTRIBUTES=service.namespace=ecad-auditoria,...`;
- manter `AUDIT_DB_PASSWORD_FILE` e `RABBITMQ_PASSWORD_FILE` como secrets;
- avaliar métrica/health do Oracle e scraping por exporter separado.

## Dashboards e consultas de debug

Cada dashboard de serviço deve responder rapidamente:

- o serviço está recebendo tráfego?
- o erro é generalizado ou de uma rota/upstream?
- começou depois de deploy?
- há aumento de latência antes do erro?
- há fila acumulando?
- há logs com o mesmo `trace_id`?
- o trace mostra gargalo em DB, RabbitMQ, AuthZ, Audit, S3 ou provider externo?

Links úteis dentro dos dashboards:

- do painel de erro para logs filtrados por `service.name` e `trace_id`;
- do painel de latência para traces exemplares;
- do painel de fila para runbook de backlog;
- do alerta para runbook.

## Runbooks mínimos

Criar em `sre/runbooks`:

- `otel-pipeline.md`: como validar app -> Alloy -> Grafana Cloud;
- `api-error-rate.md`: triagem de 5xx por rota/upstream/deploy;
- `queue-backlog.md`: triagem RabbitMQ/outbox/DLQ;
- `audit-ingestion.md`: triagem de eventos de auditoria e relatórios;
- `authz-deny-spike.md`: triagem de aumento de denies;
- `frontend-errors.md`: triagem RUM/Web Vitals;
- `database-saturation.md`: Postgres/Oracle pool, conexões e queries lentas.

## Plano de implementação

### Fase 0 - Baseline e ownership

1. Definir ambientes (`dev`, `hml`, `prod`) e naming padrão.
2. Definir donos por serviço e canal de alerta.
3. Criar `sre/terraform/grafana-cloud` e `sre/observability/alloy`.
4. Decidir se Terraform vai gerir stack existente ou criar novo stack.
5. Criar secrets fora do repo:
   - token Cloud Access Policy para Terraform;
   - service account token Grafana;
   - token de ingestão OTLP;
   - token Synthetic Monitoring, se aplicável.

Critério de aceite:

- `terraform plan` roda sem segredo commitado;
- Alloy local sobe e recebe OTLP;
- runbook `otel-pipeline.md` existe.

### Fase 1 - Centralizar Alloy

1. Copiar e adaptar a stack Alloy do `ecad-authz` para `sre`.
2. Adicionar resourcedetection, memory limiter, transform e batch.
3. Adicionar coleta de logs Docker.
4. Adicionar métricas do próprio Alloy.
5. Subir stack central em Swarm usando Docker Secret/Config.
6. Manter compatibilidade com `mcad-observability-net`.

Critério de aceite:

- `ecad-authz` continua enviando métricas/traces/logs;
- logs de containers chegam ao Loki com labels `service`, `environment` e
  `container`;
- existe alerta para falha de export do Alloy.

### Fase 2 - Terraform Grafana Cloud

1. Provisionar folders.
2. Provisionar contact points e notification policy.
3. Importar ou criar dashboards baseline.
4. Criar alertas mínimos de sintoma.
5. Criar checks sintéticos públicos.
6. Criar primeiros SLOs.

Critério de aceite:

- dashboards aparecem no Grafana sem criação manual;
- um alerta de teste chega ao canal correto;
- sintéticos cobrem frontend, BFF e APIs críticas.

### Fase 3 - Instrumentar `mcad` backend

1. `.NET`: Cadastro e Identificação com OTel, logs JSON e readiness.
2. `Spring`: Arrecadação e Distribuição no padrão AuthZ.
3. `Node`: BFF, Identity Sync e AI Orchestrator com OTel e métricas reais.
4. Conectar todos os serviços backend à rede de observabilidade.
5. Adicionar métricas de domínio e outbox.

Critério de aceite:

- cada serviço aparece em Application Observability;
- uma chamada frontend -> BFF -> API mantém o mesmo trace;
- dashboards mostram RED por serviço;
- logs têm `trace_id` pesquisável.

### Fase 4 - Auditoria

1. Instrumentar `audit-service` com OTel tracing/metrics/logs.
2. Adicionar métricas de ingestão, DLQ, dedup e relatórios.
3. Conectar stack Swarm à rede de observabilidade.
4. Propagar trace/correlation nos SDKs Java/.NET de produtores.
5. Criar dashboard e alertas específicos.

Critério de aceite:

- evento produzido em serviço MCAD pode ser ligado ao evento de auditoria;
- DLQ e falhas de relatório geram alerta;
- dashboard de auditoria responde ingestão, persistência e PDF.

### Fase 5 - Frontend e jornada

1. Instrumentar `mcad/frontend`.
2. Revisar AuthZ frontend e MFEs.
3. Escolher Faro ou proxy BFF para ingestão frontend.
4. Propagar `traceparent` e `x-mcad-request-id`.
5. Criar dashboards de Web Vitals, erros JS e jornadas.

Critério de aceite:

- erro JS vira evento visível no Grafana;
- Web Vitals aparecem por ambiente;
- requisição de browser é correlacionável com trace backend.

### Fase 6 - Maturidade

1. Tail sampling central no Alloy.
2. SLO burn rate alerts.
3. Dashboards por jornada de negócio.
4. Métricas de custo/volume de telemetria.
5. Revisão mensal de cardinalidade e alert fatigue.
6. Game day de incidente usando somente Grafana + runbooks.

Critério de aceite:

- alertas críticos têm runbook e owner;
- SLOs orientam priorização;
- volume de logs/traces está dentro do orçamento.

## Ordem recomendada

1. Não começar por todos os dashboards. Primeiro garantir pipeline app -> Alloy
   -> Grafana Cloud.
2. Usar o `ecad-authz` como referência porque já tem o padrão mais completo.
3. Instrumentar BFF cedo, pois ele é o ponto de entrada e ajuda a correlacionar
   a jornada inteira.
4. Instrumentar .NET e Spring core antes de frontend avançado.
5. Só depois criar SLOs finais; antes disso, usar SLOs preliminares para
   calibrar thresholds.

## Riscos e mitigação

### Cardinalidade alta

Risco: custo e queries lentas por labels com IDs dinâmicos.

Mitigação: revisar todos os labels customizados, mover IDs para logs/spans e
usar allowlist no Alloy.

### PII em logs/traces

Risco: e-mail, CPF, token ou payload sensível ir para Grafana Cloud.

Mitigação: redaction nos loggers, atributos bloqueados no Alloy e testes de
sanitização. O padrão do AuthZ de mascarar e-mails deve ser replicado.

### Falha do coletor

Risco: perda temporária de telemetria.

Mitigação: Alloy com batching, retries, persistent queue quando necessário,
alertas de pipeline e HA/global mode.

### Browser enviando telemetria sem controle

Risco: endpoint público vira vetor de abuso.

Mitigação: preferir Faro gerenciado ou proxy BFF com CORS, rate limit e
validação.

### Alert fatigue

Risco: muitos alertas sem ação clara.

Mitigação: começar com poucos alertas de sintoma, exigir runbook e owner, e
revisar semanalmente nas primeiras semanas.

## Referências oficiais

- Grafana Cloud OTLP endpoint:
  https://grafana.com/docs/grafana-cloud/send-data/otlp/send-data-otlp/
- Grafana Alloy para Application Observability:
  https://grafana.com/docs/opentelemetry/collector/grafana-alloy/
- Terraform provider para Grafana Cloud:
  https://grafana.com/docs/grafana-cloud/developer-resources/infrastructure-as-code/terraform/
- Criação de stack Grafana Cloud via Terraform:
  https://grafana.com/docs/grafana-cloud/as-code/infrastructure-as-code/terraform/terraform-cloud-stack/
- Alertas e notification policies via Terraform:
  https://grafana.com/docs/learning-journeys/configure-grafana-terraform/configure-alerts/
- SLOs via Terraform:
  https://grafana.com/docs/plugins/grafana-slo-app/latest/set-up/terraform/
- Synthetic Monitoring via Terraform:
  https://grafana.com/docs/grafana-cloud/testing/synthetic-monitoring/set-up/provision-synthetic-monitoring-resources/
- Coleta de logs Docker com Alloy:
  https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/
- cAdvisor exporter no Alloy:
  https://grafana.com/docs/grafana-cloud/send-data/alloy/reference/components/prometheus/prometheus.exporter.cadvisor/
- Postgres exporter no Alloy:
  https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.postgres/
- Grafana Frontend Observability / Faro:
  https://grafana.com/docs/grafana-cloud/monitor-applications/frontend-observability/
