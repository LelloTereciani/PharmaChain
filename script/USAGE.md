# Deploy and Configure (Anvil)

## 1) Export env vars

```bash
cp .env.example .env
source .env
```

## 2) Deploy implementation + proxy

```bash
forge script script/DeployPharmaChain.s.sol:DeployPharmaChain \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vv
```

Use the printed `PharmaChainERP proxy` as `PHARMA_PROXY` in your `.env`.

## 3) Configure roles (optional)

```bash
source .env
forge script script/ConfigurePharmaChainRoles.s.sol:ConfigurePharmaChainRoles \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vv
```

## 4) Run tests

```bash
forge test -vv
```

Gas report:

```bash
forge test --gas-report
```
