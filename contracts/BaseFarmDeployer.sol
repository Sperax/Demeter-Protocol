pragma solidity 0.8.10;

import "./../interfaces/IFarmFactory.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseFarmDeployer {
    using SafeERC20 for IERC20;

    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDs = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    uint256 public constant MAX_DISCOUNT = 100;
    address public factory;
    // Stores the address of farmImplementation.
    address public farmImplementation;
    address public owner;
    uint256 public discountOnSpaUSDsFarms;
    // List of deployers for which fee won't be charged.
    mapping(address => bool) public isPrivilegedDeployer;

    event FarmCreated(address farm, address creator, address indexed admin);
    event FeeCollected(
        address indexed creator,
        address token,
        uint256 amount,
        bool indexed claimable
    );
    event PrivilegeUpdated(address deployer, bool privilege);
    event DiscountOnSpaUSDsFarmsUpdated(
        uint256 oldDiscount,
        uint256 newDiscount
    );

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from farmFactory.
    function _collectFee(address _tokenA, address _tokenB) internal {
        (
            address feeReceiver,
            address feeToken,
            uint256 feeAmount,
            bool claimable
        ) = _calculateFees(_tokenA, _tokenB);
        if (feeAmount > 0) {
            IERC20(feeToken).safeTransferFrom(
                msg.sender,
                feeReceiver,
                feeAmount
            );
            emit FeeCollected(msg.sender, feeToken, feeAmount, claimable);
        }
    }

    /// @notice An internal function to calculate fees
    /// @notice and return feeReceiver, feeToken, feeAmount and claimable
    function _calculateFees(address _tokenA, address _tokenB)
        internal
        view
        returns (
            address,
            address,
            uint256,
            bool
        )
    {
        (
            address feeReceiver,
            address feeToken,
            uint256 feeAmount
        ) = IFarmFactory(factory).getFeeParams();
        if (isPrivilegedDeployer[msg.sender]) {
            // No fees for privileged deployers
            feeAmount = 0;
            return (feeReceiver, feeToken, feeAmount, false);
        }
        if (!_validateToken(_tokenA) && !_validateToken(_tokenB)) {
            // No discount because none of the tokens are SPA or USDs
            return (feeReceiver, feeToken, feeAmount, false);
        } else {
            // Discount if either of the tokens are SPA or USDs
            // This fees is claimable
            uint256 discountedFee = (feeAmount * discountOnSpaUSDsFarms) /
                MAX_DISCOUNT;
            return (feeReceiver, feeToken, discountedFee, true);
        }
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) internal pure {
        require(_addr != address(0), "Invalid address");
    }

    /// @notice Validate if a token is either SPA | USDs.
    /// @param _token Address of the desired token.
    function _validateToken(address _token) private pure returns (bool) {
        return _token == SPA || _token == USDs;
    }
}
