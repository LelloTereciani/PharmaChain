ifneq (,$(wildcard .env))
include .env
export
endif

RPC_URL ?= http://127.0.0.1:8545
DEPLOY_SCRIPT := script/DeployPharmaChain.s.sol:DeployPharmaChain
ROLES_SCRIPT := script/ConfigurePharmaChainRoles.s.sol:ConfigurePharmaChainRoles

.PHONY: help build test gas deploy roles clean

help:
	@echo "Targets disponíveis:"
	@echo "  make build   - Compila o projeto"
	@echo "  make test    - Roda a suíte de testes"
	@echo "  make gas     - Roda testes com gas report"
	@echo "  make deploy  - Deploy do implementation + proxy em Anvil"
	@echo "  make roles   - Configura roles no proxy (usa PHARMA_PROXY do .env)"
	@echo "  make clean   - Limpa artefatos de build"

build:
	forge build

test:
	forge test -vv

gas:
	forge test --gas-report

deploy:
	forge script $(DEPLOY_SCRIPT) --rpc-url $(RPC_URL) --broadcast -vv

roles:
	@test -n "$(PHARMA_PROXY)" || (echo "Erro: defina PHARMA_PROXY no .env" && exit 1)
	forge script $(ROLES_SCRIPT) --rpc-url $(RPC_URL) --broadcast -vv

clean:
	rm -rf out cache
