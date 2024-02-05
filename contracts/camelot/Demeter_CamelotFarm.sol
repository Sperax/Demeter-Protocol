// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@&....(@@@@@@@@@@@@@..../@@@@@@@@@//
//@@@@@@........../@@@@@@@........../@@@@@@//
//@@@@@............(@@@@@............(@@@@@//
//@@@@@(............@@@@@(...........&@@@@@//
//@@@@@@@...........&@@@@@@.........@@@@@@@//
//@@@@@@@@@@@@@@%..../@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@...@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@......(&@@@@@@@@@@@@//
//@@@@@@#.........@@@@@@#...........@@@@@@@//
//@@@@@/...........%@@@@@............%@@@@@//
//@@@@@............#@@@@@............%@@@@@//
//@@@@@@..........#@@@@@@@/.........#@@@@@@//
//@@@@@@@@@&/.(@@@@@@@@@@@@@@&/.(&@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INFTPoolFactory, INFTPool, INFTHandler, IPair, IRouter} from "./interfaces/ICamelot.sol";
import {RewardTokenData} from "../BaseFarm.sol";
import {BaseFarmWithExpiry} from "../features/BaseFarmWithExpiry.sol";
import {Deposit} from "../interfaces/DataTypes.sol";
import {OperableDeposit} from "../features/OperableDeposit.sol";

