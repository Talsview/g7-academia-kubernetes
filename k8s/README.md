# Kubernetes — G7 Academia

Os recursos Kubernetes deste projeto ficam nesta pasta. Todos os recursos da aplicação serão instalados no namespace `g7-academia`.

## Etapa 1 — preparar o cluster local

Pré-requisitos no Windows:

- Docker Desktop instalado e aberto, com o mecanismo Linux ativo.
- Minikube.
- kubectl (opcional para esta etapa, pois o Minikube também disponibiliza `minikube kubectl --`).

Instalação pelo WinGet (PowerShell):

```powershell
winget install Kubernetes.minikube
winget install -e --id Kubernetes.kubectl
```

Feche e abra novamente o PowerShell após a instalação. Confira:

```powershell
docker version
minikube version
kubectl version --client
```

Inicie o cluster, crie o namespace e confira o nó:

```powershell
minikube start --driver=docker --cpus=4 --memory=6144 --disk-size=30g
kubectl apply -f .\k8s\00-namespace.yaml
kubectl get nodes
kubectl get namespaces
```

Também é possível executar o script da etapa 1 a partir da raiz do projeto:

```powershell
.\scripts\k8s\etapa1-preparar.ps1
```

Se o PowerShell bloquear a execução do script, libere somente para a sessão atual:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\etapa1-preparar.ps1
```

## Conferência esperada

- `kubectl get nodes` deve mostrar o nó `minikube` com `STATUS` igual a `Ready`.
- `kubectl get namespace g7-academia` deve mostrar o namespace criado.

Não prossiga para a implantação do banco antes de o nó estar `Ready`.

## Limpeza da etapa

Para parar o cluster sem apagar os arquivos do projeto:

```powershell
minikube stop
```

Para apagar o cluster local inteiro (não execute durante a atividade sem necessidade):

```powershell
minikube delete
```
