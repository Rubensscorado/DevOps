# API DevOps de Tarefas: pipeline CI/CD com GitHub Actions, Docker, Amazon ECR e EC2

## 1. Descrição da aplicação e seu objetivo

API REST em Python (FastAPI) para gerenciar uma lista de tarefas em memória. O objetivo do projeto é demonstrar uma esteira completa de integração e entrega contínua: qualquer alteração aprovada e incorporada à branch `main` é testada, empacotada em uma imagem Docker, publicada no Amazon ECR e implantada automaticamente em uma instância Amazon EC2.

Endpoints principais:

| Método | Rota | Descrição |
|---|---|---|
| GET | `/` | Mensagem de boas-vindas |
| GET | `/health` | Verificação de saúde da API |
| GET | `/version` | Versão da aplicação e commit que gerou a imagem em execução |
| GET | `/tasks` | Lista as tarefas |
| POST | `/tasks` | Cria uma tarefa |
| PATCH | `/tasks/{id}/done` | Marca uma tarefa como concluída |

## 2. Tecnologias utilizadas

- Python 3.13 e FastAPI (servidor Uvicorn)
- Pytest e pytest-cov (testes e cobertura mínima de 90%)
- Ruff (análise estática e formatação)
- Docker
- GitHub e GitHub Actions
- Amazon ECR (registro privado de imagens)
- Amazon EC2 com Amazon Linux 2023
- IAM Role (LabInstanceProfile) para a instância ler imagens do ECR

## 3. Execução local

```bash
python -m venv .venv
# Windows (PowerShell): .\.venv\Scripts\Activate.ps1
# Linux/macOS: source .venv/bin/activate
python -m pip install --requirement requirements-dev.txt
python -m pytest --cov=app --cov-report=term-missing
python -m uvicorn app.main:app --reload
```

A API fica disponível em `http://127.0.0.1:8000` e a documentação interativa em `http://127.0.0.1:8000/docs`.

## 4. Construção e execução da imagem Docker

```bash
docker build --tag devops-python-api:local .
docker run --detach --name devops-api --publish 8000:8000 devops-python-api:local
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/version
docker rm --force devops-api
```

Para simular o commit no endpoint `/version`, adicione `-e APP_COMMIT=abc1234` ao `docker run`. Sem essa variável, o valor padrão é `local`.

## 5. Pipeline de integração contínua (CI)

Arquivo: `.github/workflows/ci.yml`.

- **Gatilho:** `pull_request` para a `main` (opened, synchronize, reopened) e `workflow_dispatch`.
- **Job `Qualidade e testes`:** baixa o código, configura o Python, instala as dependências, executa `ruff check`, `ruff format --check` e `pytest` com cobertura mínima de 90%.
- **Job `Build e teste do container`:** depende do job anterior (`needs`), constrói a imagem Docker, sobe o contêiner e valida o endpoint `/health`.
- Se os testes falharem, o segundo job não é executado e o Pull Request não pode ser mesclado, porque os dois checks são exigidos pela regra de proteção da `main`.

## 6. Pipeline de entrega contínua (CD)

Arquivo: `.github/workflows/deploy.yml`, disparado em `push` na `main` (merge de Pull Request) e em `workflow_dispatch`.

1. **Job `Testes`:** ruff e pytest.
2. **Job `Build, publicacao no ECR e deploy na EC2`** (`needs: tests`, portanto não roda se os testes falharem):
   - configura as credenciais da AWS (`aws-actions/configure-aws-credentials`);
   - faz login no Amazon ECR (`aws-actions/amazon-ecr-login`);
   - constrói a imagem e a publica no ECR com a tag igual ao SHA do commit;
   - abre uma conexão SSH com a EC2 e executa o script `scripts/deploy.sh`;
   - testa a API pelo IP público e confere se `/version` devolve o SHA do commit.

O script `scripts/deploy.sh` roda na EC2 e: autentica o Docker no ECR usando a IAM Role da instância, baixa a imagem do commit, remove o contêiner anterior, inicia o novo (`--restart unless-stopped`, porta 80 para 8000, variável `APP_COMMIT`) e verifica o `/health` em loop.