contract Demeter_CamelotFarm is BaseFarmWithExpiry, INFTHandler, OperableDeposit {
    using SafeERC20 for IERC20;

    // Camelot NFT pool address
    address public nftPool;
    // Camelot router
    address public router;

    mapping(uint256 => uint256) public depositToTokenId;

    event PoolRewardsCollected(address indexed recipient, uint256 indexed tokenId, uint256 grailAmt, uint256 xGrailAmt);

    // Custom Errors
    error InvalidCamelotPoolConfig();
    error NotACamelotNFT();
    error NoData();
    error NotAllowed();
    error InvalidAmount();

    /// @notice constructor
    /// @param _farmStartTime - time of farm start
    /// @param _cooldownPeriod - cooldown period for locked deposits in days
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _factory - Address of the farm factory
    /// @param _camelotPairPool - Camelot lp pool address
    /// @param _rwdTokenData - init data for reward tokens
    function initialize(
        string calldata _farmId,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        address _factory,
        address _camelotPairPool,
        RewardTokenData[] memory _rwdTokenData,
        address _router,
        address _nftPoolFactory
    ) external initializer {
        _isNonZeroAddr(_router);
        // initialize uniswap related data
        nftPool = INFTPoolFactory(_nftPoolFactory).getPool(_camelotPairPool);
        if (nftPool == address(0)) {
            revert InvalidCamelotPoolConfig();
        }

        router = _router;
        _setupFarm(_farmId, _farmStartTime, _cooldownPeriod, _rwdTokenData);
        _setupFarmExpiry(_farmStartTime, _factory);
    }

    /// @notice Function is called when user transfers the NFT to the contract.
    /// @param _from The address of the owner.
    /// @param _tokenId nft Id generated by camelot.
    /// @param _data The data should be the lockup flag (bool).
    function onERC721Received(
        address, // unused variable. not named
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        if (msg.sender != nftPool) {
            revert NotACamelotNFT();
        }
        if (_data.length == 0) {
            revert NoData();
        }
        uint256 liquidity = _getLiquidity(_tokenId);
        // Execute common deposit function
        uint256 depositId = _deposit(_from, abi.decode(_data, (bool)), liquidity);
        depositToTokenId[depositId] = _tokenId;
        return this.onERC721Received.selector;
    }

    /// @notice Allow user to increase liquidity for a deposit.
    /// @param _depositId The id of the deposit to be increased.
    /// @param _amounts Desired amount of tokens to be increased.
    /// @param _minAmounts Minimum amount of tokens to be added as liquidity.
    function increaseDeposit(uint256 _depositId, uint256[2] calldata _amounts, uint256[2] calldata _minAmounts)
        external
        nonReentrant
    {
        _farmNotPaused(); // Allow increase deposit only when farm is not paused.
        _isValidDeposit(msg.sender, _depositId); // Validate the deposit.

        if (_amounts[0] + _amounts[1] == 0) {
            revert InvalidAmount();
        }

        Deposit storage userDeposit = deposits[_depositId];
        if (userDeposit.expiryDate != 0) {
            revert DepositIsInCooldown();
        }

        uint256 tokenId = depositToTokenId[_depositId];
        (address lpToken,,,,,,,) = INFTPool(nftPool).getPoolInfo();

        address token0 = IPair(lpToken).token0();
        address token1 = IPair(lpToken).token1();
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

        IERC20(lpToken).forceApprove(nftPool, liquidity);
        INFTPool(nftPool).addToPosition(tokenId, liquidity);

        // claim the pending rewards for the deposit
        _updateAndClaimFarmRewards(msg.sender, _depositId);

        _updateSubscriptionForIncrease(_depositId, liquidity);
        userDeposit.liquidity += liquidity;

        // Return excess tokens back to the user.
        if (amountA < _amounts[0]) {
            IERC20(token0).safeTransfer(msg.sender, _amounts[0] - amountA);
        }
        if (amountB < _amounts[1]) {
            IERC20(token1).safeTransfer(msg.sender, _amounts[1] - amountB);
        }

        emit DepositIncreased(_depositId, liquidity);
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param _depositId The id of the deposit to be withdrawn
    function withdraw(uint256 _depositId) external override nonReentrant {
        _isValidDeposit(msg.sender, _depositId);

        _withdraw(msg.sender, _depositId);
        // Transfer the nft back to the user.
        INFTPool(nftPool).safeTransferFrom(address(this), msg.sender, depositToTokenId[_depositId]);
        delete depositToTokenId[_depositId];
    }

    function decreaseDeposit(uint256 _depositId, uint256 _liquidityToWithdraw, uint256[2] calldata _minAmounts)
        external
        nonReentrant
    {
        _isFarmActive(); // Withdraw instead of decrease deposit when a farm is not active.
        _isValidDeposit(msg.sender, _depositId); // Validate the deposit.

        Deposit storage userDeposit = deposits[_depositId];

        if (_liquidityToWithdraw == 0) {
            revert CannotWithdrawZeroAmount();
        }

        if (userDeposit.expiryDate != 0 || userDeposit.cooldownPeriod != 0) {
            revert DecreaseDepositNotPermitted();
        }

        uint256 tokenId = depositToTokenId[_depositId];

        // Withdraw liquidity from nft pool
        INFTPool(nftPool).withdrawFromPosition(tokenId, _liquidityToWithdraw);
        (address lpToken,,,,,,,) = INFTPool(nftPool).getPoolInfo();
        address token0 = IPair(lpToken).token0();
        address token1 = IPair(lpToken).token1();
        IERC20(lpToken).forceApprove(router, _liquidityToWithdraw);
        IRouter(router).removeLiquidity({
            tokenA: token0,
            tokenB: token1,
            liquidity: _liquidityToWithdraw,
            amountAMin: _minAmounts[0],
            amountBMin: _minAmounts[1],
            to: msg.sender,
            deadline: block.timestamp
        });

        // claim the pending rewards for the deposit
        _updateAndClaimFarmRewards(msg.sender, _depositId);

        // Update deposit Information
        _updateSubscriptionForDecrease(_depositId, _liquidityToWithdraw);
        userDeposit.liquidity -= _liquidityToWithdraw;

        emit DepositDecreased(_depositId, _liquidityToWithdraw);
    }

    /// @notice Claim uniswap pool fee for a deposit.
    /// @dev Only the deposit owner can claim the fee.
    /// @param _depositId Id of the deposit
    function claimPoolRewards(uint256 _depositId) external nonReentrant {
        _isFarmActive();
        _isValidDeposit(msg.sender, _depositId);
        INFTPool(nftPool).harvestPositionTo(depositToTokenId[_depositId], msg.sender);
    }

    /// @notice callback function for harvestPosition().
    function onNFTHarvest(address, address _to, uint256 _tokenId, uint256 _grailAmount, uint256 _xGrailAmount)
        external
        override
        returns (bool)
    {
        if (msg.sender != nftPool) {
            revert NotAllowed();
        }
        emit PoolRewardsCollected(_to, _tokenId, _grailAmount, _xGrailAmount);
        return true;
    }

    /// @notice Get the accrued uniswap fee for a deposit.
    /// @return amount Grail rewards.
    function computePoolRewards(uint256 _tokenId) external view returns (uint256 amount) {
        // Validate token.
        amount = INFTPool(nftPool).pendingRewards(_tokenId);
        return amount;
    }

    /// @notice This function is called when liquidity is added to an existing position
    function onNFTAddToPosition(address operator, uint256, /*tokenId*/ uint256 /*lpAmount*/ )
        external
        view
        returns (bool)
    {
        if (operator != address(this)) revert NotAllowed();
        return true;
    }

    /// @notice This function is called when liquidity is withdrawn from an NFT position
    function onNFTWithdraw(address operator, uint256, /*tokenId*/ uint256 /*lpAmount*/ ) external view returns (bool) {
        if (operator != address(this)) revert NotAllowed();
        return true;
    }

    /// @notice This function can be called before allocating funds into the strategy
    ///         it accepts desired amounts, checks pool condition and returns the amount
    ///         which will be needed/ accepted by the strategy for a balanced allocation
    /// @param amountADesired Amount of token A that is desired to be allocated
    /// @param amountBDesired Amount of token B that is desired to be allocated
    /// @return amountA Amount A tokens which will be accepted in allocation
    /// @return amountB Amount B tokens which will be accepted in allocation
    function getDepositAmounts(uint256 amountADesired, uint256 amountBDesired)
        external
        view
        returns (uint256 amountA, uint256 amountB)
    {
        (address pair,,,,,,,) = INFTPool(nftPool).getPoolInfo();
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

    // --------------------- Private  Functions ---------------------

    /// @notice Validate the position for the pool and get Liquidity
    /// @param _tokenId The tokenId of the position
    /// @dev the position must adhere to the price ranges
    /// @dev Only allow specific pool token to be staked.
    function _getLiquidity(uint256 _tokenId) private view returns (uint256) {
        /// @dev Get the info of the required token
        (uint256 liquidity,,,,,,,) = INFTPool(nftPool).getStakingPosition(_tokenId);

        return uint256(liquidity);
    }
}
