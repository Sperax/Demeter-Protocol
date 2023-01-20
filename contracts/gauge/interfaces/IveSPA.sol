pragma solidity 0.8.10;

interface IveSPA {
    struct Point {
        int128 bias; // veSPA value at this point
        int128 slope; // slope at this point
        int128 residue; // residue calculated at this point
        uint256 ts; // timestamp of this point
        uint256 blk; // block number of this point
    }

    struct LockedBalance {
        bool autoCooldown; // if true, the user's deposit will have a default cooldown.
        bool cooldownInitiated; // Determines if the cooldown has been initiated.
        uint128 amount; // amount of SPA locked for a user.
        uint256 end; // the expiry time of the deposit.
    }

    function checkpoint() external;

    function depositFor(address addr, uint128 value) external;

    function createLock(
        uint128 value,
        uint256 unlockTime,
        bool autoCooldown
    ) external;

    function increaseAmount(uint128 value) external;

    function increaseUnlockTime(uint256 unlockTime) external;

    function initiateCooldown() external;

    function withdraw() external;

    function getLastUserSlope(address addr) external view returns (int128);

    function lockedBalances(address addr)
        external
        view
        returns (LockedBalance memory);

    function lockedEnd(address addr) external view returns (uint256);

    function getUserPointHistoryTS(address addr, uint256 idx)
        external
        view
        returns (uint256);

    function userPointEpoch(address addr) external view returns (uint256);

    function balanceOf(address addr, uint256 ts)
        external
        view
        returns (uint256);

    function balanceOf(address addr) external view returns (uint256);

    function balanceOfAt(address, uint256 blockNumber)
        external
        view
        returns (uint256);

    function totalSupply(uint256 ts) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalSupplyAt(uint256 blockNumber) external view returns (uint256);

    function pointHistory(uint256 epoch) external view returns (Point memory);

    function userPointHistory(uint256 epoch)
        external
        view
        returns (Point memory);

    function epoch() external view returns (uint256);
}
