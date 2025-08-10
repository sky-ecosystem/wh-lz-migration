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
    function messageFee() external view returns (uint256);
    function publishMessage(uint32 nonce, bytes memory payload, uint8 consistencyLevel) external payable returns (uint64);
}

interface OAppLike {
    function owner() external view returns (address);
    function endpoint() external view returns (address);
    function peers(uint32) external view returns (bytes32);
    function enforcedOptions(uint32, uint16) external view returns (bytes memory);
}

interface OFTAdapterLike is OAppLike {
    struct RateLimitConfig {
        uint32 eid;
        uint48 window;
        uint256 limit;
    }
    enum RateLimitDirection {
        Inbound,
        Outbound
    }
    function token() external view returns (address);
    function defaultFeeBps() external view returns (uint16);
    function feeBps(uint32) external view returns (uint16, bool);
    function paused() external view returns (bool);
    function unpause() external;
    function outboundRateLimits(uint32) external view returns (uint128, uint48, uint256, uint256);
    function inboundRateLimits(uint32) external view returns (uint128, uint48, uint256, uint256);
    function rateLimitAccountingType() external view returns (uint8);
    function setRateLimits(RateLimitConfig[] calldata _rateLimitConfigs, RateLimitDirection _direction) external;
}

interface EndpointLike {
    function delegates(address) external view returns (address);
}

interface GovOappLike is OAppLike {
    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }
    function quoteRawBytesAction(
        bytes calldata message,
        bytes calldata extraOptions,
        bool payInLzToken
    ) external view returns (MessagingFee memory fee);
    function sendRawBytesAction(
        bytes calldata message,
        bytes calldata extraOptions,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable;
}

