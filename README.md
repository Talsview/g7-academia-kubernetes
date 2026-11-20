# G7 Academia — Projeto Kubernetes e Observabilidade

**Integrantes:** Davi Martins e Caio Vinicius  
**Projeto:** G7 Academia — sistema interno de controle de alunos, planos, matrículas, mensalidades e acessos.

Este repositório adapta o sistema original G7 Academia para um cluster Kubernetes local com Minikube. A aplicação mantém o frontend Angular, a API Spring Boot, o PgBouncer e o PostgreSQL, e acrescenta uma stack de observabilidade com Prometheus, Loki, Grafana Alloy, Tempo, OpenTelemetry Collector e Grafana.

> **Escopo do ambiente:** laboratório acadêmico local, executado em Minikube com Docker Desktop. Os manifestos de observabilidade usam armazenamento local e não representam uma configuração de alta disponibilidade para produção.

## 1. Arquitetura

```text
Navegador
   |
   v
Service app-service (NodePort)
   |
   v
Frontend Angular + Nginx (2 réplicas)
   |
   v
Service backend (ClusterIP:8080)
   |
   v
Spring Boot (2 réplicas)
   |
   v
PgBouncer (ClusterIP:6432)
   |
   v
PostgreSQL 16 (StatefulSet + PVC de 2 GiB)
```

Observabilidade:

```text
Métricas: Spring Boot / Kubernetes -> Prometheus -> Grafana
Logs: Pods do Kubernetes -> Grafana Alloy -> Loki -> Grafana
Traces: Spring Boot (OTLP) -> OpenTelemetry Collector -> Tempo -> Grafana
```

## 2. Tecnologias utilizadas

| Camada | Tecnologia |
|---|---|
| Frontend | Angular 18, TypeScript e Nginx |
| Backend | Java 21, Spring Boot 3.3.5, Spring Security e JWT |
| Banco | PostgreSQL 16 |
| Pool de conexões | PgBouncer |
| Contêineres | Docker Desktop |
| Orquestração local | Kubernetes com Minikube |
| Métricas | Prometheus e kube-state-metrics |
| Logs | Grafana Alloy e Loki |
| Traces | OpenTelemetry Spring Boot Starter, OpenTelemetry Collector e Tempo |
| Dashboards | Grafana |

## 3. Estrutura principal do repositório

```text
backend/                  API Spring Boot
frontend/                 SPA Angular e configuração Nginx
bd/                       Configuração e backup SQL do PostgreSQL
k8s/                      Manifestos Kubernetes da aplicação e do banco
  observability/          Manifestos da stack de observabilidade
scripts/k8s/              Scripts PowerShell das etapas
apresentacao/             Material da apresentação do projeto
 docs/                    Documentação da arquitetura
 evidencias/              Capturas de tela para avaliação
```

## 4. Pré-requisitos

- Windows 10/11.
- Docker Desktop instalado e em execução.
- Minikube.
- kubectl.
- GitHub Desktop.
- Conexão com a internet para baixar imagens e dependências na primeira compilação.

Instalação pelo WinGet (quando necessário):

```powershell
winget install Kubernetes.minikube
winget install -e --id Kubernetes.kubectl
```

Se o Minikube estiver instalado em `C:\Program Files\Kubernetes\Minikube` e o PowerShell não reconhecer o comando, adicione o diretório ao PATH da sessão:

```powershell
$env:Path = "C:\Program Files\Kubernetes\Minikube;$env:Path"
```

## 5. Subir o cluster Minikube

Abra o Docker Desktop e aguarde sua inicialização. Na raiz do repositório:

```powershell
minikube start --driver=docker
kubectl wait --for=condition=Ready node/minikube --timeout=180s
kubectl get nodes
```

