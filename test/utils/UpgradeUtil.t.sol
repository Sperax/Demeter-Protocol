//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.26;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeUtil {
    ProxyAdmin public proxyAdmin;

    constructor() {
        proxyAdmin = new ProxyAdmin(msg.sender);
    }

    function deployErc1967Proxy(address impl) public returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(impl, address(proxyAdmin), "");
        return address(proxy);
    }
}
