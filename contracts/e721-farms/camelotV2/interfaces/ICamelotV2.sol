// SPDX-License-Identifier: MIT Line
pragma solidity 0.8.16;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface INFTPoolFactory {
    function getPool(address _lpTokenAddr) external view returns (address);
}

interface IPair {
    function getReserves()
        external
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint16 _token0FeePercent, uint16 _token1FeePercent);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function totalSupply() external view returns (uint256);
}

interface INFTPool {
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

    /**
     * @dev Withdraw from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;

    function updatePool() external;

    /**
     * @dev Harvest from a staking position to "to" address
     *
     * Can only be called by spNFT's owner or approved address
     * spNFT's owner must be a contract
     */
    function harvestPositionTo(uint256 tokenId, address to) external;

    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    function lastTokenId() external view returns (uint256);

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    function getStakingPosition(uint256 tokenId)
        external
        view
        returns (
            uint256 amount,
            uint256 amountWithMultiplier,
            uint256 startLockTime,
            uint256 lockDuration,
            uint256 lockMultiplier,
            uint256 rewardDebt,
            uint256 boostPoints,
            uint256 totalMultiplier
        );

    function getPoolInfo()
        external
        view
        returns (
            address lpToken,
            address grailToken,
            address xGrailToken,
            uint256 lastRewardTime,
            uint256 accRewardsPerShare,
            uint256 lpSupply,
            uint256 lpSupplyWithMultiplier,
            uint256 allocPoint
        );

    function pendingRewards(uint256 tokenId) external view returns (uint256);
}

interface ICamelotV2Factory {
    function getPair(address _tokenA, address _tokenB) external view returns (address);

    function allPairs(uint256 _id) external view returns (address);

    function allPairsLength() external view returns (uint256);
}

interface INFTHandler is IERC721Receiver {
    function onNFTHarvest(address operator, address to, uint256 tokenId, uint256 grailAmount, uint256 xGrailAmount)
        external
        returns (bool);
    function onNFTAddToPosition(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
    function onNFTWithdraw(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
}

interface IPositionHelper {
    function addLiquidityAndCreatePosition(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline,
        address to,
        INFTPool nftPool,
        uint256 lockDuration
    ) external;

    function addLiquidityETHAndCreatePosition(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline,
        address to,
        INFTPool nftPool,
        uint256 lockDuration
    ) external payable;
}

interface IRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB);
}
