// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Arbitrum} from "./networkConfig/Arbitrum.t.sol";

// Select the test network configuration
abstract contract TestNetworkConfig is Arbitrum {
    function setUp() public virtual override {
        super.setUp();
    }
}
