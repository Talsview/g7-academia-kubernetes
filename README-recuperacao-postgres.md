# Recuperação do PostgreSQL — G7 Academia

Este pacote corrige o manifesto do StatefulSet para preservar o `ENTRYPOINT` da imagem oficial `postgres:16-alpine` e usa `RollingUpdate` explicitamente. O script de recuperação substitui apenas o Pod antigo quando necessário, mantém o PVC existente e limita a espera por prontidão a 90 segundos, exibindo logs/eventos automaticamente em caso de falha.

## Como aplicar

1. Extraia o conteúdo deste ZIP na raiz do repositório `g7-academia-kubernetes`, mesclando as pastas `k8s` e `scripts`.
2. Abra o PowerShell na raiz do projeto.
3. Execute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\k8s\etapa2-recuperar-postgres.ps1
```

## O que o script faz

- Confere namespace, Secret e PVC existente em `Bound`.
- Aplica `k8s/12-postgres-statefulset.yaml` com `args` (sem sobrescrever `ENTRYPOINT`) e `updateStrategy: RollingUpdate`.
- Aguarda até 15 segundos que o StatefulSet substitua o Pod sozinho; se ele continuar com a configuração antiga, exclui somente `postgres-0`.
- Confirma que o Pod novo não define `command` e usa os `args` esperados.
- Aguarda até 90 segundos pela prontidão; se falhar, mostra logs atuais/anteriores e eventos recentes.
- Testa `pg_isready` e consulta `app.alunos`.

**O script não apaga nem recria PVC, Secret ou namespace.** Os scripts de inicialização do PostgreSQL só são executados automaticamente quando o diretório de dados está vazio; reiniciar o Pod com o mesmo PVC não apaga dados.
