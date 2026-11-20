# Etapa 3 — Aplicação G7 Academia replicada no Kubernetes

Esta etapa implanta o código original do G7 Academia. O frontend é Angular servido por Nginx; a API é Spring Boot 3.3.5/Java 21. O backend acessa o PostgreSQL exclusivamente por meio do PgBouncer, conforme `application.yml`, `bd/pgbouncer.ini` e `docker-compose.yml` do projeto.

## Topologia

```text
Navegador
   |
   v
app-service (NodePort:80)
   |
   +---- frontend (Angular + Nginx) — 2 réplicas
               |
               | /api/* -> Service backend:8080
               v
           backend — 2 réplicas Spring Boot
               |
               | jdbc:postgresql://pgbouncer-service:6432/g7_academia
               v
         pgbouncer-service:6432
               |
               v
          db-service:5432
               |
               v
       postgres-0 (PVC 2 GiB já existente)
```

O PostgreSQL e seu PVC não são recriados por esta etapa. O PgBouncer recebe `APP_DB_USER` e `APP_DB_PASSWORD` do Secret `g7-db-secret`, criado na Etapa 2. O JWT é armazenado separadamente no Secret `g7-app-secret`.

## Arquivos

- `20-pgbouncer-config.yaml`: configuração do PgBouncer, ajustada para resolver `db-service` no Kubernetes.
- `21-pgbouncer-deployment.yaml` e `22-pgbouncer-service.yaml`: pool de conexões interno.
- `23-backend-deployment.yaml` e `24-backend-service.yaml`: Spring Boot com `replicas: 2`.
- `25-frontend-deployment.yaml` e `26-frontend-service.yaml`: Angular/Nginx com `replicas: 2` e Service NodePort `app-service`.
- `scripts/k8s/etapa3-aplicacao.ps1`: valida pré-requisitos, cria o Secret JWT, constrói as imagens no Minikube, aplica os manifestos e aguarda os Deployments.

## Pré-requisitos

1. Etapas 1 e 2 concluídas.
2. `minikube status` e `kubectl get nodes` devem mostrar o cluster ativo e o nó `Ready`.
3. `postgres-0` deve estar `1/1 Running` e `db-service` deve existir.
4. `.env` deve conter `JWT_SECRET` com pelo menos 32 caracteres. Não versione `.env`.
5. O Secret `g7-db-secret` deve conter `APP_DB_USER` e `APP_DB_PASSWORD` (criado na Etapa 2).

## Executar no Windows / PowerShell

Na raiz do repositório:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\etapa3-aplicacao.ps1
```

O script constrói as imagens diretamente no cache de imagens do Minikube. Isso evita que o Kubernetes tente baixar essas imagens locais de um registry. A primeira compilação pode levar alguns minutos por causa do Maven e do npm; as execuções seguintes reaproveitam o cache de camadas disponível.

## Verificar os recursos

```powershell
kubectl get deployments,pods,services -n g7-academia -o wide
kubectl get endpoints backend app-service pgbouncer-service -n g7-academia -o wide
```

Resultado esperado:

- `backend`: 2/2 réplicas disponíveis.
- `frontend`: 2/2 réplicas disponíveis.
- `pgbouncer`: 1/1 réplica disponível.
- `postgres-0`: continua 1/1 Running.
- `backend` e `app-service` devem apresentar dois endereços de Pod nos endpoints.

## Abrir no navegador

Em um terminal PowerShell separado, execute:

```powershell
minikube service app-service -n g7-academia --url
```

Mantenha esse comando em execução se ele mantiver o túnel aberto. Acesse a URL exibida no navegador. O Nginx atende a SPA e encaminha `/api/*` para o Service `backend`, que distribui as conexões entre os Pods Spring Boot.

## Comprovar o balanceamento entre as duas réplicas

O Nginx inclui temporariamente o cabeçalho didático `X-G7-Backend`, com o endereço do upstream selecionado. Em outro PowerShell, substitua a URL pela URL impressa pelo Minikube:

```powershell
$url = "http://127.0.0.1:PORTA"
1..12 | ForEach-Object {
    (curl.exe -sS -D - -o NUL "$url/api/alunos" | Select-String -Pattern '^X-G7-Backend:').Line
}
```

A API pode responder `401` porque a rota exige JWT; isso é esperado sem login. O cabeçalho deve mostrar os endereços dos Pods de backend selecionados pelo Service. Para confirmar também pelo Kubernetes:

```powershell
kubectl get endpoints backend -n g7-academia -o wide
kubectl get pods -n g7-academia -l app.kubernetes.io/name=backend -o wide
```

O cabeçalho `X-G7-Backend` expõe IPs internos dos Pods e serve apenas para a demonstração local. Remova-o do `frontend/nginx.conf` antes de publicar uma implantação de produção exposta publicamente.

## Diagnóstico rápido

```powershell
kubectl get pods -n g7-academia -o wide
kubectl logs deployment/pgbouncer -n g7-academia --tail=100
kubectl logs deployment/backend -n g7-academia --all-pods=true --tail=100
kubectl logs deployment/frontend -n g7-academia --all-pods=true --tail=100
kubectl get events -n g7-academia --sort-by=.lastTimestamp | Select-Object -Last 20
```

Não exclua `postgres-data-postgres-0` e não execute o script da Etapa 2 novamente durante o diagnóstico da aplicação.

## Commit da Etapa 3

Depois de comprovar os dois Deployments e abrir a aplicação no navegador, registre no GitHub Desktop:

```text
feat(k8s): implantar G7 Academia com frontend e backend replicados
```
