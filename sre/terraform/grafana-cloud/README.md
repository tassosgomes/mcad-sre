# Grafana Cloud Terraform

Terraform para provisionar recursos dentro do stack Grafana Cloud usado pelo
MCAD: folders, contact points, notification policy e dashboards baseline.

## State remoto no Cloudflare R2

Copie o exemplo e preencha os valores reais do bucket/account fora de commits
sensíveis:

```bash
cp backend.r2.tf.example backend.tf
```

Depois exporte as credenciais R2:

```bash
export AWS_ACCESS_KEY_ID="<R2_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<R2_SECRET_ACCESS_KEY>"
```

O backend usa `use_lockfile = true`, então o bucket precisa permitir criar e
apagar o objeto `.tflock` ao lado do state.

## Credenciais do Grafana

O provider usa:

```bash
export TF_VAR_grafana_url="https://<stack>.grafana.net"
export TF_VAR_grafana_auth="<service-account-token>"
```

O token deve ter permissão para criar folders, dashboards e alerting resources
no stack.

## Primeiro plan

```bash
terraform init
terraform plan \
  -var-file=terraform.tfvars.example
```

Para aplicar de verdade, copie `terraform.tfvars.example` para um arquivo local
não versionado ou passe as variáveis pela pipeline.

## Variáveis que ainda precisamos definir

- URL do stack Grafana Cloud.
- Service account token do Grafana.
- Bucket R2, Account ID Cloudflare e Access Key R2.
- UID real do datasource Prometheus/Mimir no stack.
- E-mail ou webhook do canal de alerta.
