// SPDX-FileCopyrightText: © 2025 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.8.0;

library SamplePayloads {

    // python3 -c "import base58; print(base58.b58decode('BPFLoaderUpgradeab1e11111111111111111111111').hex())"
    bytes32 constant BFT_LOADER_UPGRADABLE_ADDR = 0x02a8f6914e88a1b0e210153ef763ae2b00c2b93d16c124d2c0537a1004800000;
    // python3 -c "import base58; print(base58.b58decode('SysvarC1ock11111111111111111111111111111111').hex())"
    bytes32 constant SYSVAR_CLOCK_ADDR          = 0x06a7d51718c774c928566398691d5eb68b5eb8a39b4b6d5c73555b2100000000;
    // python3 -c "import base58; print(base58.b58decode('SysvarRent111111111111111111111111111111111').hex())"
    bytes32 constant SYSVAR_RENT_ADDR           = 0x06a7d517192c5c51218cc94c3d4af17f58daee089ba1fd44e3dbd98a00000000;

    // python3 -c "import base58; print(base58.b58decode('SCCGgsntaUPmP6UjwUBNiQQ83ys5fnCHdFASHPV6Fm9').hex())"
    bytes32 constant GOVERNANCE_PROGRAM_ID      = 0x06742d7ca523a03aaafe48abab02e47eb8aef53415cb603c47a3ccf864d86dc0;
    // python3 -c "import base58; print(base58.b58decode('STTUVCMPuNbk21y1J6nqEGXSQ8HKvFmFBKnCvKHTrWn').hex())"
    bytes32 constant NTT_PROGRAM_ID             = 0x06856f43abf4aaa4a26b32ae8ea4cb8fadc8e02d267703fbd5f9dad85f6d00b3;
    // solana program show STTUVCMPuNbk21y1J6nqEGXSQ8HKvFmFBKnCvKHTrWn | grep 'ProgramData Address:' | awk '{print $3}' | xargs -I{} python3 -c "import base58; print(base58.b58decode('{}').hex())"
    bytes32 constant NTT_PROGRAM_DATA_ADDR      = 0xa821ac5164fa9b54fd93b54dba8215550b8fce868f52299169f6619867cac501;
    // python3 -c "import base58; print(base58.b58decode('DCWd3ygRyr9qESyRfPRCMQ6o1wAsPu2niPUc48ixWeY9').hex())" # PDA derived from seed "config" and the NTT program ID
    bytes32 constant NTT_CONFIG_PDA             = 0xb53f200f8db357f9e1e982ef0ec4b3b879f9f6516d5247307ebaf00d187be51a;
    // python3 -c "import base58; print(base58.b58decode('Bjui9tuxKGsiF5FDwosfUsRUXg9RZCKidbThfm6CRtRt').hex())" # PDA derived from seed "token_authority" and the NTT program ID
    bytes32 constant NTT_TOKEN_AUTHORITY_PDA    = 0x9f92dcb365df21a4a4ec23d8ff4cc020cdd09895f8129c2c2fb43289bc53f95f;
    // python3 -c "import base58; print(base58.b58decode('USDSwr9ApdHk5bvJKMjzff41FfuX8bSxdKcR81vTwcA').hex())"
    bytes32 constant USDS_MINT_ADDR             = 0x0707312d1d41da71f0fb280c1662cd65ebeb2e0859c0cbae3fdbdcb26c86e0af;
    // python3 -c "import base58; print(base58.b58decode('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA').hex())"
    bytes32 constant SPL_TOKEN_PROGRAM_ID       = 0x06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9;
    // python3 -c "import base58; print(base58.b58decode('4CVeJ5oZPL77ewm9DdjEEnh6vLSWKvcPhzgvhpKcZRuL').hex())" # ATA derived from USDS (mint) and token_authority PDA (owner)
    bytes32 constant CUSTODY_ATA                = 0x2f84d6207230f62740d15c068bc819bb107ebcb144b0c9fdd53de27b1814d36b;

    // Solana account metas
    bytes2 constant READONLY = bytes2(0x0000);
    bytes2 constant WRITABLE = bytes2(0x0001);
    bytes2 constant SIGNER   = bytes2(0x0100);

    // TODO: new names for everything
    function _publishWHMessage(bytes32 govProgramId, bytes32 programId, bytes memory accounts, bytes memory data)
        internal
        pure
        returns (bytes memory payload)
    {
        payload =
            bytes.concat( // see payload layout in lib/sky-ntt-migration/solana/programs/wormhole-governance/src/instructions/governance.rs
                abi.encodePacked(
                    bytes8(0), "GeneralPurposeGovernance", // module, 32 bytes left-padded string
                    uint8(2),                              // action, 1 byte
                    uint16(1),                             // chainId, 2 bytes
                    govProgramId,                          // governanceProgramId, 32 bytes
                    programId,                             // programId, 32 bytes
                    uint16(accounts.length / 34)           // accountsLength, 2 bytes
                ),
                accounts,                                  // accounts (32+2)*accountsLength bytes
                abi.encodePacked(uint16(data.length)),     // dataLength, 2 bytes
                data                                       // data
            );
    }

    function _publishLZMessage(address originCaller, uint32 chainId, bytes32 programId, bytes memory accounts, bytes memory data)
        internal
        pure
        returns (bytes memory message)
    {
        message = bytes.concat(
            abi.encodePacked(
                uint8(2),                                 // action, 1 byte
                chainId,                                  // chainId, 4 bytes (30168 for Solana mainnet; 40168 for Solana testnet)
                bytes32(uint256(uint160(originCaller))),  // originCaller, 32 bytes
                programId,                                // programId, 32 bytes
                uint16(accounts.length / 34)              // accountsLength, 2 bytes
            ),
            accounts,                                     // accounts (32+2)*accountsLength bytes
            data                                          // data
        );
    }

    //////////////////////
    /////// Step 0 ///////
    //////////////////////

    function _upgradeSolNtt(bytes32 govProgramId, bytes32 nttProgramDataAddr, bytes32 nttProgramId, bytes32 buffer)
        internal
        pure
        returns (bytes memory payload)
    {
        return _publishWHMessage({
            govProgramId: govProgramId,
            programId:    BFT_LOADER_UPGRADABLE_ADDR,
            accounts:     abi.encodePacked( // See https://github.com/solana-labs/solana/blob/7700cb3128c1f19820de67b81aa45d18f73d2ac0/sdk/program/src/loader_upgradeable_instruction.rs#L84
                nttProgramDataAddr, WRITABLE,
                nttProgramId,       WRITABLE,
                buffer,             WRITABLE,
                bytes32("owner"),   WRITABLE, // spill account (should we instead use bytes32("payer") ?)
                SYSVAR_RENT_ADDR,   READONLY,
                SYSVAR_CLOCK_ADDR,  READONLY,
                bytes32("owner"),   SIGNER    // program's authority
            ),
            data:         hex"03" // "Upgrade" instruction as per loader_upgradeable_instruction.rs
        });
    }

    //////////////////////
    /////// Step 1 ///////
    //////////////////////

    function _pauseSolNttBridge(
        bytes32 govProgramId,
        bytes32 nttProgramId,
        bytes32 nttConfigPda
    )
        internal
        pure
        returns (bytes memory payload)
    {
        return _publishWHMessage({
            govProgramId: govProgramId,
            programId:    nttProgramId,
            accounts:     abi.encodePacked( // See lib/sky-ntt-migration/solana/programs/native-token-transfers/src/instructions/admin.rs#L266
                    bytes32("owner"), SIGNER,   // owner
                    nttConfigPda,     WRITABLE  // config
                ),
            data:         abi.encodePacked(
                    bytes8(sha256("global:set_paused")),  // Anchor discriminator for "SetPaused" instruction
                    bytes1(0x01)                          // paused = true
            )
        });
    }

    //////////////////////
    /////// Step 2 ///////
    //////////////////////

    function _transferMintAuthority(
        bytes32 govProgramId,
        bytes32 nttProgramId,
        bytes32 nttConfigPda,
        bytes32 nttTokenAuthorityPda,
        bytes32 usdsMintAddr,
        bytes32 custodyAta,
        bytes32 newMintAuthority
    )
        internal
        pure
        returns (bytes memory payload)
    {
        return _publishWHMessage({
            govProgramId: govProgramId,
            programId:    nttProgramId,
            accounts:     abi.encodePacked( // See lib/sky-ntt-migration/solana/programs/native-token-transfers/src/instructions/transfer_mint_authority.rs#L10
                    bytes32("owner"),     WRITABLE | SIGNER, // payer
                    nttConfigPda,         READONLY,          // config
                    nttTokenAuthorityPda, READONLY,          // token_authority
                    usdsMintAddr,         WRITABLE,          // mint
                    SPL_TOKEN_PROGRAM_ID, READONLY,          // token_program
                    custodyAta,           WRITABLE           // custody
                ),
            data:         abi.encodePacked(
                    bytes8(sha256("global:transfer_mint_authority")),
                    newMintAuthority
                )
        });
    }

    function _activateSolLZBridge(
        address owner,
        uint32 chainId,
        bytes32 oftStore,
        bytes32 oftProgramId
    )
        internal
        pure
        returns (bytes memory message)
    {
        return _publishLZMessage({
            originCaller: owner,
            chainId:   chainId,
            programId: oftProgramId,
            accounts:  abi.encodePacked(
                    bytes32("cpi_authority"), SIGNER,
                    oftStore,                 WRITABLE
                ),
            data:      abi.encodePacked(
                    bytes8(sha256("global:set_oft_config")), // Anchor discriminator for "SetOftConfig" instruction
                    bytes1(0x03),                            // enum variant tag for Paused
                    bytes1(0x00)                             // paused = false
                )
        });
    }
}
