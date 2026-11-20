$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$namespace = 'g7-academia'
$envFile = Join-Path $projectRoot '.env'
$backendImage = 'g7-academia-backend:stage3'
$frontendImage = 'g7-academia-frontend:stage3'

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando '$Name' não encontrado. Confira a instalação e o PATH."
    }
}

function Apply-Manifest([string]$FileName) {
    $path = Join-Path $projectRoot (Join-Path 'k8s' $FileName)
    if (-not (Test-Path $path)) { throw "Manifesto não encontrado: $path" }
    Write-Host "Aplicando $FileName ..." -ForegroundColor Cyan
    & kubectl apply -f $path
    if ($LASTEXITCODE -ne 0) { throw "Falha ao aplicar $FileName." }
}

function Show-PodDiagnostics([string]$Selector) {
    Write-Host "`n--- Pods: $Selector ---" -ForegroundColor Yellow
    & kubectl get pods -n $namespace -l $Selector -o wide
    $podJson = & kubectl get pods -n $namespace -l $Selector -o json
    if ($LASTEXITCODE -eq 0 -and $podJson) {
        $podList = $podJson | ConvertFrom-Json
        foreach ($pod in $podList.items) {
            Write-Host "`n--- Logs: $($pod.metadata.name) ---" -ForegroundColor Yellow
            & kubectl logs $pod.metadata.name -n $namespace --all-containers=true --tail=100
            Write-Host "`n--- Describe: $($pod.metadata.name) ---" -ForegroundColor Yellow
            & kubectl describe pod $pod.metadata.name -n $namespace
        }
    }
    & kubectl get events -n $namespace --sort-by=.lastTimestamp | Select-Object -Last 20
}

function Wait-Deployment([string]$Name, [string]$Selector, [int]$TimeoutSeconds) {
    Write-Host "Aguardando Deployment/$Name (limite ${TimeoutSeconds}s)..." -ForegroundColor Cyan
    & kubectl rollout status "deployment/$Name" -n $namespace "--timeout=${TimeoutSeconds}s"
    if ($LASTEXITCODE -ne 0) {
        Show-PodDiagnostics $Selector
        throw "Deployment/$Name não ficou pronto. O diagnóstico acima indica o próximo ponto a corrigir."
    }
}

Write-Host '=== G7 Academia | Etapa 3: aplicação replicada ===' -ForegroundColor Cyan

Assert-Command 'kubectl'
Assert-Command 'minikube'

if (-not (Test-Path $envFile)) {
    throw '.env não encontrado na raiz. Execute a Etapa 2 primeiro e mantenha JWT_SECRET no .env.'
}

# Lê somente as variáveis necessárias; nenhum valor secreto é exibido no terminal.
$envValues = @{}
foreach ($line in Get-Content -LiteralPath $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        $key = $Matches[1]
        $value = $Matches[2].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $envValues[$key] = $value
    }
}
if (-not $envValues.ContainsKey('JWT_SECRET') -or [string]::IsNullOrWhiteSpace($envValues['JWT_SECRET'])) {
    throw 'JWT_SECRET está ausente ou vazio no .env.'
}
if ($envValues['JWT_SECRET'].Length -lt 32) {
    throw 'JWT_SECRET deve ter pelo menos 32 caracteres para a assinatura HS256 usada pelo projeto.'
}

Write-Host '[1/7] Conferindo cluster, banco e Secrets existentes...' -ForegroundColor Cyan
$nodeReady = & kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'
if ($LASTEXITCODE -ne 0 -or $nodeReady -ne 'True') { throw 'O nó Kubernetes não está Ready. Verifique: kubectl get nodes.' }
& kubectl get namespace $namespace *> $null
if ($LASTEXITCODE -ne 0) { throw "Namespace '$namespace' não encontrado. Execute as Etapas 1 e 2." }
& kubectl get service db-service -n $namespace *> $null
if ($LASTEXITCODE -ne 0) { throw 'Service db-service não encontrado. O PostgreSQL da Etapa 2 precisa estar implantado.' }
$postgresReady = & kubectl get pod postgres-0 -n $namespace -o jsonpath='{.status.containerStatuses[0].ready}'
if ($LASTEXITCODE -ne 0 -or $postgresReady -ne 'true') { throw 'postgres-0 não está Ready. Não vou alterar o banco; corrija a Etapa 2 antes de continuar.' }
$dbSecretJson = & kubectl get secret g7-db-secret -n $namespace -o json
if ($LASTEXITCODE -ne 0) { throw 'Secret g7-db-secret não encontrado. Reexecute a preparação de Secrets da Etapa 2.' }
$dbSecret = $dbSecretJson | ConvertFrom-Json
$dbSecretKeys = @($dbSecret.data.PSObject.Properties.Name)
foreach ($key in @('APP_DB_USER', 'APP_DB_PASSWORD')) {
    if ($dbSecretKeys -notcontains $key) { throw "A chave $key não existe em g7-db-secret. Reexecute a Etapa 2 para atualizar o Secret." }
}

