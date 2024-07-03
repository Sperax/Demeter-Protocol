// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@***@@@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@(****@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@((******@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@(((*******@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@((((********@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@(((((********@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@(((((((********@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@@@(((((((/*******@@@@@@@ //
// @@@@@@@@@@&*****@@@@@@@@@@(((((((*******@@@@@ //
// @@@@@@***************@@@@@@@(((((((/*****@@@@ //
// @@@@********************@@@@@@@(((((((****@@@ //
// @@@************************@@@@@@(/((((***@@@ //
// @@@**************@@@@@@@@@***@@@@@@(((((**@@@ //
// @@@**************@@@@@@@@*****@@@@@@*((((*@@@ //
// @@@**************@@@@@@@@@@@@@@@@@@@**(((@@@@ //
// @@@@***************@@@@@@@@@@@@@@@@@**((@@@@@ //
// @@@@@****************@@@@@@@@@@@@@****(@@@@@@ //
// @@@@@@@*****************************/@@@@@@@@ //
// @@@@@@@@@@************************@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@***************@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //

import {RewardTokenData} from "../../Farm.sol";
import {Farm, E721Farm} from "../E721Farm.sol";
import {ClaimableFee} from "./../../features/ClaimableFee.sol";
import {ExpirableFarm} from "../../features/ExpirableFarm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {INFPM, ICamelotV3Factory, ICamelotV3TickSpacing} from "./interfaces/ICamelotV3.sol";
import {ICamelotV3NFPMUtils, Position} from "./interfaces/ICamelotV3NonfungiblePositionManagerUtils.sol";
import {OperableDeposit} from "../../features/OperableDeposit.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";

// Defines the Camelot pool init data for constructor.
// tokenA - Address of tokenA.
// tokenB - Address of tokenB.
// tickLowerAllowed - Lower bound of the tick range for farm.
// tickUpperAllowed - Upper bound of the tick range for farm.
struct CamelotPoolData {
    address tokenA;
    address tokenB;
    int24 tickLowerAllowed;
    int24 tickUpperAllowed;
}

// Defines a struct for inputs used for initializing this farm.
// farmId - String ID of the farm.
// farmStartTime - farm start time.
// cooldownPeriod - cooldown period for locked deposits in days.
// cooldownPeriod = 0 Disables lockup functionality for the farm.
// farmRegistry - Address of the Demeter Farm Registry.
// camelotPoolData - init data for CamelotV3 pool.
// rwdTokenData - init data for reward tokens.
// camelotV3Factory - Factory contract of Camelot V3.
// nftContract - NFT contract's address (NFPM).
// camelotUtils - address of our custom camelot utils contract.
// nfpmUtils - address of our custom camelot nonfungible position manager utils contract.
struct InitializeInput {
    string farmId;
    uint256 farmStartTime;
    uint256 cooldownPeriod;
    address farmRegistry;
    CamelotPoolData camelotPoolData;
    RewardTokenData[] rwdTokenData;
    address camelotV3Factory;
    address nftContract;
    address camelotUtils;
    address nfpmUtils;
}

