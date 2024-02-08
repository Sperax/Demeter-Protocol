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

import {
    INonfungiblePositionManager as INFPM,
    IUniswapV3Factory,
    IUniswapV3TickSpacing,
    CollectParams
} from "./interfaces/IUniswapV3.sol";
import {IUniswapUtils} from "./interfaces/IUniswapUtils.sol";
import {
    INonfungiblePositionManagerUtils as INFPMUtils, Position
} from "./interfaces/INonfungiblePositionManagerUtils.sol";
import {RewardTokenData} from "../../BaseFarm.sol";
import {BaseFarm, BaseE721Farm} from "../BaseE721Farm.sol";
import {BaseFarmWithExpiry} from "../../features/BaseFarmWithExpiry.sol";

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

contract BaseUniV3Farm is BaseE721Farm, BaseFarmWithExpiry {
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

    /// @notice constructor
    /// @param _farmId - String ID of the farm.
    /// @param _farmStartTime - time of farm start.
    /// @param _cooldownPeriod - cooldown period for locked deposits in days.
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _factory - Address of the farm factory.
    /// @param _uniswapPoolData - init data for UniswapV3 pool.
    /// @param _rwdTokenData - init data for reward tokens.
    /// @param _uniV3Factory - Factory contract of Uniswap V3.
    /// @param _nftContract - NFT contract's address (NFPM).
    /// @param _uniswapUtils - address of our custom uniswap utils contract.
    /// @param _nfpmUtils - address of our custom uniswap nonfungible position manager utils contract.
    function initialize(
        string calldata _farmId,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        address _factory,
        UniswapPoolData memory _uniswapPoolData,
        RewardTokenData[] memory _rwdTokenData,
        address _uniV3Factory,
        address _nftContract,
        address _uniswapUtils,
        address _nfpmUtils
    ) external initializer {
        _validateNonZeroAddr(_uniV3Factory);
        _validateNonZeroAddr(_nftContract);
        _validateNonZeroAddr(_uniswapUtils);
        _validateNonZeroAddr(_nfpmUtils);

        // initialize uniswap related data
        uniswapPool = IUniswapV3Factory(_uniV3Factory).getPool(
            _uniswapPoolData.tokenA, _uniswapPoolData.tokenB, _uniswapPoolData.feeTier
        );
        if (uniswapPool == address(0)) {
            revert InvalidUniswapPoolConfig();
        }
        _validateTickRange(_uniswapPoolData.tickLowerAllowed, _uniswapPoolData.tickUpperAllowed);

        tickLowerAllowed = _uniswapPoolData.tickLowerAllowed;
        tickUpperAllowed = _uniswapPoolData.tickUpperAllowed;
        uniV3Factory = _uniV3Factory;
        nftContract = _nftContract;
        uniswapUtils = _uniswapUtils;
        nfpmUtils = _nfpmUtils;
        _setupFarm(_farmId, _farmStartTime, _cooldownPeriod, _rwdTokenData);
        _setupFarmExpiry(_farmStartTime, _factory);
    }

    /// @notice Claim uniswap pool fee for a deposit.
    /// @dev Only the deposit owner can claim the fee.
    /// @param _depositId Id of the deposit
    function claimUniswapFee(uint256 _depositId) external nonReentrant {
        _validateFarmOpen();
        _validateDeposit(msg.sender, _depositId);
        uint256 tokenId = depositToTokenId[_depositId];

        address pm = nftContract;
        (uint256 amt0, uint256 amt1) = IUniswapUtils(uniswapUtils).fees(pm, tokenId);
        if (amt0 == 0 && amt1 == 0) {
            revert NoFeeToClaim();
        }
        (uint256 amt0Recv, uint256 amt1Recv) = INFPM(pm).collect(
            CollectParams({
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
        return IUniswapUtils(uniswapUtils).fees(nftContract, _tokenId);
    }

    // --------------------- Public and overriding Functions ---------------------

    /// @notice Update the farm start time.
    /// @param _newStartTime The new farm start time.
    /// @dev Calls BaseFarmWithExpiry's updateFarmStartTime function
    function updateFarmStartTime(uint256 _newStartTime) public override(BaseFarm, BaseFarmWithExpiry) onlyOwner {
        BaseFarmWithExpiry.updateFarmStartTime(_newStartTime);
    }

    /// @notice Returns if farm is open.
    ///         Farm is open if it not closed.
    /// @return bool true if farm is open.
    /// @dev Calls BaseFarmWithExpiry's isOpenFarm function.
    function isFarmOpen() public view override(BaseFarm, BaseFarmWithExpiry) returns (bool) {
        return BaseFarmWithExpiry.isFarmOpen();
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
