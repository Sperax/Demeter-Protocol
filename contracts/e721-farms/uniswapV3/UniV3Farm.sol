// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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
import {ExpirableFarm} from "../../features/ExpirableFarm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INFPM, IUniswapV3Factory, IUniswapV3TickSpacing} from "./interfaces/IUniswapV3.sol";
import {IUniswapV3Utils} from "./interfaces/IUniswapV3Utils.sol";
import {INFPMUtils, Position} from "./interfaces/INonfungiblePositionManagerUtils.sol";
import {Deposit} from "../../interfaces/DataTypes.sol";
import {OperableDeposit} from "../../features/OperableDeposit.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";

// Defines the Uniswap pool init data for constructor.
// tokenA - Address of tokenA
// tokenB - Address of tokenB
// feeTier - Fee tier for the Uniswap pool
// tickLowerAllowed - Lower bound of the tick range for farm
// tickUpperAllowed - Upper bound of the tick range for farm
struct UniswapPoolData {
    address tokenA;
    address tokenB;
    uint24 feeTier;
    int24 tickLowerAllowed;
    int24 tickUpperAllowed;
}

// Defines a struct for inputs used for initializing this farm.
// _farmId - String ID of the farm.
// _farmStartTime - time of farm start.
// _cooldownPeriod - cooldown period for locked deposits in days.
// _cooldownPeriod = 0 Disables lockup functionality for the farm.
// _farmRegistry - Address of the Demeter Farm Registry.
// _uniswapPoolData - init data for UniswapV3 pool.
// _rwdTokenData - init data for reward tokens.
// _uniV3Factory - Factory contract of Uniswap V3.
// _nftContract - NFT contract's address (NFPM).
// _uniswapUtils - address of our custom uniswap utils contract.
// _nfpmUtils - address of our custom uniswap nonfungible position manager utils contract
struct InitializeInput {
    string farmId;
    uint256 farmStartTime;
    uint256 cooldownPeriod;
    address farmRegistry;
    UniswapPoolData uniswapPoolData;
    RewardTokenData[] rwdTokenData;
    address uniV3Factory;
    address nftContract;
    address uniswapUtils;
    address nfpmUtils;
}