library MigrationInit {
    /*
    ChainlogLike constant LOG = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address constant WORMHOLE_CORE_BRIDGE = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;
    address constant NTT_MANAGER          = 0x7d4958454a3f520bDA8be764d06591B054B0bf33;
    address constant ETH_LZ_ENDPOINT      = 0x1a44076050125825900e736c501f859c50fE728c;
    */
    uint32  constant SOL_EID              = 30168; // TODO: should be configureable?

    function _publishWHMessage(address wormhole, bytes memory payload) internal {
        uint256 fee = WormholeLike(wormhole).messageFee();
        WormholeLike(wormhole).publishMessage{value: fee}({
            nonce: 0,
            payload: payload,
            consistencyLevel: 202 // "Finalized" (~19 minutes - see https://wormhole.com/docs/build/reference/consistency-levels/) // TB asked - did you see anyone use that value? as I understand it should be 201, which is just a tag, not actual seconds
        });
    }

    function _publishLZMessage(bytes memory message, address refundAddress, uint128 gasLimit, address govOapp) internal {
        // The following yields the same result as doing:
        // bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0);
        // but without the need to import OptionsBuilder
        bytes memory extraOptions = abi.encodePacked( // see addExecutorLzReceiveOption() in @layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol
            abi.encodePacked(uint16(3)), // Option TYPE_3
            uint8(1),                    // ExecutorOptions.WORKER_ID
            uint16(17),                  // (abi.encodePacked(gasLimit)).length.toUint16() + 1
            uint8(1),                    // ExecutorOptions.OPTION_TYPE_LZRECEIVE
            abi.encodePacked(gasLimit)   // ExecutorOptions.encodeLzReceiveOption(gasLimit, 0)
        );

        // TODO: Decide if we prefer to get this fee off-chain
        GovOappLike.MessagingFee memory fee = GovOappLike(govOapp).quoteRawBytesAction({
            message: message,
            extraOptions: extraOptions,
            payInLzToken: false
        });

        GovOappLike(govOapp).sendRawBytesAction{value: fee.nativeFee}({
            message: message,
            extraOptions: extraOptions,
            fee: fee,
            refundAddress: refundAddress
        });
    }

    //////////////////////
    /////// Step 0 ///////
    //////////////////////

    function initMigrationStep0(
        address nttManagerImpV2,
        address nttManager, // NTT_MANAGER on mainnet
        address wormhole,   // WORMHOLE_CORE_BRIDGE on mainnet
        bytes   memory payload
    ) internal {
        //// _upgradeEthNtt ////
        NttManagerLike mgr   = NttManagerLike(nttManager);
        NttManagerLike impV2 = NttManagerLike(nttManagerImpV2);

        // Sanity checks
        require(impV2.token()             == mgr.token(),             "MigrationInit/token-mismatch");
        require(impV2.mode()              == mgr.mode(),              "MigrationInit/mode-mismatch");
        require(impV2.chainId()           == mgr.chainId(),           "MigrationInit/chain-id-mismatch");
        require(impV2.rateLimitDuration() == mgr.rateLimitDuration(), "MigrationInit/rl-dur-mismatch");

        mgr.upgrade(nttManagerImpV2);

        //// _upgradeSolNtt ////
        _publishWHMessage({ wormhole: wormhole, payload: payload });
    }

    //////////////////////
    /////// Step 1 ///////
    //////////////////////

    function initMigrationStep1(
        address nttManager,  // NTT_MANAGER on mainnet
        address wormhole,    // WORMHOLE_CORE_BRIDGE on mainnet
        bytes memory payload
    ) internal {
        //// _pauseEthNttBridge(nttManager); ////
        NttManagerLike(nttManager).pauseSend();

        //// _pauseSolNttBridge ////
        _publishWHMessage({ wormhole: wormhole, payload: payload });
    }

    //////////////////////
    /////// Step 2 ///////
    //////////////////////

    function _sanityCheckOapp(address oapp, uint32 solEid, address owner, address endpoint, bytes32 peer) internal view {
        OAppLike oapp_ = OAppLike(oapp);
        bytes memory opts1 = oapp_.enforcedOptions(solEid, 1);
        bytes memory opts2 = oapp_.enforcedOptions(solEid, 2);

        require(oapp_.owner() == owner,                                "MigrationInit/owner-mismatch"); 
        require(oapp_.endpoint() == endpoint,                          "MigrationInit/endpoint-mismatch");
        require(oapp_.peers(solEid) == peer,                           "MigrationInit/peer-mismatch");
        require(EndpointLike(endpoint).delegates(oapp) == owner,       "MigrationInit/delegate-mismatch");
        require(opts1.length == 22 && bytes6(opts1) == 0x000301001101, "MigrationInit/bad-enforced-opts-msg-type1"); // expecting [{ msgType: 1, optionType: ExecutorOptionType.LZ_RECEIVE, gas, value: 0 }], see encoding by addExecutorLzReceiveOption() in @layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol 
        uint128 gas = uint128(uint256(bytes32(opts1) >> 80));
        require(gas > 0 && gas <= 36_000_000,                          "MigrationInit/bad-enforced-opts-msg-type1-gas"); 
        require(opts2.length == 0,                                     "MigrationInit/bad-enforced-opts-msg-type2");
    }

    struct MigrationStep2Params {
        address oftAdapter;
        bytes32 oftProgramId;
        address govOapp;
        bytes32 newGovProgramId;
        address refundAddress;
        uint128 gasLimit;
        uint48  outboundWindow;
        uint256 outboundLimit;
        uint48  inboundWindow;
        uint256 inboundLimit;
        uint8   rlAccountingType;
        address nttManager; // NTT_MANAGER on mainnet
        address wormhole;   // WORMHOLE_CORE_BRIDGE on mainnet
        address owner;      // LOG.getAddress("MCD_PAUSE_PROXY")
        address endpoint;   // ETH_LZ_ENDPOINT
        uint32  solEid;     // SOL_EID
        bytes   whPayload;
        bytes   lzMessage;
    }

    function initMigrationStep2(
        MigrationStep2Params memory p
    ) internal {
        // Sanity checks
        _sanityCheckOapp(p.oftAdapter, p.solEid, p.owner, p.endpoint, p.oftProgramId);
        _sanityCheckOapp(p.govOapp,    p.solEid, p.owner, p.endpoint, p.newGovProgramId);
        {
        OFTAdapterLike oft = OFTAdapterLike(p.oftAdapter);
        (uint16 feeBps, bool enabled)         = oft.feeBps(p.solEid);
        (,,,uint256 outLimit) = oft.outboundRateLimits(p.solEid);
        (,,,uint256  inLimit) = oft.inboundRateLimits(p.solEid);
        require(oft.token() == NttManagerLike(p.nttManager).token(),  "MigrationInit/token-mismatch");
        require(oft.defaultFeeBps() == 0,                             "MigrationInit/incorrect-default-fee");
        require(feeBps == 0 && !enabled,                              "MigrationInit/incorrect-solana-fee");
        require(!oft.paused(),                                        "MigrationInit/paused");
        require(outLimit == 0,                                        "MigrationInit/outbound-rl-nonzero");
        require(inLimit  == 0,                                        "MigrationInit/inbound-rl-nonzero");
        require(oft.rateLimitAccountingType() == p.rlAccountingType , "MigrationInit/rl-accounting-mismatch");
        }

        //// _migrateLockedTokens(p.nttManager, p.oftAdapter); ////
        NttManagerLike(p.nttManager).migrateLockedTokens(p.oftAdapter);

        //// _activateEthLZBridge(p.oftAdapter, p.outboundWindow, p.outboundLimit, p.inboundWindow, p.inboundLimit); ////
        OFTAdapterLike.RateLimitConfig[] memory rlConfigs = new OFTAdapterLike.RateLimitConfig[](1);
        rlConfigs[0] = OFTAdapterLike.RateLimitConfig(SOL_EID, p.outboundWindow, p.outboundLimit); // TB - shouldn't the eid stay configurable for tests?
        OFTAdapterLike(p.oftAdapter).setRateLimits(rlConfigs, OFTAdapterLike.RateLimitDirection.Outbound);
        rlConfigs[0] = OFTAdapterLike.RateLimitConfig(SOL_EID,  p.inboundWindow,  p.inboundLimit);
        OFTAdapterLike(p.oftAdapter).setRateLimits(rlConfigs, OFTAdapterLike.RateLimitDirection.Inbound);

        //// _transferMintAuthority ////
        _publishWHMessage({ wormhole: p.wormhole, payload: p.whPayload });

        //// _activateSolLZBridge ///
        _publishLZMessage(p.lzMessage, p.refundAddress, p.gasLimit, p.govOapp);
    }
}
