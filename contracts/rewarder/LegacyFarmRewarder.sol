// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// NOTE: This contract is commented because this is a standalone contract, causing issues as Parent contract Rewarder.sol
//       is deployable via factory and inherits Upgradeable contracts.
//       Also we are not foreseeing any use of this contract anytime soon.

// // @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@***@@@@@@@@@@@@@@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@(****@@@@@@@@@@@@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@((******@@@@@@@@@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@(((*******@@@@@@@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@@((((********@@@@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@@@(((((********@@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@@@@(((((((********@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@@@@@@(((((((/*******@@@@@@@ //
// // @@@@@@@@@@&*****@@@@@@@@@@(((((((*******@@@@@ //
// // @@@@@@***************@@@@@@@(((((((/*****@@@@ //
// // @@@@********************@@@@@@@(((((((****@@@ //
// // @@@************************@@@@@@(/((((***@@@ //
// // @@@**************@@@@@@@@@***@@@@@@(((((**@@@ //
// // @@@**************@@@@@@@@*****@@@@@@*((((*@@@ //
// // @@@**************@@@@@@@@@@@@@@@@@@@**(((@@@@ //
// // @@@@***************@@@@@@@@@@@@@@@@@**((@@@@@ //
// // @@@@@****************@@@@@@@@@@@@@****(@@@@@@ //
// // @@@@@@@*****************************/@@@@@@@@ //
// // @@@@@@@@@@************************@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@***************@@@@@@@@@@@@@@@ //
// // @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //

// import {Rewarder, IFarm} from "./Rewarder.sol";
// import {TokenUtils} from "../utils/TokenUtils.sol";
// import {ICamelotFarm, IUniswapV3Farm} from "./interfaces/ILegacyRewarderHelpers.sol";

// /// @title FixedAPRRewarderSPA contract of Demeter Protocol.
// /// @author Sperax Foundation.
// /// @notice This contract tracks farms, their APR, and rewards.
// contract LegacyFarmRewarder is Rewarder {
//     uint8 public constant COMMON_FUND_ID = 0;
//     address public immutable UNISWAP_UTILS;

//     mapping(address => bool) public isUniV3Farm;

//     /// @notice Constructor.
//     /// @param _rewardToken Address of the Reward token.
//     /// @param _oracle Address of the USDs Master Price Oracle.
//     /// @param _admin Admin/ deployer of this contract.
//     /// @param _rewarderFactory Address of the Rewarder factory.
//     /// @param _uniswapUtils Address of Uniswap utils contract.
//     constructor(
//         address _rewardToken,
//         address _oracle,
//         address _admin,
//         address _rewarderFactory,
//         address _uniswapUtils
//     ) {
//         _validateNonZeroAddr(_rewarderFactory);
//         _initialize(_rewardToken, _oracle, _admin, _rewarderFactory);
//         _validateNonZeroAddr(_uniswapUtils);
//         UNISWAP_UTILS = _uniswapUtils;
//     }

//     /// @notice Function to update the rewardToken configuration.
//     /// @param _farm Address of the farm for which the config is to be updated.
//     /// @param _rewardConfig The config which is to be set.
//     /// @param _isUniV3Farm Boolean to check if the farm is UniV3Farm or not.
//     function updateRewardConfig(address _farm, FarmRewardConfigInput memory _rewardConfig, bool _isUniV3Farm)
//         external
//         onlyOwner
//     {
//         isUniV3Farm[_farm] = _isUniV3Farm;
//         super.updateRewardConfig(_farm, _rewardConfig);
//     }

//     /// @notice Function to get token amounts.
//     /// @param _farm Address of the farm.
//     /// @return _tokens Array of token addresses.
//     /// @return _amounts Array of token amounts.
//     function _getTokenAmounts(address _farm) internal view override returns (address[] memory, uint256[] memory) {
//         uint256 totalLiquidity = IFarm(_farm).getRewardFundInfo(COMMON_FUND_ID).totalLiquidity;
//         if (isUniV3Farm[_farm]) {
//             return TokenUtils.getUniV3TokenAmounts({
//                 _uniPool: IUniswapV3Farm(_farm).uniswapPool(),
//                 _uniUtils: UNISWAP_UTILS,
//                 _tickLower: IUniswapV3Farm(_farm).tickLowerAllowed(),
//                 _tickUpper: IUniswapV3Farm(_farm).tickUpperAllowed(),
//                 _liquidity: totalLiquidity
//             });
//         } else {
//             return TokenUtils.getUniV2TokenAmounts(ICamelotFarm(_farm).nftPool(), totalLiquidity);
//         }
//     }

//     /// @notice Function to check if the farm has reward token.
//     function _hasRewardToken(address) internal pure override returns (bool) {
//         return true;
//     }
// }
