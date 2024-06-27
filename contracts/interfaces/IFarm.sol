// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RewardData, RewardFund} from "./DataTypes.sol";

interface IFarm {
    function updateRewardData(address _rwdToken, address _newTknManager) external;

    function setRewardRate(address _rwdToken, uint128[] memory _newRewardRates) external;

    function recoverRewardFunds(address _rwdToken, uint256 _amount) external;

    function rewardData(address _token) external view returns (RewardData memory);

    function cooldownPeriod() external view returns (uint256);

    function isFarmActive() external view returns (bool);

    function getRewardTokens() external view returns (address[] memory);

    function getRewardFundInfo(uint8 _fundId) external view returns (RewardFund memory);

    function getTokenAmounts() external view returns (address[] memory, uint256[] memory);

    function getRewardBalance(address _rwdToken) external view returns (uint256);
}