Nenhum comando é executado manualmente na instância durante o deploy.

### Segredos do GitHub (somente os nomes)

`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `EC2_HOST`, `EC2_USER`, `EC2_SSH_KEY`. Nenhuma credencial é versionada no repositório.

## 7. Arquitetura de implantação

```
Desenvolvedor
    |  branch + Pull Request
    v
GitHub  --(pull_request)--> CI: ruff + pytest + build/teste do contêiner
    |
    |  merge na main (push)
    v
GitHub Actions (deploy.yml)
    |-- Testes
    |-- docker build  (tag = SHA do commit)
    |-- docker push -----------------> Amazon ECR (repositório privado: devops-python-api)
    |-- SSH + scripts/deploy.sh ------> EC2 (Amazon Linux 2023, Docker)
                                          |-- login no ECR via IAM Role (LabInstanceProfile)
                                          |-- docker pull da imagem do commit
                                          |-- docker run -p 80:8000 -e APP_COMMIT=<sha>
                                          v
                                   API publicada na porta 80
```

Rede: Security Group `devops-api-sg` com entrada TCP 22 (SSH, usado pelo GitHub Actions) e TCP 80 (HTTP da API). Região: us-east-1.

## 8. Endereço de acesso à API publicada

`http://18.207.122.44`

Observação: o ambiente é o AWS Academy Learner Lab. O IP público da instância muda quando o laboratório é reiniciado, e os recursos são desligados ao final da avaliação. O endereço acima corresponde à execução registrada nas evidências.

## 9. Evidências da execução das pipelines

| # | Evidência | Arquivo |
|---|---|---|
| 01 | CI aprovada no Pull Request #1 | `docs/evidencias/01-ci-aprovada-pr.png` |
| 02 | Imagens no ECR com a tag do commit | `docs/evidencias/02-ecr-imagens.png` |
| 03 | Deploy executado com sucesso | `docs/evidencias/03-deploy-sucesso.png` |
| 04 | Contêiner em execução na EC2 (`docker ps` e `curl /version`) | `docs/evidencias/04-ec2-docker-ps-curl.png` |
| 05 | API publicada na versão 1.0.0 | `docs/evidencias/05-version-1-0-0.png` |
| 06 | API publicada na versão 1.1.0 | `docs/evidencias/06-version-1-1-0.png` |
| 07 | Deploy disparado automaticamente pelo merge (pushed by) | `docs/evidencias/07-deploy-disparado-merge.png` |
| 08 | Pull Request #2 com checks obrigatórios (proteção da main) | `docs/evidencias/08-pr2-checks-obrigatorios.png` |
| 09 | Security Group da instância | `docs/evidencias/09-security-group.png` |
| 10 | Instância EC2 em execução | `docs/evidencias/10-instancia-ec2.png` |

Pull Requests:

- PR #1 (pipeline CI/CD): https://github.com/Rubensscorado/DevOps/pull/1
- PR #2 (atualização para 1.1.0): https://github.com/Rubensscorado/DevOps/pull/2

### Atualização automática (Etapa 7)

| Versão | Commit exibido em `/version` |
|---|---|
| 1.0.0 | `d9fbb40683d96b40b376a651be0aec5978d39972` |
| 1.1.0 | `3e3255261b977e3b9b10a0b1a8fd2448ae2c4a76` |

O segundo deploy foi disparado pelo merge do Pull Request #2, sem nenhum comando manual na EC2.

## 10. Como verificar a versão implantada

```bash
curl http://18.207.122.44/version
```

Resposta esperada (exemplo da versão 1.1.0):

```json
{"version":"1.1.0","commit":"3e3255261b977e3b9b10a0b1a8fd2448ae2c4a76"}
```

O campo `commit` é o SHA do commit que gerou a imagem em execução. Ele deve coincidir com o commit exibido na execução do workflow **Deploy API** e com a tag da imagem no Amazon ECR.