Preparar o namespace e os recursos iniciais:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\etapa1-preparar.ps1
```

## 6. Implantar o PostgreSQL

Na raiz do repositório:

```powershell
.\scripts\k8s\etapa2-postgres.ps1
```

O banco utiliza PostgreSQL 16, StatefulSet, PVC persistente de 2 GiB e o Service interno `db-service` na porta 5432. O backup inicial contém os schemas, tabelas, rotinas e dados de demonstração do G7 Academia.

Na execução relatada, o PostgreSQL ficou `Running 1/1`, o PVC ficou `Bound`, a consulta retornou **5 alunos** e foram identificadas as tabelas `alunos`, `matriculas`, `operadores`, `planos` e `registros_acesso` no schema `app`.

Se o StatefulSet precisar da correção de inicialização já utilizada neste ambiente, aplicar o manifesto atualizado e executar o script de recuperação disponibilizado para a Etapa 2. **Não excluir o PVC `postgres-data-postgres-0`**, pois ele contém os dados persistentes.

## 7. Implantar a aplicação replicada

Executar:

```powershell
.\scripts\k8s\etapa3-aplicacao.ps1
```

O script constrói as imagens do projeto e implanta PgBouncer, backend e frontend. A configuração usada prevê:

- Backend Spring Boot: 2 réplicas.
- Frontend Angular/Nginx: 2 réplicas.
- PgBouncer: 1 réplica.
- PostgreSQL: 1 StatefulSet com volume persistente.

Conferir os recursos:

```powershell
kubectl get deployments,pods,services -n g7-academia
```

Para abrir a aplicação:

```powershell
minikube service app-service -n g7-academia --url
```

Mantenha o terminal desse comando aberto enquanto utilizar a URL apresentada.

## 8. Instalar a stack de observabilidade

Executar:

```powershell
.\scripts\k8s\etapa4-observabilidade.ps1
```

O script cria o namespace `observability`, solicita uma senha para o usuário `admin` do Grafana, aplica os manifestos e recompila o backend com instrumentação de métricas e traces.

### Versão do OpenTelemetry Collector

No ambiente utilizado, a tag `otel/opentelemetry-collector-contrib:0.165.1` não foi encontrada no registry. O manifesto `k8s/observability/30-otel-collector.yaml` foi ajustado para usar `otel/opentelemetry-collector-contrib:0.165.0`, que foi baixada e iniciou com a mensagem `Everything is ready. Begin running and processing data.`

### Componentes implantados

| Componente | Função |
|---|---|
| Prometheus | Coleta métricas da aplicação e do cluster |
| kube-state-metrics | Expõe estado dos objetos Kubernetes |
| Loki | Armazena logs dos Pods |
| Grafana Alloy | Descobre e encaminha logs do Kubernetes ao Loki |
| Tempo | Armazena traces distribuídos |
| OpenTelemetry Collector | Recebe OTLP e exporta traces para Tempo |
| Grafana | Centraliza fontes de dados e dashboards |

Conferir:

```powershell
kubectl get deployments,pods,services,pvc -n observability
kubectl get deployments,pods -n g7-academia
```

Abrir o Grafana:

```powershell
minikube service grafana -n observability --url
```

Entrar com usuário `admin` e a senha definida durante a instalação. A senha é armazenada em Secret do Kubernetes; não a incluir nos arquivos versionados.

## 9. Consultas úteis no Grafana

### Prometheus — métricas

No Grafana, abrir **Explore → Prometheus**, selecionar **Code**, executar e clicar em **Run query**:

```promql
up
```

Estado dos Pods do namespace da aplicação:

```promql
kube_pod_status_ready{namespace="g7-academia",condition="true"}
```

Uso de CPU por Pod:

```promql
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="g7-academia",container!="",image!=""}[5m]))
```

### Loki — logs

No Grafana, abrir **Explore → Loki** e executar:

```logql
{project="g7-academia"}
```

### Tempo — traces

No Grafana, abrir **Explore → Tempo → Search**, selecionar um intervalo de tempo e pesquisar o serviço `g7-academia-backend`. O backend envia traces via OTLP gRPC ao serviço `otel-collector.observability:4317`, que encaminha os dados ao Tempo.

## 10. Evidências da atividade

As capturas devem ser salvas na pasta `evidencias/` e referenciadas aqui:

| Evidência | Arquivo | Situação do material disponível |
|---|---|---|
| Pods, Deployments e Services (2 réplicas do backend e frontend) | `evidencia-03-01-pods-deployments-services.png` | Captura ainda deve ser colocada na pasta |
| Aplicação G7 Academia no navegador | `evidencia-03-02-g7-academia-navegador.png` | Captura final sem mensagem de erro de login ainda deve ser colocada |
| Prometheus no Grafana | `evidencia-04-01-grafana-prometheus.png` | A consulta `up` foi executada; incluir a captura dos resultados |
| Loki no Grafana | `evidencia-04-02-grafana-loki.png` | Captura incluída nesta pasta |
| Tempo no Grafana | `evidencia-04-03-grafana-tempo.png` | Captura ainda deve ser colocada |

> Não inserir capturas fictícias. A evidência do Loki incluída mostra registros de log do projeto. Para a avaliação, completar a pasta com as capturas reais solicitadas pelo professor.

## 11. Segurança e versionamento

- Não versionar `.env`, tokens JWT, senhas do banco ou senha administrativa do Grafana.
- Manter `.env` ignorado pelo `.gitignore`.
- O PostgreSQL não é publicado externamente; o acesso é feito pelo Service interno `db-service`.
- O login do G7 Academia usa JWT e perfis de acesso.
- Os manifestos e scripts devem ser versionados; dados físicos dos PVCs não devem ser adicionados ao Git.

## 12. Commits sugeridos por etapa

```text
chore: importar projeto inicial G7 Academia
infra: preparar ambiente Kubernetes
feat(k8s): implantar PostgreSQL com volume persistente
feat(k8s): implantar aplicação replicada
feat(observability): configurar Prometheus Loki Tempo OpenTelemetry e Grafana
docs: finalizar documentação e evidências da atividade
```

## 13. Integrantes

- Davi Martins
- Caio Vinicius
