pragma solidity 0.8.10;

import "./interfaces/IFarmDeployer.sol";
import "./UniswapFarmV1.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract UniswapFarmV1Deployer is IFarmDeployer {
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        UniswapPoolData uniswapPoolData;
        RewardTokenData[] rewardData;
    }

    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDs = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public immutable factory;
    address public immutable implementation;

    constructor(address _factory) {
        _isNonZeroAddr(_factory);
        factory = _factory;
        implementation = address(new UniswapFarmV1());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data encoded data for deployment.
    function deploy(bytes memory _data) external returns (address, bool) {
        require(msg.sender == factory, "Caller not the Factory");
        FarmData memory data = abi.decode(_data, (FarmData));
        _isNonZeroAddr(data.farmAdmin);
        UniswapFarmV1 farmInstance = UniswapFarmV1(
            Clones.clone(implementation)
        );
        farmInstance.initialize(
            data.farmStartTime,
            data.cooldownPeriod,
            data.uniswapPoolData,
            data.rewardData
        );
        farmInstance.transferOwnership(data.farmAdmin);

        // A logic to check if fee collection is required for farm deployment
        // Collect fee only if neither of the token is either SPA | USDs
        bool collectFee = !_validateToken(data.uniswapPoolData.tokenA) &&
            !_validateToken(data.uniswapPoolData.tokenB);
        return (address(farmInstance), collectFee);
    }

    /// @notice Encodes deployment data for the farm.
    /// @param _data The struct that needs to be encoded
    function encodeDeploymentParam(FarmData memory _data)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(_data);
    }

    /// @notice Validate if a token is either SPA | USDs.
    /// @param _token Address of the desired token.
    function _validateToken(address _token) private pure returns (bool) {
        return _token == SPA || _token == USDs;
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Invalid address");
    }
}
