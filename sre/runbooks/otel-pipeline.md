# Runbook: OTLP app -> Alloy -> Grafana Cloud

## Sintoma

Um serviço não aparece no Grafana Cloud, não há traces/logs recentes ou os
dashboards mostram ausência de métricas.

## Checagens

1. Confirmar variáveis do serviço:

   ```bash
   OTEL_EXPORTER_OTLP_ENDPOINT=http://mcad-observability-alloy:4318
   OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
   OTEL_SERVICE_NAME=<servico>
   OTEL_RESOURCE_ATTRIBUTES=service.namespace=mcad,deployment.environment=prod,service.version=<versao>
   ```

2. Confirmar conectividade app -> Alloy na mesma rede Swarm:

   ```bash
   docker service inspect <stack>_<service> --format '{{json .Spec.TaskTemplate.Networks}}'
   docker service logs -f mcad-observability_mcad-observability-alloy
   ```

3. Confirmar que Alloy está pronto:

   ```bash
   docker service ps mcad-observability_mcad-observability-alloy
   docker service logs --tail 200 mcad-observability_mcad-observability-alloy
   ```

4. Procurar erro de export para Grafana Cloud:

   ```bash
   docker service logs mcad-observability_mcad-observability-alloy | grep -i "export\\|error\\|retry"
   ```

5. Verificar no Grafana Explore:

   - Metrics: filtrar por `service_name` ou `service.name`.
   - Logs: filtrar por `service_name`, `service`, `deployment_environment`.
   - Traces: filtrar por `service.name`.

## Causas comuns

- serviço fora da rede `mcad-observability-net`;
- endpoint OTLP usando nome errado do serviço Alloy;
- token Grafana Cloud expirado/revogado;
- `GRAFANA_INSTANCE_ID` ou `GRAFANA_OTLP_ENDPOINT` incorretos;
- aplicação instrumentada só com Prometheus local, sem OTLP;
- cardinalidade/atributos diferentes do esperado no dashboard.

## Recuperação

1. Corrigir env/rede do serviço.
2. Recriar Docker secret se o token foi rotacionado.
3. Recriar Docker config se o Alloy foi alterado.
4. Redeploy da stack `mcad-observability`.
5. Redeploy do serviço afetado.
