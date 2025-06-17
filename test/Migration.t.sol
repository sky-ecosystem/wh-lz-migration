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

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
}

contract OFTAdapterMock{
    address public owner = msg.sender;
    address public token;
    address public endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // LZ Ethereum EndpointV2
    constructor(address _token) {
        token = _token;
    }
    function unpause() external {}
}

contract GovOappMock{
    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }
    function sendRawBytesAction(
        bytes calldata message,
        bytes calldata extraOptions,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable {}
    function quoteRawBytesAction(
        bytes calldata message,
        bytes calldata extraOptions,
        bool payInLzToken
    ) external view returns (MessagingFee memory fee) {}
}

contract MigrationTest is DssTest {
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

    function testMigrationStep2() public {
        uint256 escrowed = TokenLike(usds).balanceOf(address(nttManager));

        vm.startPrank(pauseProxy);
        address oftAdapter = address(new OFTAdapterMock(usds));
        MigrationInit.initMigrationStep0(nttManagerImpV2, 0);
        MigrationInit.initMigrationStep1();
        MigrationInit.initMigrationStep2(oftAdapter, 0, 0, address(new GovOappMock()), 0, 0);  
        vm.stopPrank();

        assertEq(TokenLike(usds).balanceOf(address(nttManager)), 0);
        assertEq(TokenLike(usds).balanceOf(oftAdapter), escrowed);
    }
}
