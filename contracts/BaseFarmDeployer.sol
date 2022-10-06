pragma solidity 0.8.10;

import "./FarmFactory.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseFarmDeployer {
    using SafeERC20 for IERC20;

    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDs = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public factory;
    // Stores the address of farmImplementation.
    address public farmImplementation;

    event FarmCreated(address farm, address creator, address indexed admin);
    event FeeCollected(address token, uint256 amount);

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from farmFactory.
    function _collectFee(uint8 _discountPercentage) internal {
        (
            address feeReceiver,
            address feeToken,
            uint256 feeAmount
        ) = FarmFactory(factory).getFeeParams();
        if (_discountPercentage > 0){
            uint256 _discount = feeAmount * _discountPercentage / 100;
            feeAmount = feeAmount - _discount;
        }
        IERC20(feeToken).safeTransferFrom(msg.sender, feeReceiver, feeAmount);
        emit FeeCollected(feeToken, feeAmount);
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) internal pure {
        require(_addr != address(0), "Invalid address");
    }
}
