// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Arbitrum} from "./networkConfig/Arbitrum.t.sol";
import {UpgradeUtil} from "./UpgradeUtil.t.sol";
import {FarmRegistry, IFarmRegistry} from "../../contracts/FarmRegistry.sol";

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
        IFarmRegistry farmRegistryImpl = new FarmRegistry();
        FARM_REGISTRY = upgradeUtil.deployErc1967Proxy(address(farmRegistryImpl));
        IFarmRegistry(FARM_REGISTRY).initialize(_feeReceiver, _feeToken, _feeAmount, _extensionFeePerDay);
        vm.stopPrank();
    }
}
