// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {RewardData} from "./DataTypes.sol";

interface IFarm {
    function updateRewardData(address _rwdToken, address _newTknManager) external;

    function setRewardRate(address _rwdToken, uint256[] memory _newRwdRates) external;

    function rewardData(address _token) external view returns (RewardData memory);

    function getTokenAmounts() external view returns (address[] memory, uint256[] memory);

    function cooldownPeriod() external view returns (uint256);

    function isFarmActive() external view returns (bool);
}
