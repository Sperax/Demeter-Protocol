pragma solidity 0.8.10;

interface IveSPA {
    function getLastUserSlope(address addr) external view returns (int128);

    function lockedEnd(address addr) external view returns (uint256);
}
