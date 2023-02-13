pragma solidity 0.8.10;

interface IUSDs {
function pauseSwitch(bool _isPaused) external;
function owner() external view returns(address);
}
