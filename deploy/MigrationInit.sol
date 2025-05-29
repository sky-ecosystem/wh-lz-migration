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

interface NttManagerLike {
    function token() external view returns (address);
    function mode() external view returns (uint8);
    function chainId() external view returns (uint16);
    function rateLimitDuration() external view returns (uint64);
    function upgrade(address) external;
    function pauseSend() external;
    function migrateLockedTokens(address) external;
}

interface WormholeLike {
    function publishMessage(uint32 nonce, bytes memory payload, uint8 consistencyLevel) external payable returns (uint64);
}

library MigrationInit {

    address constant WORMHOLE_CORE_BRIDGE = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;

    // python3 -c "import base58; print(base58.b58decode('BPFLoaderUpgradeab1e11111111111111111111111').hex())"
    bytes32 constant BFT_LOADER_UPGRADABLE_ADDR       = 0x02a8f6914e88a1b0e210153ef763ae2b00c2b93d16c124d2c0537a1004800000;
    // python3 -c "import base58; print(base58.b58decode('SysvarC1ock11111111111111111111111111111111').hex())"
    bytes32 constant SYSVAR_CLOCK_ADDR                = 0x06a7d51718c774c928566398691d5eb68b5eb8a39b4b6d5c73555b2100000000;
    // python3 -c "import base58; print(base58.b58decode('SysvarRent111111111111111111111111111111111').hex())"
    bytes32 constant SYSVAR_RENT_ADDR                 = 0x06a7d517192c5c51218cc94c3d4af17f58daee089ba1fd44e3dbd98a00000000;
    // python3 -c "import base58; print(base58.b58decode('SCCGgsntaUPmP6UjwUBNiQQ83ys5fnCHdFASHPV6Fm9').hex())"
    bytes32 constant GOVERNANCE_PROGRAM_ID            = 0x06742d7ca523a03aaafe48abab02e47eb8aef53415cb603c47a3ccf864d86dc0;
    // python3 -c "import base58; print(base58.b58decode('STTUVCMPuNbk21y1J6nqEGXSQ8HKvFmFBKnCvKHTrWn').hex())"
    bytes32 constant NTT_PROGRAM_ID                   = 0x06856f43abf4aaa4a26b32ae8ea4cb8fadc8e02d267703fbd5f9dad85f6d00b3;
    // solana program show STTUVCMPuNbk21y1J6nqEGXSQ8HKvFmFBKnCvKHTrWn | grep 'ProgramData Address:' | awk '{print $3}' | xargs -I{} python3 -c "import base58; print(base58.b58decode('{}').hex())"
    bytes32 constant NTT_PROGRAM_DATA_ADDR            = 0xa821ac5164fa9b54fd93b54dba8215550b8fce868f52299169f6619867cac501;

    function _upgradeEthNtt(address nttManagerImpV2, address nttManager) internal {
        NttManagerLike mgr   = NttManagerLike(nttManager);
        NttManagerLike impV2 = NttManagerLike(nttManagerImpV2);

        // Sanity checks
        require(impV2.token()             == mgr.token(),             "MigrationInit/token-mismatch");
        require(impV2.mode()              == mgr.mode(),              "MigrationInit/mode-mismatch");
        require(impV2.chainId()           == mgr.chainId(),           "MigrationInit/chain-id-mismatch");
        require(impV2.rateLimitDuration() == mgr.rateLimitDuration(), "MigrationInit/rl-dur-mismatch");
        
        mgr.upgrade(nttManagerImpV2);
    }

    function _upgradeSolNtt(bytes32 buffer) internal {
        bytes memory  accounts = abi.encodePacked(
            NTT_PROGRAM_DATA_ADDR,      bytes2(0x0001), // WRITABLE
            NTT_PROGRAM_ID,             bytes2(0x0001), // WRITABLE
            buffer,                     bytes2(0x0001), // WRITABLE
            bytes32("owner"),           bytes2(0x0001), // WRITABLE -- will be used as spill, should we instead use bytes32("payer") ?
            SYSVAR_RENT_ADDR,           bytes2(0x0000), // READONLY
            SYSVAR_CLOCK_ADDR,          bytes2(0x0000), // READONLY
            bytes32("owner"),           bytes2(0x0100)  // SIGNER
        );

        WormholeLike(WORMHOLE_CORE_BRIDGE).publishMessage({
            nonce: 0, 
            payload: bytes.concat(
                abi.encodePacked(
                    bytes8(0), "GeneralPurposeGovernance", // module, 32 bytes left-padded string
                    uint8(2),                              // action, 1 byte
                    uint16(1),                             // chainId, 2 bytes
                    GOVERNANCE_PROGRAM_ID,                 // governanceProgramId, 32 bytes
                    BFT_LOADER_UPGRADABLE_ADDR,            // programId, 32 bytes
                    uint16(7)                              // accountsLength, 2 bytes
                ),
                accounts,                                  // accounts (32+2)*7 bytes
                abi.encodePacked(                          
                    uint16(1),                             // dataLength, 2 bytes
                    bytes1(0x03)                           // data; "Upgrade" instruction
                )
            ), 
            consistencyLevel: 202 // "Finalized" (~19 minutes)
        });
    }

    function initMigrationStep0(
        address nttManagerImpV2,
        address nttManager,
        bytes32 buffer
    ) internal {
        _upgradeEthNtt(nttManagerImpV2, nttManager);
        _upgradeSolNtt(buffer);
    }

    function initMigrationStep1(
        address nttManager
    ) internal {
        NttManagerLike(nttManager).pauseSend();
    }

    function initMigrationStep2(
        address nttManager,
        address oftAdapter
    ) internal {
        NttManagerLike(nttManager).migrateLockedTokens(oftAdapter);
    }
}
