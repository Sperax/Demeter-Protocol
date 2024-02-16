// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Arbitrum} from "./networkConfig/Arbitrum.t.sol";
import {UpgradeUtil} from "./UpgradeUtil.t.sol";
import {FarmRegistry} from "../../contracts/FarmRegistry.sol";

// Select the test network configuration
abstract contract TestNetworkConfig is Arbitrum {
    function setUp() public virtual override {
        super.setUp();
        address _feeReceiver = actors[6];
        address _feeToken = USDS;
        uint256 _feeAmount = 1e20;
        uint256 _extensionFeePerDay = 1e18;
        vm.startPrank(PROXY_OWNER);
        UpgradeUtil upgradeUtil = new UpgradeUtil();
        FarmRegistry farmRegistryImpl = new FarmRegistry();
        DEMETER_REGISTRY = upgradeUtil.deployErc1967Proxy(address(farmRegistryImpl));
        FarmRegistry(DEMETER_REGISTRY).initialize(_feeReceiver, _feeToken, _feeAmount, _extensionFeePerDay);
        vm.stopPrank();
    }
}
