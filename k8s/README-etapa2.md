# Etapa 2 — PostgreSQL no Kubernetes

Esta etapa implanta o banco de dados do G7 Academia no namespace `g7-academia`, utilizando PostgreSQL 16, `StatefulSet`, armazenamento persistente e `Service` interno `ClusterIP`.

## O que será criado

- `Secret/g7-db-secret`: credenciais lidas do arquivo local `.env` (não versionado).
- `ConfigMap/postgres-config`: configuração do PostgreSQL e regras de autenticação adequadas à rede interna do Kubernetes.
- `ConfigMap/postgres-init`: backup SQL do projeto e script de criação dos usuários `app_user` e `leitor_user`.
- `StatefulSet/postgres`: uma instância PostgreSQL 16.
- `PersistentVolumeClaim/postgres-data-postgres-0`: volume persistente de 2 GiB.
- `Service/db-service`: acesso interno ao banco na porta 5432.
- `Service/postgres-headless`: identidade de rede do StatefulSet.

O banco não é publicado com `NodePort` ou `LoadBalancer`. A aplicação acessará `db-service` dentro do cluster. A configuração `pg_hba.conf` aceita conexões autenticadas da faixa privada usada pelos Pods no Minikube (`10.0.0.0/8`), além de loopback.

## Antes de executar

1. Faça o commit da Etapa 1.
2. Extraia o conteúdo deste ZIP na raiz do repositório, mantendo as pastas `k8s` e `scripts`.
3. Confira se `k8s/00-namespace.yaml` existe e se `kubectl get nodes` mostra `minikube Ready`.
4. O script cria `.env` a partir de `.env.example` se o arquivo ainda não existir. Revise as credenciais locais antes de continuar. O `.env` está listado no `.gitignore` e não deve ser enviado ao GitHub.

## Executar no PowerShell

Na raiz de `g7-academia-kubernetes`:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\etapa2-postgres.ps1
```

Se o script criar `.env` e encerrar pedindo revisão, abra o arquivo, ajuste as senhas e execute novamente:

```powershell
notepad .env
.\scripts\k8s\etapa2-postgres.ps1
```

O banco precisa manter `POSTGRES_DB=g7_academia` e `POSTGRES_USER=postgres`, porque o backup SQL do G7 usa esse nome de banco e o script de inicialização utiliza o usuário administrador informado.

## Verificação manual

```powershell
kubectl get pods,pvc,services -n g7-academia
kubectl logs postgres-0 -n g7-academia --tail=80
kubectl exec postgres-0 -n g7-academia -- pg_isready -U postgres -d g7_academia
kubectl exec postgres-0 -n g7-academia -- psql -U postgres -d g7_academia -c "SELECT count(*) FROM app.alunos;"
kubectl exec postgres-0 -n g7-academia -- psql -U postgres -d g7_academia -c "SELECT count(*) FROM app.operadores;"
```

Resultado esperado: Pod `postgres-0` em `Running` e `Ready 1/1`, PVC `Bound`, `db-service` como `ClusterIP`, e consultas SQL concluídas.

## Atenção à persistência

Os arquivos `01-backup.sql` e `02-usuarios.sh` são executados somente na primeira inicialização de um diretório de dados PostgreSQL vazio. Aplicar novamente os manifestos não recria nem apaga os dados. Não exclua o PVC para tentar corrigir erros sem antes verificar os logs e confirmar que pode perder os dados locais.

## Commit sugerido após os testes

```text
feat(k8s): implantar PostgreSQL com volume persistente
```