contract UniV3Farm is E721Farm, ExpirableFarm, OperableDeposit {
    using SafeERC20 for IERC20;

    // UniswapV3 params
    int24 public tickLowerAllowed;
    int24 public tickUpperAllowed;
    address public uniswapPool;
    address public uniV3Factory;
    address public uniswapUtils; // UniswapUtils (Uniswap helper) contract
    address public nfpmUtils; // Uniswap INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract

    event PoolFeeCollected(address indexed recipient, uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);

    // Custom Errors
    error InvalidUniswapPoolConfig();
    error NoFeeToClaim();
    error IncorrectPoolToken();
    error IncorrectTickRange();
    error InvalidTickRange();
    error InvalidAmount();

    /// @notice Initializer function of this farm
    /// @param _input A struct having all the input params.
    function initialize(InitializeInput calldata _input) external initializer {
        _validateNonZeroAddr(_input.uniV3Factory);
        _validateNonZeroAddr(_input.nftContract);
        _validateNonZeroAddr(_input.uniswapUtils);
        _validateNonZeroAddr(_input.nfpmUtils);

        // initialize uniswap related data
        uniswapPool = IUniswapV3Factory(_input.uniV3Factory).getPool(
            _input.uniswapPoolData.tokenA, _input.uniswapPoolData.tokenB, _input.uniswapPoolData.feeTier
        );
        if (uniswapPool == address(0)) {
            revert InvalidUniswapPoolConfig();
        }
        _validateTickRange(_input.uniswapPoolData.tickLowerAllowed, _input.uniswapPoolData.tickUpperAllowed);

        tickLowerAllowed = _input.uniswapPoolData.tickLowerAllowed;
        tickUpperAllowed = _input.uniswapPoolData.tickUpperAllowed;
        uniV3Factory = _input.uniV3Factory;
        nftContract = _input.nftContract;
        uniswapUtils = _input.uniswapUtils;
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
        Position memory positions = INFPMUtils(nfpmUtils).positions(pm, tokenId);

        // Transfer tokens from user to the contract.
        IERC20(positions.token0).safeTransferFrom(msg.sender, address(this), _amounts[0]);
        IERC20(positions.token1).safeTransferFrom(msg.sender, address(this), _amounts[1]);

        // Approve token to the NFPM contract.
        IERC20(positions.token0).forceApprove(pm, _amounts[0]);
        IERC20(positions.token1).forceApprove(pm, _amounts[1]);

        // Increases liquidity in the current range
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
                amount0Max: uint128(amount0),
                amount1Max: uint128(amount1)
            })
        );
    }

    /// @notice Claim uniswap pool fee for a deposit.
    /// @dev Only the deposit owner can claim the fee.
    /// @param _depositId Id of the deposit
    function claimUniswapFee(uint256 _depositId) external nonReentrant {
        _validateFarmOpen();
        _validateDeposit(msg.sender, _depositId);
        uint256 tokenId = depositToTokenId[_depositId];

        address pm = nftContract;
        (uint256 amt0, uint256 amt1) = IUniswapV3Utils(uniswapUtils).fees(pm, tokenId);
        if (amt0 == 0 && amt1 == 0) {
            revert NoFeeToClaim();
        }
        (uint256 amt0Recv, uint256 amt1Recv) = INFPM(pm).collect(
            INFPM.CollectParams({
                tokenId: tokenId,
                recipient: msg.sender,
                amount0Max: uint128(amt0),
                amount1Max: uint128(amt1)
            })
        );
        emit PoolFeeCollected(msg.sender, tokenId, amt0Recv, amt1Recv);
    }

    /// @notice Get the accrued uniswap fee for a deposit.
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function computeUniswapFee(uint256 _tokenId) external view returns (uint256 amount0, uint256 amount1) {
        // Validate token.
        _getLiquidity(_tokenId);
        return IUniswapV3Utils(uniswapUtils).fees(nftContract, _tokenId);
    }

    /// @notice A function to be called by Demeter Rewarder to get tokens and amounts associated with the farm's liquidity.
    function getTokenAmounts() external view override returns (address[] memory, uint256[] memory) {
        return TokenUtils.getUniV3TokenAmounts(
            uniswapPool, uniswapUtils, tickLowerAllowed, tickUpperAllowed, rewardFunds[COMMON_FUND_ID].totalLiquidity
        );
    }

    // --------------------- Public and overriding Functions ---------------------

    /// @notice Update the farm start time.
    /// @param _newStartTime The new farm start time.
    /// @dev Calls ExpirableFarm's updateFarmStartTime function
    function updateFarmStartTime(uint256 _newStartTime) public override(Farm, ExpirableFarm) onlyOwner {
        ExpirableFarm.updateFarmStartTime(_newStartTime);
    }

    /// @notice Returns if farm is open.
    ///         Farm is open if it not closed.
    /// @return bool true if farm is open.
    /// @dev Calls ExpirableFarm's isOpenFarm function.
    function isFarmOpen() public view override(Farm, ExpirableFarm) returns (bool) {
        return ExpirableFarm.isFarmOpen();
    }

    /// @notice Validate the position for the pool and get Liquidity
    /// @param _tokenId The tokenId of the position
    /// @dev the position must adhere to the price ranges
    /// @dev Only allow specific pool token to be staked.
    function _getLiquidity(uint256 _tokenId) internal view override returns (uint256) {
        /// @dev Get the info of the required token
        Position memory positions = INFPMUtils(nfpmUtils).positions(nftContract, _tokenId);

        /// @dev Check if the token belongs to correct pool

        if (uniswapPool != IUniswapV3Factory(uniV3Factory).getPool(positions.token0, positions.token1, positions.fee)) {
            revert IncorrectPoolToken();
        }

        /// @dev Check if the token adheres to the tick range
        if (positions.tickLower != tickLowerAllowed || positions.tickUpper != tickUpperAllowed) {
            revert IncorrectTickRange();
        }

        return uint256(positions.liquidity);
    }

    function _validateTickRange(int24 _tickLower, int24 _tickUpper) private view {
        int24 spacing = IUniswapV3TickSpacing(uniswapPool).tickSpacing();
        if (
            _tickLower >= _tickUpper || _tickLower < -887272 || _tickLower % spacing != 0 || _tickUpper > 887272
                || _tickUpper % spacing != 0
        ) {
            revert InvalidTickRange();
        }
    }
}
