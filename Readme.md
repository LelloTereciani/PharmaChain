# PharmaChainERP

**Classification:** Independent Project · Study Project · Experimental

A Solidity and Foundry study project for pharmaceutical batch traceability using an ERC-1155-based model, role-based access control, documents, quality status transitions, and a simulated logistics workflow.

The main contract is named `PharmaChainERP` and is implemented in [src/Cannabis.sol](src/Cannabis.sol). The filename is retained from the original study structure; it does not describe a commercial cannabis product.

## Scope and limitations

- Local development and testnet-oriented experimentation only.
- The repository does not claim commercial deployment, external users, regulatory approval, or an external audit.
- UUPS upgradeability and privileged roles are included as subjects for study and require independent review before any real use.
- Test and coverage figures are repository snapshots and should be reproduced locally.

## Project structure

- Contract: `src/Cannabis.sol`
- Foundry tests: `test/`
- Deployment scripts: `script/`
- Environment template: `.env.example`

## Development

Requirements: Foundry and Solidity 0.8.20+.

```bash
cp .env.example .env
make build
make test
make gas
```

For local deployment, use Anvil and follow the Makefile targets. Never commit populated `.env` files or private keys.

## License

MIT. See [LICENSE](LICENSE).

## Author

Lello Tereciani