/// @title Camelot V3 farm.
/// @author Sperax Foundation.
/// @notice This contract is the implementation of the Camelot V3 farm.
contract CamelotV3Farm is E721Farm, OperableDeposit, ExpirableFarm, ClaimableFee {
    using SafeERC20 for IERC20;

    // CamelotV3 params.
    int24 public tickLowerAllowed;
    int24 public tickUpperAllowed;
    address public camelotPool;
    address public camelotV3Factory;
    address public camelotUtils; // CamelotUtils (Camelot helper) contract.
    address public nfpmUtils; // Camelot INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract.

    int256 internal constant MIN_TICK = -887272;
    int256 internal constant MAX_TICK = 887272;

    // Custom Errors.
    error InvalidCamelotPoolConfig();
    error IncorrectPoolToken();
    error IncorrectTickRange();
    error InvalidTickRange();
    error InvalidAmount();

    /// @notice Initializer function of this farm.
    /// @param _input A struct having all the input params.
    function initialize(InitializeInput calldata _input) external {
        _validateNonZeroAddr(_input.camelotV3Factory);
        _validateNonZeroAddr(_input.nftContract);
        _validateNonZeroAddr(_input.camelotUtils);
        _validateNonZeroAddr(_input.nfpmUtils);

        // initialize camelot related data.
        camelotPool = ICamelotV3Factory(_input.camelotV3Factory).poolByPair(
            _input.camelotPoolData.tokenA, _input.camelotPoolData.tokenB
        );
        if (camelotPool == address(0)) {
            revert InvalidCamelotPoolConfig();
        }
        _validateTickRange(_input.camelotPoolData.tickLowerAllowed, _input.camelotPoolData.tickUpperAllowed);

        tickLowerAllowed = _input.camelotPoolData.tickLowerAllowed;
        tickUpperAllowed = _input.camelotPoolData.tickUpperAllowed;
        camelotV3Factory = _input.camelotV3Factory;
        nftContract = _input.nftContract;
        camelotUtils = _input.camelotUtils;
        nfpmUtils = _input.nfpmUtils;
        _setupFarm(_input.farmId, _input.farmStartTime, _input.cooldownPeriod, _input.rwdTokenData);
        _setupFarmExpiry(_input.farmStartTime, _input.farmRegistry);
    }

    /// @notice Allow user to increase liquidity for a deposit.
    /// @param _depositId The id of the deposit to be increased.
    /// @param _amounts Desired amount of tokens to be increased.
    /// @param _minAmounts Minimum amount of tokens to be added as liquidity.
    function increaseDeposit(uint256 _depositId, uint256[2] calldata _amounts, uint256[2] calldata _minAmounts)
        external
        nonReentrant
    {
        _validateDeposit(msg.sender, _depositId);
        if (_amounts[0] + _amounts[1] == 0) {
            revert InvalidAmount();
        }

        address pm = nftContract;
        uint256 tokenId = depositToTokenId[_depositId];
        Position memory positions = ICamelotV3NFPMUtils(nfpmUtils).positions(pm, tokenId);

        // Transfer tokens from user to the contract.
        IERC20(positions.token0).safeTransferFrom(msg.sender, address(this), _amounts[0]);
        IERC20(positions.token1).safeTransferFrom(msg.sender, address(this), _amounts[1]);

        // Approve token to the NFPM contract.
        IERC20(positions.token0).forceApprove(pm, _amounts[0]);
        IERC20(positions.token1).forceApprove(pm, _amounts[1]);

        // Increases liquidity in the current range.
        (uint128 liquidity, uint256 amount0, uint256 amount1) = INFPM(pm).increaseLiquidity(
            INFPM.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: _amounts[0],
                amount1Desired: _amounts[1],
                amount0Min: _minAmounts[0],
                amount1Min: _minAmounts[1],
                deadline: block.timestamp
            })
        );

        _increaseDeposit(_depositId, liquidity);

        // Return the excess tokens to the user.
        if (amount0 < _amounts[0]) {
            IERC20(positions.token0).safeTransfer(msg.sender, _amounts[0] - amount0);
        }
        if (amount1 < _amounts[1]) {
            IERC20(positions.token1).safeTransfer(msg.sender, _amounts[1] - amount1);
        }
    }

    /// @notice Withdraw liquidity partially from an existing deposit.
    /// @param _depositId Deposit index for the user.
    /// @param _liquidityToWithdraw Amount to be withdrawn.
    /// @param _minAmounts Minimum amount of tokens to be received.
    function decreaseDeposit(uint256 _depositId, uint128 _liquidityToWithdraw, uint256[2] calldata _minAmounts)
        external
        nonReentrant
    {
        _decreaseDeposit(_depositId, _liquidityToWithdraw);

        address pm = nftContract;
        uint256 tokenId = depositToTokenId[_depositId];
        // Decrease liquidity in the current range.
        (uint256 amount0, uint256 amount1) = INFPM(pm).decreaseLiquidity(
            INFPM.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: _liquidityToWithdraw,
                amount0Min: _minAmounts[0],
                amount1Min: _minAmounts[1],
                deadline: block.timestamp
            })
        );

        // Transfer the tokens to the user.
        INFPM(pm).collect(
            INFPM.CollectParams({
                tokenId: tokenId,
                recipient: msg.sender,
                amount0Max: SafeCast.toUint128(amount0),
                amount1Max: SafeCast.toUint128(amount1)
            })
        );
    }

    /// @notice Function to be called by Demeter Rewarder to get tokens and amounts associated with the farm's liquidity.
    /// @return tokens An array of token addresses.
    /// @return amounts An array of token amounts.
    function getTokenAmounts() external view override returns (address[] memory, uint256[] memory) {
        return TokenUtils.getCamelotV3TokenAmounts({
            _camelotPool: camelotPool,
            _camelotUtils: camelotUtils,
            _tickLower: tickLowerAllowed,
            _tickUpper: tickUpperAllowed,
            _liquidity: rewardFunds[COMMON_FUND_ID].totalLiquidity
        });
    }

    // --------------------- Public and overriding Functions ---------------------

    /// @notice Update the farm start time.
    /// @param _newStartTime The new farm start time.
    /// @dev Calls ExpirableFarm's updateFarmStartTime function.
    function updateFarmStartTime(uint256 _newStartTime) public override(Farm, ExpirableFarm) {
        ExpirableFarm.updateFarmStartTime(_newStartTime);
    }

    /// @notice Returns if farm is open.
    ///         Farm is open if it is not closed.
    /// @return bool True if farm is open.
    /// @dev Calls ExpirableFarm's isOpenFarm function.
    function isFarmOpen() public view override(Farm, ExpirableFarm) returns (bool) {
        return ExpirableFarm.isFarmOpen();
    }

    /// @notice Claim pool fee implementation from `ClaimableFee` feature.
    /// @param _depositId Deposit ID of the deposit in the farm.
    function _claimPoolFee(uint256 _depositId)
        internal
        override
        returns (uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv)
    {
        tokenId = depositToTokenId[_depositId];
        (amt0Recv, amt1Recv) = INFPM(nftContract).collect(
            INFPM.CollectParams({
                tokenId: tokenId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    /// @notice Validate the position for the pool and get Liquidity.
    /// @param _tokenId The tokenId of the position.
    /// @return The liquidity of the position.
    /// @dev The position must adhere to the price ranges.
    /// @dev Only allow specific pool token to be staked.
    function _getLiquidity(uint256 _tokenId) internal view override returns (uint256) {
        /// @dev Get the info of the required token.
        Position memory positions = ICamelotV3NFPMUtils(nfpmUtils).positions(nftContract, _tokenId);

        /// @dev Check if the token belongs to correct pool.

        if (camelotPool != ICamelotV3Factory(camelotV3Factory).poolByPair(positions.token0, positions.token1)) {
            revert IncorrectPoolToken();
        }

        /// @dev Check if the token adheres to the tick range.
        if (positions.tickLower != tickLowerAllowed || positions.tickUpper != tickUpperAllowed) {
            revert IncorrectTickRange();
        }

        return uint256(positions.liquidity);
    }

    /// @notice Validate the ticks (upper and lower).
    /// @param _tickLower The lower tick of the range.
    /// @param _tickUpper The upper tick of the range.
    /// @dev The ticks must be within the max range and must be multiple of tickSpacing.
    function _validateTickRange(int24 _tickLower, int24 _tickUpper) private view {
        int24 spacing = ICamelotV3TickSpacing(camelotPool).tickSpacing();
        if (
            _tickLower >= _tickUpper || _tickLower < MIN_TICK || _tickLower % spacing != 0 || _tickUpper > MAX_TICK
                || _tickUpper % spacing != 0
        ) {
            revert InvalidTickRange();
        }
    }
}
