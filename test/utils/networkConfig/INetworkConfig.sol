// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface INetworkConfig {
    function setForkNetwork() external;

    function FEE_TOKEN() external pure returns (address);

    function NETWORK_ID() external pure returns (string memory);
}
