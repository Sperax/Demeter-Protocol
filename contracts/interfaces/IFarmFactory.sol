pragma solidity 0.8.10;

interface IFarmFactory {
    function registerFarm(address farm, address creator) external;

    function getFeeParams()
        external
        view
        returns (
            address feeFeceiver,
            address feeToken,
            uint256 feeAmount
        );
}
