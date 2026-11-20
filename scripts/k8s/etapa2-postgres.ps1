$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$namespace = 'g7-academia'
$envFile = Join-Path $projectRoot '.env'
$exampleEnv = Join-Path $projectRoot '.env.example'

Write-Host '=== G7 Academia | Etapa 2: PostgreSQL no Kubernetes ===' -ForegroundColor Cyan

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw 'kubectl não foi encontrado. Feche e reabra o PowerShell e confira: kubectl version --client'
}

& kubectl get namespace $namespace *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Namespace '$namespace' não encontrado. Execute primeiro a Etapa 1."
}

if (-not (Test-Path $envFile)) {
    if (-not (Test-Path $exampleEnv)) {
        throw '.env e .env.example não foram encontrados na raiz do projeto.'
    }
    Copy-Item $exampleEnv $envFile
    Write-Host 'Foi criado .env a partir de .env.example.' -ForegroundColor Yellow
    Write-Host 'Confira/edite as senhas em .env e execute este script novamente.' -ForegroundColor Yellow
    exit 2
}

# Lê somente as variáveis necessárias para criar o Secret do Kubernetes.
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

$requiredKeys = @('POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD', 'APP_DB_USER', 'APP_DB_PASSWORD', 'LEITOR_DB_USER', 'LEITOR_DB_PASSWORD')
foreach ($key in $requiredKeys) {
    if (-not $envValues.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($envValues[$key])) {
        throw "A variável $key está ausente ou vazia no .env. Confira o arquivo e tente novamente."
    }
}

if ($envValues['POSTGRES_DB'] -ne 'g7_academia') {
    throw "POSTGRES_DB deve ser g7_academia, pois o backup SQL do projeto utiliza esse nome."
}
if ($envValues['POSTGRES_USER'] -ne 'postgres') {
    throw "POSTGRES_USER deve ser postgres para corresponder à configuração de inicialização do projeto."
}

# Cria um arquivo temporário fora do repositório para não gravar credenciais em YAML versionado.
$tempSecretEnv = Join-Path $env:TEMP ('g7-k8s-secret-' + [guid]::NewGuid().ToString('N') + '.env')
$secretLines = foreach ($key in $requiredKeys) { "$key=$($envValues[$key])" }
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($tempSecretEnv, [string[]]$secretLines, $utf8NoBom)

try {
    Write-Host '[1/5] Criando/atualizando Secret do PostgreSQL...' -ForegroundColor Cyan
    $secretArgs = @('create', 'secret', 'generic', 'g7-db-secret', '--namespace', $namespace, "--from-env-file=$tempSecretEnv", '--dry-run=client', '-o', 'yaml')
    $secretYaml = & kubectl @secretArgs
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível gerar o Secret do Kubernetes.' }
    $secretYaml | & kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível aplicar o Secret do Kubernetes.' }
}
finally {
    Remove-Item -LiteralPath $tempSecretEnv -Force -ErrorAction SilentlyContinue
}

$manifests = @(
    '10-postgres-config.yaml',
    '11-postgres-init.yaml',
    '13-postgres-service.yaml',
    '12-postgres-statefulset.yaml'
)

foreach ($manifest in $manifests) {
    $manifestPath = Join-Path $projectRoot (Join-Path 'k8s' $manifest)
    if (-not (Test-Path $manifestPath)) { throw "Manifesto não encontrado: $manifestPath" }
    Write-Host "Aplicando $manifest ..." -ForegroundColor Cyan
    & kubectl apply -f $manifestPath
    if ($LASTEXITCODE -ne 0) { throw "Falha ao aplicar $manifest." }
}

Write-Host '[5/5] Aguardando o PostgreSQL ficar pronto (pode levar alguns minutos na primeira inicialização)...' -ForegroundColor Cyan
& kubectl rollout status statefulset/postgres -n $namespace --timeout=360s
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Diagnóstico do Pod:' -ForegroundColor Yellow
    & kubectl get pods,pvc -n $namespace
    & kubectl describe pod postgres-0 -n $namespace
    & kubectl logs postgres-0 -n $namespace --all-containers=true --tail=100
    throw 'O PostgreSQL não ficou pronto. Envie a saída do diagnóstico antes de tentar apagar o PVC.'
}

Write-Host "`n=== Recursos implantados ===" -ForegroundColor Green
& kubectl get pods,pvc,services -n $namespace
Write-Host "`n=== Teste de conexão e dados do G7 ===" -ForegroundColor Green
& kubectl exec postgres-0 -n $namespace -- psql -U postgres -d g7_academia -c 'SELECT current_database() AS banco, version();'
if ($LASTEXITCODE -ne 0) { throw 'O PostgreSQL iniciou, mas a consulta de validação falhou.' }
& kubectl exec postgres-0 -n $namespace -- psql -U postgres -d g7_academia -c 'SELECT count(*) AS total_alunos FROM app.alunos;'
if ($LASTEXITCODE -ne 0) { throw 'A tabela app.alunos não foi encontrada. Verifique os logs de inicialização.' }

Write-Host "`nEtapa 2 concluída. O Service interno é db-service:5432." -ForegroundColor Green
Write-Host 'O PostgreSQL não foi exposto publicamente; o acesso é interno ao cluster Kubernetes.'
