// SPDX-License-Identifier: MIT Line
pragma solidity 0.8.16;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface INFTPoolFactory {
    function getPool(address _lpTokenAddr) external view returns (address);
}

interface INFTPool {
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

    /**
     * @dev Withdraw from a staking position
     *
     * Can only be called by spNFT's owner or approved address
     */
    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw)
        external;

    function updatePool() external;

    /**
     * @dev Harvest from a staking position to "to" address
     *
     * Can only be called by spNFT's owner or approved address
     * spNFT's owner must be a contract
     */
    function harvestPositionTo(uint256 tokenId, address to) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    function tokenOfOwnerByIndex(address owner, uint256 index)
        external
        view
        returns (uint256);

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

    function pendingRewards(uint256 tokenId) external view returns (uint256);
}

interface ICamelotFactory {
    function getPair(address _tokenA, address _tokenB)
        external
        view
        returns (address);

    function allPairs(uint256 _id) external view returns (address);

    function allPairsLength() external view returns (uint256);
}

interface INFTHandler is IERC721Receiver {
    function onNFTHarvest(
        address operator,
        address to,
        uint256 tokenId,
        uint256 grailAmount,
        uint256 xGrailAmount
    ) external returns (bool);
    //   function onNFTAddToPosition(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
    //   function onNFTWithdraw(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
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
