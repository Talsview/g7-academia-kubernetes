$ErrorActionPreference = 'Stop'

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$namespaceManifest = Join-Path $projectRoot 'k8s\00-namespace.yaml'

Write-Host '=== G7 Academia | Etapa 1: preparar Kubernetes ===' -ForegroundColor Cyan

if (-not (Test-Command 'docker')) {
    throw 'Docker CLI não encontrado. Instale/abra o Docker Desktop e tente novamente.'
}
if (-not (Test-Command 'minikube')) {
    throw 'Minikube não encontrado. Instale com: winget install Kubernetes.minikube. Depois reabra o PowerShell.'
}

if (-not (Test-Path $namespaceManifest)) {
    throw "Manifesto não encontrado: $namespaceManifest"
}

Write-Host '\n[1/4] Verificando se o Docker Desktop está ativo...'
& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'O Docker não está respondendo. Abra o Docker Desktop, aguarde ficar pronto e execute novamente.'
}

Write-Host '\n[2/4] Iniciando o Minikube (driver Docker)...'
& minikube start --driver=docker --cpus=4 --memory=6144 --disk-size=30g
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao iniciar o Minikube. Confira a mensagem acima e tente novamente.'
}

Write-Host '\n[3/4] Aplicando o namespace g7-academia...'
if (Test-Command 'kubectl') {
    & kubectl apply -f $namespaceManifest
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível aplicar o namespace com kubectl.' }
    Write-Host '\n[4/4] Estado do cluster:'
    & kubectl get nodes
    & kubectl get namespace g7-academia
} else {
    Write-Host 'kubectl não está no PATH; usando a cópia disponibilizada pelo Minikube.' -ForegroundColor Yellow
    & minikube kubectl -- apply -f $namespaceManifest
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível aplicar o namespace com minikube kubectl.' }
    Write-Host '\n[4/4] Estado do cluster:'
    & minikube kubectl -- get nodes
    & minikube kubectl -- get namespace g7-academia
}

Write-Host '\nEtapa 1 concluída. Confirme que o nó minikube aparece como Ready.' -ForegroundColor Green
