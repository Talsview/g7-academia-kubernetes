$ErrorActionPreference = 'Stop'

$namespace = 'g7-academia'
$podName = 'postgres-0'
$manifest = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'k8s\12-postgres-statefulset.yaml'
$expectedArgs = @('-c', 'config_file=/etc/postgresql/postgresql.conf')

function Get-PodObject {
    $json = & kubectl get pod $podName -n $namespace -o json 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (($json -join "`n") | ConvertFrom-Json)
}

function Show-Diagnostics {
    Write-Host "`n===== PODS E PVC =====" -ForegroundColor Yellow
    & kubectl get pods,pvc,services -n $namespace
    Write-Host "`n===== LOG ATUAL =====" -ForegroundColor Yellow
    & kubectl logs $podName -n $namespace --tail=80
    Write-Host "`n===== LOG ANTERIOR =====" -ForegroundColor Yellow
    & kubectl logs $podName -n $namespace --previous --tail=80
    Write-Host "`n===== EVENTOS RECENTES =====" -ForegroundColor Yellow
    & kubectl get events -n $namespace --sort-by=.lastTimestamp | Select-Object -Last 12
}

Write-Host '=== G7 Academia | Recuperação objetiva do PostgreSQL ===' -ForegroundColor Cyan

if (-not (Test-Path $manifest)) { throw "Manifesto não encontrado: $manifest" }

# Pré-condições: namespace, Secret e armazenamento já existentes.
& kubectl get namespace $namespace *> $null
if ($LASTEXITCODE -ne 0) { throw "Namespace $namespace não encontrado." }
& kubectl get secret g7-db-secret -n $namespace *> $null
if ($LASTEXITCODE -ne 0) { throw 'Secret g7-db-secret não encontrado. Não vou recriar credenciais automaticamente.' }

$pvcJson = & kubectl get pvc postgres-data-postgres-0 -n $namespace -o json
if ($LASTEXITCODE -ne 0) { throw 'PVC postgres-data-postgres-0 não encontrado. Parei sem alterar armazenamento.' }
$pvc = ($pvcJson -join "`n") | ConvertFrom-Json
if ($pvc.status.phase -ne 'Bound') { throw "PVC está em '$($pvc.status.phase)', não Bound. Parei sem excluir recursos." }

Write-Host '[1/4] Aplicando StatefulSet corrigido (args + RollingUpdate)...' -ForegroundColor Cyan
& kubectl apply -f $manifest
if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar o manifesto corrigido.' }

# Dá ao controller alguns segundos para realizar sozinho o RollingUpdate.
$pod = $null
$podCorrect = $false
for ($i = 0; $i -lt 15; $i++) {
    $pod = Get-PodObject
    if ($null -ne $pod) {
        $container = $pod.spec.containers | Where-Object { $_.name -eq 'postgres' } | Select-Object -First 1
        $commandCount = @($container.command | Where-Object { $_ }).Count
        $argsJoined = @($container.args) -join "`n"
        if ($commandCount -eq 0 -and $argsJoined -eq ($expectedArgs -join "`n")) {
            $podCorrect = $true
            break
        }
    }
    Start-Sleep -Seconds 1
}

if (-not $podCorrect) {
    if ($null -eq $pod) {
        Write-Host 'O controller está recriando o Pod; aguardando a nova instância...' -ForegroundColor Yellow
    } else {
        Write-Host 'O Pod existente ainda tem a especificação antiga. Vou substituí-lo; o PVC Bound será mantido.' -ForegroundColor Yellow
        & kubectl delete pod $podName -n $namespace --wait=true
        if ($LASTEXITCODE -ne 0) { throw 'Não foi possível excluir somente o Pod antigo.' }
    }
}

Write-Host '[2/4] Confirmando a criação do Pod com a especificação nova...' -ForegroundColor Cyan
$pod = $null
for ($i = 0; $i -lt 30; $i++) {
    $pod = Get-PodObject
    if ($null -ne $pod) {
        $container = $pod.spec.containers | Where-Object { $_.name -eq 'postgres' } | Select-Object -First 1
        $commandCount = @($container.command | Where-Object { $_ }).Count
        $argsJoined = @($container.args) -join "`n"
        if ($commandCount -eq 0 -and $argsJoined -eq ($expectedArgs -join "`n")) { break }
    }
    Start-Sleep -Seconds 1
}

if ($null -eq $pod) { Show-Diagnostics; throw 'O StatefulSet não recriou postgres-0 em 30 segundos.' }
$container = $pod.spec.containers | Where-Object { $_.name -eq 'postgres' } | Select-Object -First 1
if (@($container.command | Where-Object { $_ }).Count -gt 0 -or ((@($container.args) -join "`n") -ne ($expectedArgs -join "`n"))) {
    Show-Diagnostics
    throw 'O novo Pod ainda não recebeu args corretos. Não continuei para evitar novos ciclos.'
}

Write-Host 'Pod com ENTRYPOINT original preservado:' -ForegroundColor Green
Write-Host "  command: vazio"
Write-Host "  args: $($container.args -join ' ')"
Write-Host '[3/4] Aguardando prontidão por no máximo 90 segundos...' -ForegroundColor Cyan

$ready = $false
for ($i = 0; $i -lt 45; $i++) {
    $pod = Get-PodObject
    if ($null -ne $pod) {
        $cs = $pod.status.containerStatuses | Where-Object { $_.name -eq 'postgres' } | Select-Object -First 1
        if ($null -ne $cs -and $cs.ready) { $ready = $true; break }
        $reason = $null
        if ($null -ne $cs -and $null -ne $cs.state.waiting) { $reason = $cs.state.waiting.reason }
        if ($reason -in @('CrashLoopBackOff', 'ErrImagePull', 'ImagePullBackOff')) { break }
    }
    Start-Sleep -Seconds 2
}

if (-not $ready) {
    Show-Diagnostics
    throw 'PostgreSQL ainda não está Ready. Diagnóstico exibido acima; o PVC foi preservado.'
}

Write-Host '[4/4] PostgreSQL Ready. Testando banco e tabela app.alunos...' -ForegroundColor Cyan
& kubectl exec $podName -n $namespace -- pg_isready -h 127.0.0.1 -U postgres -d g7_academia
if ($LASTEXITCODE -ne 0) { Show-Diagnostics; throw 'pg_isready falhou.' }
& kubectl exec $podName -n $namespace -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U postgres -d g7_academia -c "SELECT count(*) AS total_alunos FROM app.alunos;"'
if ($LASTEXITCODE -ne 0) { Show-Diagnostics; throw 'A consulta à tabela app.alunos falhou.' }

Write-Host "`n=== SUCESSO: PostgreSQL está Ready e o PVC foi mantido ===" -ForegroundColor Green
& kubectl get pods,pvc,services -n $namespace
