$ErrorActionPreference = 'Stop'

Write-Host '=== G7 Academia | Corrigir CORS do backend ===' -ForegroundColor Cyan
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$backendDir = Join-Path $projectRoot 'backend'
$deploymentFile = Join-Path $projectRoot 'k8s\23-backend-deployment.yaml'
$minikubeExe = 'C:\Program Files\Kubernetes\Minikube\minikube.exe'
$newImage = 'g7-academia-backend:stage4-cors'

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw 'kubectl não encontrado no PATH.'
}
if (-not (Test-Path $minikubeExe)) {
    $cmd = Get-Command minikube -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { throw "minikube.exe não encontrado em $minikubeExe e comando minikube ausente no PATH." }
    $minikubeExe = $cmd.Source
}
if (-not (Test-Path (Join-Path $backendDir 'Dockerfile'))) { throw 'Dockerfile do backend não encontrado.' }
if (-not (Test-Path $deploymentFile)) { throw 'k8s\23-backend-deployment.yaml não encontrado. Extraia o pacote da Etapa 4 na raiz do projeto.' }

Write-Host '[1/4] Construindo backend com CORS restrito para URLs locais do Minikube...' -ForegroundColor Cyan
& $minikubeExe image build -t $newImage $backendDir
if ($LASTEXITCODE -ne 0) { throw 'Falha ao construir a imagem do backend.' }

Write-Host '[2/4] Atualizando a tag da imagem no manifesto...' -ForegroundColor Cyan
$lines = [System.IO.File]::ReadAllLines($deploymentFile)
$imageMatches = 0
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^(\s*)image:\s*g7-academia-backend:stage4\s*$') {
        $indent = $Matches[1]
        $lines[$i] = $indent + 'image: ' + $newImage
        $imageMatches++
    }
}
if ($imageMatches -eq 1) {
    [System.IO.File]::WriteAllLines($deploymentFile, $lines, [System.Text.UTF8Encoding]::new($false))
} elseif ($imageMatches -eq 0 -and ($lines -join "`n") -notmatch [regex]::Escape($newImage)) {
    throw 'A imagem esperada g7-academia-backend:stage4 não foi encontrada no Deployment. Nenhum manifesto foi aplicado.'
} elseif ($imageMatches -gt 1) {
    throw 'Mais de uma linha de imagem do backend foi encontrada. Manifesto não alterado.'
}

Write-Host '[3/4] Aplicando Deployment atualizado...' -ForegroundColor Cyan
& kubectl apply -f $deploymentFile
if ($LASTEXITCODE -ne 0) { throw 'kubectl apply falhou.' }

Write-Host '[4/4] Aguardando as duas réplicas do backend...' -ForegroundColor Cyan
& kubectl rollout status deployment/backend -n g7-academia --timeout=180s
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Pods e eventos do backend:' -ForegroundColor Yellow
    & kubectl get pods -n g7-academia -o wide
    & kubectl get events -n g7-academia --sort-by=.lastTimestamp | Select-Object -Last 15
    throw 'O rollout do backend não foi concluído. Consulte os logs dos Pods novos.'
}

& kubectl get deployment backend -n g7-academia
& kubectl get pods -n g7-academia -l app.kubernetes.io/name=backend
Write-Host '=== CORS atualizado. JWT e regras de perfil foram preservados. ===' -ForegroundColor Green
