$ErrorActionPreference = "Stop"

function Invoke-Kubectl {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl falhou: kubectl $($Arguments -join ' ')"
    }
}

function Wait-Deployments {
    param([array]$Targets, [int]$TimeoutSeconds = 300)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $pending = @($Targets)
    while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline) {
        $nextPending = @()
        foreach ($target in $pending) {
            $raw = & kubectl get deployment $target.Name -n $target.Namespace -o json 2>$null
            if ($LASTEXITCODE -ne 0) {
                $nextPending += $target
                continue
            }
            $deployment = ($raw -join "`n") | ConvertFrom-Json
            $desired = [int]$deployment.spec.replicas
            $available = 0
            if ($null -ne $deployment.status.availableReplicas) { $available = [int]$deployment.status.availableReplicas }
            if ($available -lt $desired) { $nextPending += $target }
        }
        $pending = @($nextPending)
        if ($pending.Count -gt 0) {
            $labels = ($pending | ForEach-Object { "$($_.Namespace)/$($_.Name)" }) -join ", "
            Write-Host "Aguardando: $labels" -ForegroundColor DarkYellow
            Start-Sleep -Seconds 5
        }
    }
    if ($pending.Count -gt 0) {
        Write-Host "Tempo limite atingido. Pods e eventos:" -ForegroundColor Yellow
        foreach ($ns in @($Targets.Namespace | Select-Object -Unique)) {
            & kubectl get pods -n $ns -o wide
            & kubectl get events -n $ns --sort-by=.lastTimestamp | Select-Object -Last 15
        }
        throw "Alguns Deployments não ficaram prontos em ${TimeoutSeconds}s. Consulte os logs dos Pods pendentes."
    }
    Write-Host "Todos os Deployments monitorados estão disponíveis." -ForegroundColor Green
}

Write-Host "=== G7 Academia | Etapa 4: Observabilidade ===" -ForegroundColor Cyan
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$manifestDir = Join-Path $projectRoot "k8s\observability"
$backendDir = Join-Path $projectRoot "backend"
$minikubeExe = "C:\Program Files\Kubernetes\Minikube\minikube.exe"

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl não encontrado no PATH. Abra um novo terminal depois da instalação."
}
if (-not (Get-Command minikube -ErrorAction SilentlyContinue)) {
    if (Test-Path $minikubeExe) {
        $env:Path = "$(Split-Path $minikubeExe);$env:Path"
    } else {
        throw "minikube.exe não encontrado. Verifique a instalação."
    }
}
if (-not (Test-Path (Join-Path $manifestDir "00-namespace.yaml"))) {
    throw "Arquivos da Etapa 4 não encontrados em k8s\observability. Extraia o ZIP na raiz do projeto."
}

Write-Host "[1/7] Validando cluster e aplicação existente..." -ForegroundColor Cyan
$nodesRaw = & kubectl get nodes -o json
if ($LASTEXITCODE -ne 0) { throw "Não foi possível consultar os nós Kubernetes." }
$nodes = ($nodesRaw -join "`n") | ConvertFrom-Json
$readyNodes = @($nodes.items | Where-Object {
    @($_.status.conditions | Where-Object { $_.type -eq "Ready" -and $_.status -eq "True" }).Count -gt 0
})
if ($readyNodes.Count -lt 1) { throw "Nenhum nó Kubernetes está Ready. Execute kubectl get nodes." }

& kubectl get deployment backend -n g7-academia *> $null
if ($LASTEXITCODE -ne 0) { throw "Deployment backend não encontrado em g7-academia. Conclua a Etapa 3 primeiro." }
& kubectl get deployment frontend -n g7-academia *> $null
if ($LASTEXITCODE -ne 0) { throw "Deployment frontend não encontrado em g7-academia. Conclua a Etapa 3 primeiro." }
& kubectl get secret g7-db-secret -n g7-academia *> $null
if ($LASTEXITCODE -ne 0) { throw "Secret g7-db-secret não encontrado. O PostgreSQL da Etapa 2 precisa estar configurado." }
& kubectl get secret g7-app-secret -n g7-academia *> $null
if ($LASTEXITCODE -ne 0) { throw "Secret g7-app-secret não encontrado. O backend atual precisa estar configurado." }

