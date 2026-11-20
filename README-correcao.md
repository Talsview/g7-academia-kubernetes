# Correção do script da Etapa 3

Substitua o arquivo existente `scripts/k8s/etapa3-aplicacao.ps1` por este arquivo, mantendo o mesmo caminho.

Correções incluídas:
- Verificação do nó e do PostgreSQL usando JSON + ConvertFrom-Json, sem JSONPath com aspas frágeis no Windows PowerShell.
- Localização automática de `minikube.exe` em `C:\Program Files\Kubernetes\Minikube` quando não estiver no PATH.
- Construção das imagens chamando o caminho resolvido do Minikube.

Não altera os manifestos, o banco, o PVC nem os Secrets existentes.

Depois, na raiz do repositório, execute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\etapa3-aplicacao.ps1
```
