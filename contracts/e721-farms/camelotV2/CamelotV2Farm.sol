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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INFTPoolFactory, INFTPool, INFTHandler, IPair, IRouter} from "./interfaces/ICamelotV2.sol";
import {RewardTokenData} from "../../Farm.sol";
import {Farm, E721Farm} from "../E721Farm.sol";
import {OperableDeposit} from "../../features/OperableDeposit.sol";
import {ExpirableFarm} from "../../features/ExpirableFarm.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";

/// @title Camelot V2 farm.
/// @author Sperax Foundation.
/// @notice This contract is the implementation of the Camelot V2 farm.
contract CamelotV2Farm is E721Farm, INFTHandler, OperableDeposit, ExpirableFarm {
    using SafeERC20 for IERC20;

    // Camelot router.
    address public router;
    address internal poolLpToken;
    address internal poolToken0;
    address internal poolToken1;

    // Events.
    event PoolRewardsCollected(address indexed recipient, uint256 indexed tokenId, uint256 grailAmt, uint256 xGrailAmt);

    // Custom Errors.
    error InvalidCamelotPoolConfig();
    error NotAllowed();
    error InvalidAmount();

    /// @notice constructor.
    /// @param _farmId ID of the farm. E.g: `Demeter_Camelot_V2`.
    /// @param _farmStartTime - farm start time.
    /// @param _cooldownPeriod - Cooldown period for locked deposits in days.
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _farmRegistry - Address of the Demeter Farm Registry.
    /// @param _camelotPairPool - Camelot lp pool address.
    /// @param _rwdTokenData - Initialize data for reward tokens.
    /// @param _router Camelot Router's address.
    /// @param _nftPoolFactory Non fungible position manager contract for Camelot V2.
    function initialize(
        string calldata _farmId,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        address _farmRegistry,
        address _camelotPairPool,
        RewardTokenData[] memory _rwdTokenData,
        address _router,
        address _nftPoolFactory
    ) external {
        _validateNonZeroAddr(_router);
        // Initialize camelot related data nftContract = nft pool.
        nftContract = INFTPoolFactory(_nftPoolFactory).getPool(_camelotPairPool);
        if (nftContract == address(0)) {
            revert InvalidCamelotPoolConfig();
        }
        (address _lpToken,,,,,,,) = INFTPool(nftContract).getPoolInfo();

        router = _router;
        poolLpToken = _lpToken;
        poolToken0 = IPair(_lpToken).token0();
        poolToken1 = IPair(_lpToken).token1();
        _setupFarm(_farmId, _farmStartTime, _cooldownPeriod, _rwdTokenData);
        _setupFarmExpiry(_farmStartTime, _farmRegistry);
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

        // Memory variables to store storage variables.
        address lpToken = poolLpToken;
        address token0 = poolToken0;
        address token1 = poolToken1;

        IERC20(token0).safeTransferFrom(msg.sender, address(this), _amounts[0]);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), _amounts[1]);

        // Approve token to the router contract.
        IERC20(token0).forceApprove(router, _amounts[0]);
        IERC20(token1).forceApprove(router, _amounts[1]);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = IRouter(router).addLiquidity({
            tokenA: token0,
            tokenB: token1,
            amountADesired: _amounts[0],
            amountBDesired: _amounts[1],
            amountAMin: _minAmounts[0],
            amountBMin: _minAmounts[1],
            to: address(this),
            deadline: block.timestamp
        });

        IERC20(lpToken).forceApprove(nftContract, liquidity);
        INFTPool(nftContract).addToPosition(depositToTokenId[_depositId], liquidity);

        _increaseDeposit(_depositId, liquidity);

        // Return excess tokens back to the user.
        if (amountA < _amounts[0]) {
            IERC20(token0).safeTransfer(msg.sender, _amounts[0] - amountA);
        }
        if (amountB < _amounts[1]) {
            IERC20(token1).safeTransfer(msg.sender, _amounts[1] - amountB);
        }
    }

    /// @notice Withdraw liquidity partially from an existing deposit.
    /// @param _depositId Deposit index for the user.
    /// @param _liquidityToWithdraw Amount to be withdrawn.
    /// @param _minAmounts Minimum amount of tokens to be received.
    function decreaseDeposit(uint256 _depositId, uint256 _liquidityToWithdraw, uint256[2] calldata _minAmounts)
        external
        nonReentrant
    {
        _decreaseDeposit(_depositId, _liquidityToWithdraw);

        // Withdraw liquidity from nft pool
        INFTPool(nftContract).withdrawFromPosition(depositToTokenId[_depositId], _liquidityToWithdraw);
        IERC20(poolLpToken).forceApprove(router, _liquidityToWithdraw);
        IRouter(router).removeLiquidity({
            tokenA: poolToken0,
            tokenB: poolToken1,
            liquidity: _liquidityToWithdraw,
            amountAMin: _minAmounts[0],
            amountBMin: _minAmounts[1],
            to: msg.sender,
            deadline: block.timestamp
        });
    }

    /// @notice Claim uniswap pool fee for a deposit.
    /// @dev Only the deposit owner can claim the fee.
    /// @param _depositId Id of the deposit.
    function claimPoolRewards(uint256 _depositId) external nonReentrant {
        _validateFarmOpen();
        _validateDeposit(msg.sender, _depositId);
        INFTPool(nftContract).harvestPositionTo(depositToTokenId[_depositId], msg.sender);
    }

    /// @notice callback function for harvestPosition().
    function onNFTHarvest(address, address _to, uint256 _tokenId, uint256 _grailAmount, uint256 _xGrailAmount)
        external
        override
        returns (bool)
    {
        if (msg.sender != nftContract) {
            revert NotAllowed();
        }
        emit PoolRewardsCollected(_to, _tokenId, _grailAmount, _xGrailAmount);
        return true;
    }

    /// @notice Get the accrued camelot fee for a deposit.
    /// @param _tokenId The tokenId of the position.
    /// @return amount Grail rewards.
    function computePoolRewards(uint256 _tokenId) external view returns (uint256 amount) {
        // Validate token.
        amount = INFTPool(nftContract).pendingRewards(_tokenId);
        return amount;
    }

    /// @notice This function is called when liquidity is added to an existing position.
    function onNFTAddToPosition(address operator, uint256, /*tokenId*/ uint256 /*lpAmount*/ )
        external
        view
        override
        returns (bool)
    {
        if (operator != address(this)) revert NotAllowed();
        return true;
    }

    /// @notice This function is called when liquidity is withdrawn from an NFT position.
    function onNFTWithdraw(address operator, uint256, /*tokenId*/ uint256 /*lpAmount*/ )
        external
        view
        override
        returns (bool)
    {
        if (operator != address(this)) revert NotAllowed();
        return true;
    }

    /// @notice This function can be called before allocating funds into the strategy.
    ///         it accepts desired amounts, checks pool condition and returns the amount.
    ///         which will be needed/ accepted by the strategy for a balanced allocation.
    /// @param amountADesired Amount of token A that is desired to be allocated.
    /// @param amountBDesired Amount of token B that is desired to be allocated.
    /// @return amountA Amount A tokens which will be accepted in allocation.
    /// @return amountB Amount B tokens which will be accepted in allocation.
    function getDepositAmounts(uint256 amountADesired, uint256 amountBDesired)
        external
        view
        returns (uint256 amountA, uint256 amountB)
    {
        (address pair,,,,,,,) = INFTPool(nftContract).getPoolInfo();
        (uint112 reserveA, uint112 reserveB,,) = IPair(pair).getReserves();
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = IRouter(router).quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = IRouter(router).quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// @notice Function to be called by Demeter Rewarder to get tokens and amounts associated with the farm's liquidity.
    /// @return tokens An array of token addresses.
    /// @return amounts An array of token amounts.
    function getTokenAmounts() external view override returns (address[] memory tokens, uint256[] memory amounts) {
        return TokenUtils.getUniV2TokenAmounts(nftContract, rewardFunds[COMMON_FUND_ID].totalLiquidity);
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

    // --------------------- Private  Functions ---------------------

    /// @notice Validate the position for the pool and get Liquidity.
    /// @param _tokenId The tokenId of the position.
    /// @dev The position must adhere to the price ranges.
    /// @dev Only allow specific pool token to be staked.
    /// @return liquidity The liquidity of the position.
    function _getLiquidity(uint256 _tokenId) internal view override returns (uint256) {
        /// @dev Get the info of the required token
        (uint256 liquidity,,,,,,,) = INFTPool(nftContract).getStakingPosition(_tokenId);

        return liquidity;
    }
}
