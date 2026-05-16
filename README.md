# mcad-sre

Repositório de SRE/observabilidade da plataforma MCAD.

## Conteúdo

- `sre/plano-observabilidade-grafana-cloud.md`: estratégia e plano de
  implementação.
- `sre/terraform/grafana-cloud`: baseline Terraform para Grafana Cloud com
  backend R2 de exemplo.
- `sre/observability/alloy`: stack Grafana Alloy local e Docker Swarm.
- `sre/runbooks`: runbooks operacionais.

## Próximo passo

Preencher os valores sensíveis fora do repositório:

- credenciais R2 para o backend Terraform;
- URL e service account token do Grafana;
- endpoint OTLP, instance ID e token de ingestão do Grafana Cloud.
