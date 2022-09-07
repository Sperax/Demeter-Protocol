pragma solidity 0.8.10;

interface IFarmDeployer {
    function deploy(bytes memory _data) external returns (address, bool);
}
