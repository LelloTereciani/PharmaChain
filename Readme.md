# PharmaChainERP

Contrato inteligente para rastreabilidade farmacêutica com padrão ERC-1155, controle de acesso por papéis (RBAC), trilha documental e fluxo logístico com reconciliação de massa.

## Escopo funcional

O contrato `PharmaChainERP` implementa:
- criação de lotes com validade (`mintBatch`);
- aprovação e reprovação por qualidade (`releaseBatch`, `rejectBatch`);
- recall sanitário (`executeRecall`);
- anexos documentais de compliance (`COA`, `NFE`, `CTE`, `NCR`, `LOSS_REPORT`);
- despacho e recebimento com validação de custódia (`shipBatch`, `receiveShipment`);
- bloqueio de transferência direta de tokens (`safeTransferFrom`/`safeBatchTransferFrom`);
- upgrade UUPS com autorização por `ADMIN_ROLE`.

## Papéis (RBAC)

- `ADMIN_ROLE`: governança, pause/unpause e upgrades.
- `ORACLE_ROLE`: atualização de licenças de atores.
- `PRODUCTION_ROLE`: criação de lotes e operações de produção.
- `QUALITY_ROLE`: liberação, reprovação e recall.
- `LOGISTICS_ROLE`: fluxo logístico e documentos de transporte.

## Regras de segurança e compliance

- validação de existência de lote em operações sensíveis;
- validação de entradas (GTIN, hashes, URIs, endereços e quantidades);
- restrição de circulação para lote em `RECALL`, `REJECTED`, `QUARANTINE` e vencido;
- proteção contra reentrância em fluxos críticos (`nonReentrant`);
- pausa global operacional (`pauseContract`/`unpauseContract`);
- política de transições válidas de status.

## Estrutura do projeto

- Contrato principal: `src/Cannabis.sol`
- Testes base/shared: `test/PharmaChainERPBase.t.sol`
- Testes unitários: `test/PharmaChainERP.Unit.t.sol`
- Testes de integração: `test/PharmaChainERP.Integration.t.sol`
- Testes fuzz: `test/PharmaChainERP.Fuzz.t.sol`
- Testes de gas budget: `test/PharmaChainERP.Gas.t.sol`
- Testes de segurança: `test/PharmaChainERP.Security.t.sol`
- Scripts de deploy/configuração: `script/DeployPharmaChain.s.sol`, `script/ConfigurePharmaChainRoles.s.sol`

## Ambiente (Foundry)

Dependências:
- `openzeppelin-contracts-upgradeable` `v4.9.6`
- `openzeppelin-contracts` `v4.9.6`
- `forge-std`

Comandos úteis:
```bash
make build
make test
make gas
```

## Deploy e configuração

Fluxo local com Anvil:
```bash
anvil
cp .env.example .env
source .env
make deploy
# atualizar PHARMA_PROXY no .env com o proxy retornado
source .env
make roles
```

Para testnet, use seu `RPC_URL` e `PRIVATE_KEY` no `.env`.

## Testes e cobertura

Status atual da suíte:
- `43` testes passando (`forge test -vv`)
- sem falhas

Cobertura atual de `src/Cannabis.sol` (medida com `forge coverage` em 20/02/2026):
- linhas: `99.41%` (`168/169`)
- statements: `96.59%` (`170/176`)
- branches: `87.62%` (`92/105`)
- funções: `100%` (`28/28`)

Execução por categoria:
```bash
forge test --match-path test/PharmaChainERP.Unit.t.sol
forge test --match-path test/PharmaChainERP.Integration.t.sol
forge test --match-path test/PharmaChainERP.Fuzz.t.sol
forge test --match-path test/PharmaChainERP.Gas.t.sol
forge test --match-path test/PharmaChainERP.Security.t.sol
```

## Observações

- O contrato é upgradeável (UUPS), então o deploy recomendado em ambientes reais é via proxy.
- O arquivo `tests/Cannabis_Test.sol` é legado e não faz parte da suíte ativa em `test/`.
