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

pragma solidity ^0.8.21;

import "dss-test/DssTest.sol";

import { MigrationDeploy } from "deploy/MigrationDeploy.sol";
import { MigrationInit } from "deploy/MigrationInit.sol";
import { NttManager } from "lib/sky-ntt-migration/evm/src/NttManager/NttManager.sol";
import { OFTAdapter } from "lib/sky-oapp-oft/contracts/OFTAdapter.sol";
import { DoubleSidedRateLimiter } from "lib/sky-oapp-oft/contracts/oft-dsrl/DoubleSidedRateLimiter.sol";
import { GovernanceControllerOApp } from "lib/sky-oapp-gov/contracts/GovernanceControllerOApp.sol";

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { SetConfigParam, IMessageLibManager } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { ExecutorConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";


interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface TokenLike {
    function approve(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

contract MigrationTest is DssTest {
    using OptionsBuilder for bytes;

    ChainlogLike public chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    NttManager   public nttManager = NttManager(0x7d4958454a3f520bDA8be764d06591B054B0bf33);

    address public pauseProxy;
    address public usds;
    address public nttManagerImpV2;
    
    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        pauseProxy = chainlog.getAddress("MCD_PAUSE_PROXY");
        usds       = chainlog.getAddress("USDS");

        nttManagerImpV2 = MigrationDeploy.deployMigration();
    }

    function testMigrationStep0() public {
        vm.startPrank(pauseProxy);
        vm.expectRevert(bytes(""));
        nttManager.migrateLockedTokens(address(this));

        MigrationInit.initMigrationStep0(nttManagerImpV2, 0);

        nttManager.migrateLockedTokens(address(this));
        vm.stopPrank();
    }

    function testMigrationStep1() public {
        vm.expectRevert(bytes(""));
        nttManager.isSendPaused();

        vm.startPrank(pauseProxy);
        MigrationInit.initMigrationStep0(nttManagerImpV2, 0);
        MigrationInit.initMigrationStep1();
        vm.stopPrank();

        assertEq(nttManager.isSendPaused(), true);
    }

    function _initOapp(address oapp) internal {
        IOAppCore(oapp).setPeer(MigrationInit.SOL_EID, bytes32(uint256(0xbeef)));

        ExecutorConfig memory execCfg = ExecutorConfig({
            maxMessageSize: 1_000_000,
            executor:       0x173272739Bd7Aa6e4e214714048a9fE699453059 // LZ Executor
        });
        UlnConfig memory ulnCfg = UlnConfig({
            confirmations:        15,
            requiredDVNCount:     1,
            optionalDVNCount:     type(uint8).max,
            optionalDVNThreshold: 0,
            requiredDVNs:         new address[](1),
            optionalDVNs:         new address[](0)
        });
        ulnCfg.requiredDVNs[0] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs DVN

        SetConfigParam[] memory cfgParams = new SetConfigParam[](2);
        cfgParams[0] = SetConfigParam(MigrationInit.SOL_EID, 1, abi.encode(execCfg));
        cfgParams[1] = SetConfigParam(MigrationInit.SOL_EID, 2, abi.encode(ulnCfg));

        IMessageLibManager(MigrationInit.ETH_LZ_ENDPOINT).setConfig(
            oapp,
            0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1, // SendUln302 message lib
            cfgParams
        );

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam(MigrationInit.SOL_EID, 1, OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0));
        IOAppOptionsType3(oapp).setEnforcedOptions(opts);
    }

    function testMigrationStep2() public {
        uint256 escrowed = TokenLike(usds).balanceOf(address(nttManager));

        OFTAdapter oftAdapter = new OFTAdapter(usds, MigrationInit.ETH_LZ_ENDPOINT, pauseProxy);
        GovernanceControllerOApp govOapp = new GovernanceControllerOApp(MigrationInit.ETH_LZ_ENDPOINT, pauseProxy);

        vm.startPrank(pauseProxy);
        _initOapp(address(govOapp));
        _initOapp(address(oftAdapter));
        DoubleSidedRateLimiter.RateLimitConfig[] memory rlConfigs = new DoubleSidedRateLimiter.RateLimitConfig[](1);
        rlConfigs[0] = DoubleSidedRateLimiter.RateLimitConfig(MigrationInit.SOL_EID, 1 days, 1_000_000 ether);
        oftAdapter.setRateLimits(rlConfigs, DoubleSidedRateLimiter.RateLimitDirection.Outbound);
        oftAdapter.setRateLimits(rlConfigs, DoubleSidedRateLimiter.RateLimitDirection.Inbound);
        oftAdapter.setPauser(pauseProxy, true);
        oftAdapter.pause();
        assertTrue(oftAdapter.paused());
        SendParam memory sendParams = SendParam({
            dstEid: MigrationInit.SOL_EID,
            to: bytes32(uint256(0xdede)),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
        vm.expectRevert(Pausable.EnforcedPause.selector);
        oftAdapter.quoteSend(sendParams, false);

        MigrationInit.initMigrationStep0(nttManagerImpV2, 0);
        MigrationInit.initMigrationStep1();
        MigrationInit.initMigrationStep2({
            oftAdapter: address(oftAdapter),
            newMintAuthority: 0,
            gasLimit: 1_000_000,
            govOapp: address(govOapp),
            oftStore: 0,
            oftProgramId: bytes32(uint256(0xbeef)),
            outboundWindow: rlConfigs[0].window,
            outboundLimit: rlConfigs[0].limit,
            inboundWindow: rlConfigs[0].window,
            inboundLimit: rlConfigs[0].limit,
            rlAccountingType: 0
        });  
        vm.stopPrank();

        assertFalse(oftAdapter.paused());
        assertEq(TokenLike(usds).balanceOf(address(nttManager)), 0);
        assertEq(TokenLike(usds).balanceOf(address(oftAdapter)), escrowed);

        MessagingFee memory msgFee = oftAdapter.quoteSend(sendParams, false);
        deal(usds, address(this), 1 ether, true);
        TokenLike(usds).approve(address(oftAdapter), 1 ether);
        oftAdapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
    }
}
