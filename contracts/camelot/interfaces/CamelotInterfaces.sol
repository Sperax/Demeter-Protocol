pragma solidity 0.8.10;

// Camelot position helper: https://arbiscan.io/address/0xe458018Ad4283C90fB7F5460e24C4016F81b8175#code
// NFTPoolFactory: 0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d https://arbiscan.io/address/0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d
// Factory: 0x6EcCab422D763aC031210895C81787E87B43A652 https://arbiscan.io/address/0x6EcCab422D763aC031210895C81787E87B43A652#code
// Router: 0xc873fEcbd354f5A56E00E710B90EF4201db2448d https://arbiscan.io/address/0xc873fEcbd354f5A56E00E710B90EF4201db2448d
// USDs: 0xD74f5255D557944cf7Dd0E45FF521520002D5748
// USDC: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
// USDs-USDC lp:
// USDs-USDC nft pool:

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
