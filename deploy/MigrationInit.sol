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

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

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
        bytes calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);
    function sendRawBytesAction(
        bytes calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable;
}

library MigrationInit {
    ChainlogLike constant LOG = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address constant WORMHOLE_CORE_BRIDGE = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;
    address constant NTT_MANAGER          = 0x7d4958454a3f520bDA8be764d06591B054B0bf33;
    address constant ETH_LZ_ENDPOINT      = 0x1a44076050125825900e736c501f859c50fE728c;
    uint32  constant SOL_EID              = 30168;

    function _publishWHMessage(address wormhole, uint256 maxFee, bytes memory payload) internal {
        uint256 fee = WormholeLike(wormhole).messageFee();
        require(fee <= maxFee, "MigrationInit/exceeds-max-fee"); 
        WormholeLike(wormhole).publishMessage{value: fee}({
            nonce: 0, 
            payload: payload,
            consistencyLevel: 202 // "Finalized" (~19 minutes - see https://wormhole.com/docs/build/reference/consistency-levels/)
        });
    }

    function _publishLZMessage(uint256 maxFee, address refundAddress, uint128 gas, uint128 value, uint32 solEid, address govOapp, bytes memory payload) internal {
        // The following yields the same result as doing:
        // bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gas, value);
        // but without the need to import OptionsBuilder
        bytes memory extraOptions = abi.encodePacked( // see addExecutorLzReceiveOption() in @layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol
            abi.encodePacked(uint16(3)),                                        // Options Type "3" (TYPE_3), the only options type currently supported by LZ
            uint8(1),                                                           // ExecutorOptions.WORKER_ID
            value == 0 ? uint16(17) : uint16(33),                               // ExecutorOptions.encodeLzReceiveOption(gas, value).length.toUint16() + 1
            uint8(1),                                                           // ExecutorOptions.OPTION_TYPE_LZRECEIVE
            value == 0 ? abi.encodePacked(gas) : abi.encodePacked(gas, value)   // ExecutorOptions.encodeLzReceiveOption(gas, value)
        );

        GovOappLike.MessagingFee memory fee = GovOappLike(govOapp).quoteRawBytesAction({
            _message: payload,
            _dstEid: solEid,
            _extraOptions: extraOptions,
            _payInLzToken: false
        });
        require(fee.nativeFee <= maxFee, "MigrationInit/exceeds-max-fee"); 

        GovOappLike(govOapp).sendRawBytesAction{value: fee.nativeFee}({
            _message: payload,
            _dstEid: solEid,
            _extraOptions: extraOptions,
            _fee: fee,
            _refundAddress: refundAddress
        });
    }

    //////////////////////
    /////// Step 0 ///////
    //////////////////////

    function initMigrationStep0(
        address nttManagerImpV2,
        uint256 maxWHFee,
        bytes memory payload,
        address nttManager,
        address wormhole
    ) internal {
        NttManagerLike mgr   = NttManagerLike(nttManager);
        NttManagerLike impV2 = NttManagerLike(nttManagerImpV2);

        // Sanity checks
        require(impV2.token()             == mgr.token(),             "MigrationInit/token-mismatch");
        require(impV2.mode()              == mgr.mode(),              "MigrationInit/mode-mismatch");
        require(impV2.chainId()           == mgr.chainId(),           "MigrationInit/chain-id-mismatch");
        require(impV2.rateLimitDuration() == mgr.rateLimitDuration(), "MigrationInit/rl-dur-mismatch");
        
        // Upgrade Ethereum NTT Manager
        mgr.upgrade(nttManagerImpV2);

        // Upgrade Solana NTT Manager
        _publishWHMessage({
            wormhole: wormhole,
            maxFee:   maxWHFee,
            payload:  payload
        });
    }

    function initMigrationStep0(
        address nttManagerImpV2,
        uint256 maxWHFee,
        bytes memory payload
    ) internal {
        initMigrationStep0({
            nttManagerImpV2: nttManagerImpV2,
            maxWHFee:        maxWHFee,
            payload:         payload,
            nttManager:      NTT_MANAGER,
            wormhole:        WORMHOLE_CORE_BRIDGE
        });
    }

    //////////////////////
    /////// Step 1 ///////
    //////////////////////

    function initMigrationStep1(
        uint256 maxWHFee,
        bytes memory payload,
        address nttManager,
        address wormhole
    ) internal {
        // Pause Ethereum NTT Manager
        NttManagerLike(nttManager).pauseSend();

        // Pause Solana NTT Manager
        _publishWHMessage({
            wormhole: wormhole,
            maxFee:   maxWHFee,
            payload:  payload
        });
    }

    function initMigrationStep1(
        uint256 maxWHFee,
        bytes memory payload
    ) internal {
        initMigrationStep1({
            maxWHFee:     maxWHFee,
            payload:      payload,
            nttManager:   NTT_MANAGER,
            wormhole:     WORMHOLE_CORE_BRIDGE
        });
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
        require(opts1.length == 38 && bytes6(opts1) == 0x000301002101, "MigrationInit/bad-enforced-opts-msg-type1"); // expecting [{ msgType: 1, optionType: ExecutorOptionType.LZ_RECEIVE, gas, value: 2_500_000 }], see encoding by addExecutorLzReceiveOption() in @layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol
        uint128 gas_; uint128 val;
        assembly { // opts1 layout: {header: 6 bytes}{gas: 16 bytes}{value: 16 bytes}
            let ptr := add(opts1, 32)
            gas_ := shr(80, mload(ptr))
            val  := mload(add(ptr, 6))
        }
        require(gas_ <= 1_400_000,                                     "MigrationInit/bad-enforced-opts-msg-type1-gas"); // max 1.4m compute units, per https://solana.com/docs/core/fees#compute-units-and-limits
        require(val  == 2_500_000,                                     "MigrationInit/bad-enforced-opts-msg-type1-value"); // assume 2.5m lamports enforced, per https://docs.layerzero.network/v2/developers/solana/oft/account#setting-enforced-options-inbound-to-solana
        require(opts2.length == 0,                                     "MigrationInit/bad-enforced-opts-msg-type2");
    }

    struct RateLimitsParams {
        uint48  outboundWindow;
        uint256 outboundLimit;
        uint48  inboundWindow;
        uint256 inboundLimit;
        uint8   rlAccountingType;
    }

    struct MigrationStep2Params {
        address oftAdapter;
        bytes32 oftProgramId;
        address govOapp; 
        bytes32 newGovProgramId;
        uint128 gas;
        uint128 value;
        RateLimitsParams rl;
        uint256 maxWHFee;
        uint256 maxLZFee;
        bytes whPayload;
        bytes lzPayload;
        address nttManager;
        address wormhole;
        address owner;
        address endpoint;
        uint32  solEid;
    }

    function initMigrationStep2(
        MigrationStep2Params memory p
    ) internal {
        // Sanity checks
        _sanityCheckOapp(p.oftAdapter, p.solEid, p.owner, p.endpoint, p.oftProgramId);
        _sanityCheckOapp(p.govOapp,    p.solEid, p.owner, p.endpoint, p.newGovProgramId);
        OFTAdapterLike oft = OFTAdapterLike(p.oftAdapter);
        (uint16 feeBps, bool enabled)         = oft.feeBps(p.solEid);
        (,,,uint256 outLimit) = oft.outboundRateLimits(p.solEid);
        (,,,uint256  inLimit) = oft.inboundRateLimits(p.solEid);
        require(oft.token() == NttManagerLike(p.nttManager).token(),     "MigrationInit/token-mismatch");
        require(oft.defaultFeeBps() == 0,                                "MigrationInit/incorrect-default-fee");
        require(feeBps == 0 && !enabled,                                 "MigrationInit/incorrect-solana-fee");
        require(!oft.paused(),                                           "MigrationInit/paused");
        require(outLimit == 0,                                           "MigrationInit/outbound-rl-nonzero");
        require(inLimit  == 0,                                           "MigrationInit/inbound-rl-nonzero");
        require(oft.rateLimitAccountingType() == p.rl.rlAccountingType , "MigrationInit/rl-accounting-mismatch");
        
        // Migrated Locked Tokens
        NttManagerLike(p.nttManager).migrateLockedTokens(p.oftAdapter);

        // Activate Ethereum LZ Bridge
        OFTAdapterLike.RateLimitConfig[] memory rlConfigs = new OFTAdapterLike.RateLimitConfig[](1);
        rlConfigs[0] = OFTAdapterLike.RateLimitConfig(p.solEid, p.rl.outboundWindow, p.rl.outboundLimit);
        OFTAdapterLike(p.oftAdapter).setRateLimits(rlConfigs, OFTAdapterLike.RateLimitDirection.Outbound);
        rlConfigs[0] = OFTAdapterLike.RateLimitConfig(p.solEid,  p.rl.inboundWindow,  p.rl.inboundLimit);
        OFTAdapterLike(p.oftAdapter).setRateLimits(rlConfigs, OFTAdapterLike.RateLimitDirection.Inbound);
        
        // Transfer Mint Authority
        _publishWHMessage({
            wormhole: p.wormhole,
            maxFee:   p.maxWHFee,
            payload:  p.whPayload
        });
        
        // Activate Solana LZ Bridge
        _publishLZMessage({
            maxFee:        p.maxLZFee,
            refundAddress: p.owner,
            gas:           p.gas,
            value:         p.value,
            solEid:        p.solEid,
            govOapp:       p.govOapp,
            payload:       p.lzPayload
        });
    }

    function initMigrationStep2(
        address oftAdapter,
        bytes32 oftProgramId,
        address govOapp,
        bytes32 newGovProgramId,
        uint128 gas,
        uint128 value,
        RateLimitsParams memory rl,
        uint256 maxWHFee,
        uint256 maxLZFee,
        bytes memory whPayload,
        bytes memory lzPayload
    ) internal {
        MigrationStep2Params memory p = MigrationStep2Params({
            oftAdapter:      oftAdapter,
            oftProgramId:    oftProgramId,
            govOapp:         govOapp,
            newGovProgramId: newGovProgramId,
            gas:             gas,
            value:           value,
            rl:              rl,
            maxWHFee:        maxWHFee,
            maxLZFee:        maxLZFee,
            whPayload:       whPayload,
            lzPayload:       lzPayload,
            nttManager:      NTT_MANAGER,
            wormhole:        WORMHOLE_CORE_BRIDGE,
            owner:           LOG.getAddress("MCD_PAUSE_PROXY"),
            endpoint:        ETH_LZ_ENDPOINT,
            solEid:          SOL_EID
        });
        initMigrationStep2(p);
    }
}
