// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface INetworkConfig {
    function FEE_TOKEN() external pure returns (address);

    function NETWORK_ID() external pure returns (string memory);

    function setForkNetwork() external;
}
