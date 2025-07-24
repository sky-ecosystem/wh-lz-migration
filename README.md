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

Prior to the execution of Spell 2, the new LZ Governance OApp and the new LZ USDS Token bridge will have been deployed and configured (including setting its owner, delegate, peer, enforced options, and rate limit configuration in the case of the token bridge). The LZ USDS Token bridge will have been paused on both the Ethereum and Solana side.

### Spell 2

- Transfer the locked tokens from the Ethereum NTT Manager to the Ethereum side of the LZ Token bridge
- Unpause the Ethereum side of the LZ Token bridge
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
