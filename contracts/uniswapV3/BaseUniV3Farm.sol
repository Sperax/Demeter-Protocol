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

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
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
import {BaseFarm, RewardTokenData} from "../BaseFarm.sol";

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

abstract contract BaseUniV3Farm is BaseFarm, IERC721Receiver {
    // UniswapV3 params
    int24 public tickLowerAllowed;
    int24 public tickUpperAllowed;
    address public uniswapPool;
    address public uniswapUtils; // UniswapUtils (Uniswap helper) contract
    address public nfpmUtils; // Uniswap INonfungiblePositionManagerUtils (NonfungiblePositionManager helper) contract

    mapping(uint256 => uint256) public depositToToken;

    event PoolFeeCollected(address indexed recipient, uint256 tokenId, uint256 amt0Recv, uint256 amt1Recv);

    // Custom Errors
    error InvalidUniswapPoolConfig();
    error NotAUniV3NFT();
    error NoData();
    error NoFeeToClaim();
    error IncorrectPoolToken();
    error IncorrectTickRange();
    error InvalidTickRange();

    /// @notice constructor
    /// @param _farmStartTime - time of farm start
    /// @param _cooldownPeriod - cooldown period for locked deposits in days
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _uniswapPoolData - init data for UniswapV3 pool
    /// @param _rwdTokenData - init data for reward tokens
    function initialize(
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        UniswapPoolData memory _uniswapPoolData,
        RewardTokenData[] memory _rwdTokenData,
        address _uniswapUtils,
        address _nfpmUtils
    ) external initializer {
        _isNonZeroAddr(_uniswapUtils);
        _isNonZeroAddr(_nfpmUtils);

        // initialize uniswap related data
        uniswapPool = IUniswapV3Factory(UNIV3_FACTORY()).getPool(
            _uniswapPoolData.tokenA, _uniswapPoolData.tokenB, _uniswapPoolData.feeTier
        );
        if (uniswapPool == address(0)) {
            revert InvalidUniswapPoolConfig();
        }
        _validateTickRange(_uniswapPoolData.tickLowerAllowed, _uniswapPoolData.tickUpperAllowed);
        tickLowerAllowed = _uniswapPoolData.tickLowerAllowed;
        tickUpperAllowed = _uniswapPoolData.tickUpperAllowed;
        uniswapUtils = _uniswapUtils;
        nfpmUtils = _nfpmUtils;

        _setupFarm(_farmStartTime, _cooldownPeriod, _rwdTokenData);
    }

    /// @notice Function is called when user transfers the NFT to the contract.
    /// @param _from The address of the owner.
    /// @param _tokenId nft Id generated by uniswap v3.
    /// @param _data The data should be the lockup flag (bool).
    function onERC721Received(
        address, // unused variable. not named
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        if (msg.sender != NFPM()) {
            revert NotAUniV3NFT();
        }
        if (_data.length == 0) {
            revert NoData();
        }
        uint256 liquidity = _getLiquidity(_tokenId);
        // Validate the position and get the liquidity

        _deposit(_from, abi.decode(_data, (bool)), liquidity);
        depositToToken[totalDeposits] = _tokenId;
        return this.onERC721Received.selector;
    }

    /// @notice Function to lock a staked deposit
    /// @param _depositId The id of the deposit to be locked
    /// @dev _depositId is corresponding to the user's deposit
    function initiateCooldown(uint256 _depositId) external override nonReentrant {
        _initiateCooldown(_depositId);
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param _depositId The id of the deposit to be withdrawn
    function withdraw(uint256 _depositId) external override nonReentrant {
        _isValidDeposit(msg.sender, _depositId);

        _withdraw(msg.sender, _depositId);
        // Transfer the nft back to the user.
        INFPM(NFPM()).safeTransferFrom(address(this), msg.sender, depositToToken[_depositId]);
        delete depositToToken[_depositId];
    }

    /// @notice Claim uniswap pool fee for a deposit.
    /// @dev Only the deposit owner can claim the fee.
    /// @param _depositId Id of the deposit
    function claimUniswapFee(uint256 _depositId) external nonReentrant {
        _farmNotClosed();
        _isValidDeposit(msg.sender, _depositId);
        uint256 tokenId = depositToToken[_depositId];

        address pm = NFPM();
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
        return IUniswapUtils(uniswapUtils).fees(NFPM(), _tokenId);
    }

    // solhint-disable-next-line func-name-mixedcase
    function NFPM() public pure virtual returns (address);

    // solhint-disable-next-line func-name-mixedcase
    function UNIV3_FACTORY() public pure virtual returns (address);

    /// @notice Validate the position for the pool and get Liquidity
    /// @param _tokenId The tokenId of the position
    /// @dev the position must adhere to the price ranges
    /// @dev Only allow specific pool token to be staked.
    function _getLiquidity(uint256 _tokenId) private view returns (uint256) {
        /// @dev Get the info of the required token
        Position memory positions = INFPMUtils(nfpmUtils).positions(NFPM(), _tokenId);

        /// @dev Check if the token belongs to correct pool

        if (
            uniswapPool != IUniswapV3Factory(UNIV3_FACTORY()).getPool(positions.token0, positions.token1, positions.fee)
        ) {
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