Write-Host "[2/7] Criando namespace e Secret local do Grafana..." -ForegroundColor Cyan
Invoke-Kubectl @("apply", "-f", (Join-Path $manifestDir "00-namespace.yaml"))
$securePassword = Read-Host "Defina a senha do usuário admin do Grafana (mínimo 12 caracteres)" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$tempEnv = Join-Path $env:TEMP ("g7-grafana-" + [guid]::NewGuid().ToString("N") + ".env")
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    if ([string]::IsNullOrWhiteSpace($plainPassword) -or $plainPassword.Length -lt 12) {
        throw "A senha do Grafana precisa ter pelo menos 12 caracteres. Execute o script novamente."
    }
    $secretText = "GF_SECURITY_ADMIN_USER=admin`nGF_SECURITY_ADMIN_PASSWORD=$plainPassword`n"
    [System.IO.File]::WriteAllText($tempEnv, $secretText, [System.Text.UTF8Encoding]::new($false))
    $secretYaml = & kubectl create secret generic grafana-admin -n observability --from-env-file=$tempEnv --dry-run=client -o yaml
    if ($LASTEXITCODE -ne 0) { throw "Não foi possível gerar o Secret do Grafana." }
    $secretYaml | & kubectl apply -f - | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Não foi possível aplicar o Secret do Grafana." }
}
finally {
    if (Test-Path $tempEnv) { Remove-Item $tempEnv -Force -ErrorAction SilentlyContinue }
    if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    if ($securePassword) { $securePassword.Dispose() }
    $plainPassword = $null
    $secretText = $null
    $secretYaml = $null
}

Write-Host "[3/7] Aplicando Prometheus e kube-state-metrics..." -ForegroundColor Cyan
foreach ($file in @("01-prometheus-rbac.yaml", "02-kube-state-metrics.yaml", "03-prometheus.yaml")) {
    Invoke-Kubectl @("apply", "-f", (Join-Path $manifestDir $file))
}

Write-Host "[4/7] Aplicando Loki, Tempo, OpenTelemetry Collector, Alloy e Grafana..." -ForegroundColor Cyan
foreach ($file in @("10-loki.yaml", "20-tempo.yaml", "30-otel-collector.yaml", "40-alloy.yaml", "50-grafana.yaml")) {
    Invoke-Kubectl @("apply", "-f", (Join-Path $manifestDir $file))
}

Write-Host "[5/7] Construindo backend com Prometheus e OpenTelemetry..." -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $backendDir "Dockerfile"))) { throw "Dockerfile do backend não encontrado." }
& minikube image build -t g7-academia-backend:stage4 $backendDir
if ($LASTEXITCODE -ne 0) { throw "Falha ao construir g7-academia-backend:stage4. Verifique a saída do Maven/Docker." }
Invoke-Kubectl @("apply", "-f", (Join-Path $projectRoot "k8s\23-backend-deployment.yaml"))

Write-Host "[6/7] Aguardando os componentes ficarem prontos..." -ForegroundColor Cyan
Wait-Deployments -Targets @(
    @{ Name = "kube-state-metrics"; Namespace = "observability" },
    @{ Name = "prometheus"; Namespace = "observability" },
    @{ Name = "loki"; Namespace = "observability" },
    @{ Name = "tempo"; Namespace = "observability" },
    @{ Name = "otel-collector"; Namespace = "observability" },
    @{ Name = "alloy"; Namespace = "observability" },
    @{ Name = "grafana"; Namespace = "observability" },
    @{ Name = "backend"; Namespace = "g7-academia" }
) -TimeoutSeconds 300

Write-Host "[7/7] Resumo final..." -ForegroundColor Cyan
kubectl get deployments,pods,services,pvc -n observability
kubectl get deployment backend,frontend,pgbouncer -n g7-academia
Write-Host ""
Write-Host "=== ETAPA 4 INSTALADA ===" -ForegroundColor Green
Write-Host "Grafana: em outro terminal execute: minikube service grafana -n observability --url"
Write-Host "Login: admin | senha: a que você acabou de informar (não é salva no repositório)."
Write-Host "Aguarde 30-60 segundos e gere acessos ao G7 Academia para observar métricas, logs e traces."
