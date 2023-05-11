pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFarmFactory.sol";

abstract contract BaseFarmDeployer is Ownable {
    using SafeERC20 for IERC20;

    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDs = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public factory;
    // Stores the address of farmImplementation.
    address public farmImplementation;
    uint256 public discountedFee;

    event FarmCreated(address farm, address creator, address indexed admin);
    event FeeCollected(
        address indexed creator,
        address token,
        uint256 amount,
        bool indexed claimable
    );
    event FarmImplementationUpdated(address newFarmImplementation);
    event DiscountedFeeUpdated(
        uint256 oldDiscountedFee,
        uint256 newDiscountedFee
    );

    function updateFarmImplementation(address _newFarmImplementation)
        external
        onlyOwner
    {
        farmImplementation = _newFarmImplementation;
        emit FarmImplementationUpdated(_newFarmImplementation);
    }

    /// @notice An external function to update discountOnSpaUSDsFarms
    /// @param _discountedFee New desired discount on Spa/ USDs farms
    /// @dev _discountedFee cannot be more than 100
    function updateDiscountedFee(uint256 _discountedFee) external onlyOwner {
        emit DiscountedFeeUpdated(discountedFee, _discountedFee);
        discountedFee = _discountedFee;
    }

    /// @notice A public view function to calculate fees
    /// @param _tokenA address of token A
    /// @param _tokenB address of token B
    /// @notice Order does not matter
    /// @return Fees to be paid in feeToken set in FarmFactory (mostly USDs)
    function calculateFees(address _tokenA, address _tokenB)
        external
        view
        returns (
            address,
            address,
            uint256,
            bool
        )
    {
        _isNonZeroAddr(_tokenA);
        _isNonZeroAddr(_tokenB);
        require(_tokenA != _tokenB, "Invalid token pair");
        return _calculateFees(_tokenA, _tokenB);
    }

    /// @notice Collect fee and transfer it to feeReceiver.
    /// @dev Function fetches all the fee params from sfarmFactory.
    function _collectFee(address _tokenA, address _tokenB) internal virtual {
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
        if (IFarmFactory(factory).isPrivilegedDeployer(msg.sender)) {
            // No fees for privileged deployers
            feeAmount = 0;
            return (feeReceiver, feeToken, feeAmount, false);
        }
        if (!_validateToken(_tokenA) && !_validateToken(_tokenB)) {
            // No discount because neither of the token is SPA or USDs
            return (feeReceiver, feeToken, feeAmount, false);
        } else {
            // DiscountedFee if either of the token is SPA or USDs
            // This fees is claimable
            return (feeReceiver, feeToken, discountedFee, true);
        }
    }

    /// @notice Validate if a token is either SPA | USDs.
    /// @param _token Address of the desired token.
    function _validateToken(address _token) internal pure returns (bool) {
        return _token == SPA || _token == USDs;
    }

    /// @notice Validate address
    function _isNonZeroAddr(address _addr) internal pure {
        require(_addr != address(0), "Invalid address");
    }
}
