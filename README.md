# Wormhole to LayerZero migration library

This repository includes init library functions for migrating the USDS Wormhole bridge (and its Wormhole-based cross-chain governance) to a new LayerZero USDS bridge (and its LayerZero-based cross-chain governance).

## Migration steps

The migration is planned to be executed in two spells, as outlined below:

### Spell 0

- Upgrade the NTT Manager implementation on Ethereum to immediately prevent outbound transfers and to allow governance to transfer the escrowed tokens
- Upgrade the NTT Manager implementation on Solana to immediately prevent outbound transfers and to allow governance to transfer the mint authority
- Reduce the Governance Delay to 16 hours

To prevent outbound transfers, the new EVM NTT Manager implementation has its `transfer` functions removed, and the new SVM NTT Manager implementation has its `transfer_burn` function removed.

After the execution of Spell 0, we check if there are any pending transfers in the inbound and outbound queues. Assuming that is not the case, Spell 1 can be voted on without further delay. In the unlikely scenario where the daily limit of the bridge has been reached and some transfers remain queued after the execution of Spell 0, voting on Spell 1 must be delayed long enough to ensure that the spell does not execute before both the outbound and inbound queues are cleared, which can take a few days in the worst case.

If there are any in-flight transfers that still need to be relayed to the other side of the bridge after the execution of Spell 0, those might need to be manually relayed before Spell 1 is executed.

Prior to the execution of Spell 1, the new LZ Governance OApp and the new LZ USDS Token bridge will have been deployed and configured (including setting its owner, delegate, peer, and enforced options). The Solana side of the LZ USDS Token bridge will already have had its rate limit configuration set to its intended non-zero value, and will thereby have been effectively already activated. The Ethereum side of the LZ USDS Token bridge will have its rate limit configuration set to zero (it will be set to a non-zero value in Spell 1, see below). Users are highly advised to refrain from using the bridge before Spell 1 has been executed.

### Spell 1

- Transfer the locked tokens from the Ethereum NTT Manager to the Ethereum side of the LZ Token bridge
- Set the rate limits of the Ethereum side of the LZ Token bridge to a non-zero value
- Transfer the mint authority from the Solana NTT Manager program's PDA to the Solana LZ Token bridge program's PDA

## Migration functions

Each of the two spells above requires calling a dedicated init function in the library. The init functions come in two sets: variants of the functions meant to be used on testnet as they allow specifying the relevant addresses for the pre-existing testnet wormhole deployment and variants of the functions meant to be used in production as they use hardcoded values for the known mainnet wormhole deployment.

## Dependencies

The `lib` directory contains the following dependencies relevant for the migration:

- `sky-ntt-migration`: contains the new NTT implementations the NTT Managers are upgraded to in Spell 0.
- `sky-oapp-gov`: points to [@sky-ecosystem/sky-oapp-oft#governance](https://github.com/sky-ecosystem/sky-oapp-oft/tree/governance) and contains the EVM and SVM Governance OApp code.
- `sky-oapp-oft`: points to [@sky-ecosystem/sky-oapp-oft#milestone-1](https://github.com/sky-ecosystem/sky-oapp-oft/tree/milestone-1) and contains the EVM LZ Token Bridge code.

## EVM Tests

These tests cover the Ethereum side of the migration, but do not test any cross-chain message passing or Solana side state changes.

```
forge test
```
