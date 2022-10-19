pragma solidity 0.8.10;

import "./../interfaces/IFarmFactory.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract BaseFarmDeployer is Ownable {
    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDs = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public factory;
    // Stores the address of farmImplementation.
    address public farmImplementation;

    event FarmCreated(address farm, address creator, address indexed admin);
    event FeeCollected(
        address indexed creator,
        address token,
        uint256 amount,
        bool indexed claimable
    );

    function calculateFees(address tokenA, address tokenB)
        external
        view
        virtual
        returns (uint256);

    function _collectFee(address tokenA, address tokenB) internal virtual;

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) internal pure {
        require(_addr != address(0), "Invalid address");
    }
}
