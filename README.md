# Wormhole to LayerZero migration library

This repository includes init library functions for migrating USDS Wormhole bridge (and its Wormhole-based cross-chain governance) to a new LayerZero USDS bridge (and its LayerZero-based cross-chain governance).

## Migration steps

The migration is assumed to be executed over the course of 3 spells, as outlined below:

### Spell 0

- Upgrade the NTT Manager implementation on Ethereum to allow governance to pause outbound transfers and to transfer the escrowed tokens
- Upgrade the NTT Manager implementation on Solana to allow governance to pause outbound transfers and to transfer the mint authority

### Spell 1

- Pause outbound transfers on the Ethereum NTT Manager
- Pause outbound transfers on the Solana NTT Manager

After the execution of spell 1 and before the execution of spell 2, it is assumed that all in-flight transfers have been relayed to Ethereum or Solana. This will have been done manually if needed.

Prior to the execution of Spell 2, the new LZ Governance OApp and the new LZ USDS Token bridge will have been deployed and configured (including setting its owner, delegate, peer and enforced options). The Solana side of the LZ USDS Token bridge will have been paused and will have had its rate limit configuration set to its intended non-zero value. The Ethereum side of the LZ USDS Token bridge should remain unpaused and have its rate limit configuration set to zero (it will be set to a non-zero value in Spell 2).

### Spell 2

- Transfer the locked tokens from the Ethereum NTT Manager to the Ethereum side of the LZ Token bridge
- Set the rate limits of the Ethereum side of the LZ Token bridge to a non-zero value
- Transfer the mint authority from the Solana NTT Manager program's PDA to the Solana LZ Token bridge program's PDA
- Unpause the Solana side of the LZ Token bridge

## Migration functions

Each of the above spells requires calling one dedicated function in the library. The init functions that take a struct as inputs are meant to be used on testnet as they allow specifying the relevant addresses for the pre-existing testnet wormhole deployment. The init functions that take a list of `address`, `bytes32` and integers as inputs are meant to be used in production as they use hardcoded values for the known mainnet wormhole deployment.

## Dependencies

The `lib` directory contains the following dependencies relevant for the migration:

- `sky-ntt-migration`: contains the new NTT implementations upgraded in spell 0.
- `sky-oapp-gov`: points to [@sky-ecosystem/sky-oapp-oft#governance](https://github.com/sky-ecosystem/sky-oapp-oft/tree/governance) and contains the EVM and SVM Governance OApp code.
- `sky-oapp-oft`: points to [@sky-ecosystem/sky-oapp-oft#milestone-1](https://github.com/sky-ecosystem/sky-oapp-oft/tree/milestone-1) and contains the EVM LZ Token Bridge code.

## EVM Tests

These tests cover the Ethereum-side of the migration, but do not cover any cross-chain message passing or Solana-side state changes.

```
forge test
```

## Solana Tests

Partial Solana tests are provided to help validate that the Wormhole and LayerZero payloads (built in Solidity by the library) are properly formed. These tests do not cover the execution of the target Solana program and should be complemented by proper end-to-end integration tests (not provided as part of this repo).

### Solana Wormhole Tests

Generate sample Wormhole governance payloads using the library code and store those in `test/solana/wormhole/payloads.rs`:

```
forge test -vvvv --match-test testMigrationStep2 2>&1 | \
grep 'emit LogMessagePublished' | \
awk -F'param3: 0x' '{print $2}' | \
awk -F',' '{print $1}' | \
awk '{printf "pub const PAYLOAD%d: &str = \"%s\";\n", NR-1, $0}' > test/solana/wormhole/payloads.rs
```

Copy the generated payloads and the wormhole governance tests that use them into the `lib/sky-ntt-migration/solana/programs/wormhole-governance` dependency:

```
mkdir lib/sky-ntt-migration/solana/programs/wormhole-governance/tests
cp -r test/solana/wormhole/* lib/sky-ntt-migration/solana/programs/wormhole-governance/tests/
```

Run the tests:

```
cd lib/sky-ntt-migration/solana/programs/wormhole-governance
cargo test test_migration
```

### Solana LayerZero Tests

Generate a sample LayerZero governance payload using the library code and store it in `test/solana/layerzero/payloads.rs`:

```
forge test -vvvv --match-test testMigrationStep2 2>&1 | \
grep 'emit PacketSent' | \
head -n 1 | \
awk -F'encodedPayload: 0x' '{print $2}' | \
awk -F',' '{print substr($1, 227)}' | \
awk '{printf "pub const PAYLOAD0: &str = \"%s\";\n", $0}' > test/solana/layerzero/payloads.rs
```

Copy the generated payloads and the wormhole governance tests that use them into the `lib/sky-oapp-gov/programs/governance` dependency:

```
cp -r test/solana/layerzero/* lib/sky-oapp-gov/programs/governance/tests/
```

Run the tests:

```
cd lib/sky-oapp-gov/programs/governance
cargo test test_migration
```