Write-Host '[2/7] Criando/atualizando Secret da aplicação sem imprimir JWT_SECRET...' -ForegroundColor Cyan
$tempSecretEnv = Join-Path $env:TEMP ('g7-app-secret-' + [guid]::NewGuid().ToString('N') + '.env')
$tempSecretYaml = Join-Path $env:TEMP ('g7-app-secret-' + [guid]::NewGuid().ToString('N') + '.yaml')
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
try {
    [System.IO.File]::WriteAllText($tempSecretEnv, "JWT_SECRET=$($envValues['JWT_SECRET'])", $utf8NoBom)
    $secretArgs = @('create', 'secret', 'generic', 'g7-app-secret', '--namespace', $namespace, "--from-env-file=$tempSecretEnv", '--dry-run=client', '-o', 'yaml')
    $secretYaml = & kubectl @secretArgs
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível gerar o Secret g7-app-secret.' }
    [System.IO.File]::WriteAllText($tempSecretYaml, ($secretYaml -join [Environment]::NewLine), $utf8NoBom)
    & kubectl apply -f $tempSecretYaml
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível aplicar g7-app-secret.' }
}
finally {
    Remove-Item -LiteralPath $tempSecretEnv, $tempSecretYaml -Force -ErrorAction SilentlyContinue
}

Write-Host '[3/7] Construindo imagem do backend Java 21 dentro do Minikube...' -ForegroundColor Cyan
$backendPath = Join-Path $projectRoot 'backend'
& minikube image build -t $backendImage $backendPath
if ($LASTEXITCODE -ne 0) { throw 'Falha ao construir a imagem do backend. Confira a saída do Maven acima.' }

Write-Host '[4/7] Construindo imagem do frontend Angular/Nginx dentro do Minikube...' -ForegroundColor Cyan
$frontendPath = Join-Path $projectRoot 'frontend'
& minikube image build -t $frontendImage $frontendPath
if ($LASTEXITCODE -ne 0) { throw 'Falha ao construir a imagem do frontend. Confira a saída do npm/Angular acima.' }

Write-Host '[5/7] Aplicando PgBouncer, backend, frontend e Services...' -ForegroundColor Cyan
$manifests = @(
    '20-pgbouncer-config.yaml',
    '21-pgbouncer-deployment.yaml',
    '22-pgbouncer-service.yaml',
    '23-backend-deployment.yaml',
    '24-backend-service.yaml',
    '25-frontend-deployment.yaml',
    '26-frontend-service.yaml'
)
foreach ($manifest in $manifests) { Apply-Manifest $manifest }

Write-Host '[6/7] Aguardando os componentes ficarem Ready...' -ForegroundColor Cyan
Wait-Deployment 'pgbouncer' 'app.kubernetes.io/name=pgbouncer' 90
Wait-Deployment 'backend' 'app.kubernetes.io/name=backend' 150
Wait-Deployment 'frontend' 'app.kubernetes.io/name=frontend' 90

Write-Host '[7/7] Resumo da implantação...' -ForegroundColor Cyan
& kubectl get deployments,pods,services -n $namespace -o wide
Write-Host "`nEndpoints do backend (esperado: 2 Pods):" -ForegroundColor Green
& kubectl get endpoints backend -n $namespace -o wide
Write-Host "`nEndpoints do frontend (esperado: 2 Pods):" -ForegroundColor Green
& kubectl get endpoints app-service -n $namespace -o wide

Write-Host "`n=== Etapa 3 implantada ===" -ForegroundColor Green
Write-Host 'A aplicação fica disponível pelo Service NodePort app-service.'
Write-Host 'Em outro terminal, execute: minikube service app-service -n g7-academia --url'
Write-Host 'Mantenha esse comando aberto enquanto acessar a URL no navegador.'
