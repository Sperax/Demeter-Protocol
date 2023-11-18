// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Arbitrum} from "./networkConfig/Arbitrum.t.sol";
import {UpgradeUtil} from "./UpgradeUtil.t.sol";
import {FarmFactory} from "../../contracts/FarmFactory.sol";

// Select the test network configuration
abstract contract TestNetworkConfig is Arbitrum {
    function setUp() public virtual override {
        super.setUp();
        address _feeReceiver = actors[6];
        address _feeToken = USDS;
        uint256 _feeAmount = 1e22;
        vm.startPrank(PROXY_OWNER);
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        FarmFactory farmFactoryImpl = new FarmFactory();
        DEMETER_FACTORY = upgradeUtil.deployErc1967Proxy(address(farmFactoryImpl));
        FarmFactory(DEMETER_FACTORY).initialize(_feeReceiver, _feeToken, _feeAmount);
        vm.stopPrank();
    }
}
