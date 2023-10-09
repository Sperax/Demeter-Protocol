// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@&....(@@@@@@@@@@@@@..../@@@@@@@@@//
//@@@@@@........../@@@@@@@........../@@@@@@//
//@@@@@............(@@@@@............(@@@@@//
//@@@@@(............@@@@@(...........&@@@@@//
//@@@@@@@...........&@@@@@@.........@@@@@@@//
//@@@@@@@@@@@@@@%..../@@@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@...@@@@@@@@@@@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@......(&@@@@@@@@@@@@//
//@@@@@@#.........@@@@@@#...........@@@@@@@//
//@@@@@/...........%@@@@@............%@@@@@//
//@@@@@............#@@@@@............%@@@@@//
//@@@@@@..........#@@@@@@@/.........#@@@@@@//
//@@@@@@@@@&/.(@@@@@@@@@@@@@@&/.(&@@@@@@@@@//
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFarmFactory} from "./interfaces/IFarmFactory.sol";

/**
 * @title BaseFarmDeployer
 * @dev An abstract contract for deploying farms with fees and discounts.
 */
abstract contract BaseFarmDeployer is Ownable {
    using SafeERC20 for IERC20;

    // Define constants for SPA and USDs tokens.
    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;

    address public immutable factory; // Address of the factory contract.

    address public farmImplementation; // Stores the address of the farm implementation contract.
    uint256 public discountedFee; // Discounted fee percentage for SPA/USDs farms.

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

    // Custom error messages.
    error InvalidTokenPair();
    error InvalidAddress();

    /**
     * @dev Constructor to initialize the contract with the factory address.
     * @param _factory Address of the factory contract.
     */
    constructor(address _factory) {
        _isNonZeroAddr(_factory);
        factory = _factory;
    }

    /**
     * @notice Update the farm implementation contract address.
     * @param _newFarmImplementation New address of the farm implementation.
     */
    function updateFarmImplementation(address _newFarmImplementation)
        external
        onlyOwner
    {
        farmImplementation = _newFarmImplementation;
        emit FarmImplementationUpdated(_newFarmImplementation);
    }

    /**
     * @notice Update the discounted fee percentage for SPA/USDs farms.
     * @param _discountedFee New discounted fee percentage (cannot exceed 100).
     */
    function updateDiscountedFee(uint256 _discountedFee) external onlyOwner {
        emit DiscountedFeeUpdated(discountedFee, _discountedFee);
        discountedFee = _discountedFee;
    }

    /**
     * @notice Calculate the fees for creating a farm with two tokens.
     * @param _tokenA Address of token A.
     * @param _tokenB Address of token B.
     * @return feeReceiver Address that will receive the fee.
     * @return feeToken Address of the fee token.
     * @return feeAmount Amount of the fee.
     * @return claimable True if the fee is claimable, false otherwise.
     */
    function calculateFees(address _tokenA, address _tokenB)
        external
        view
        returns (
            address feeReceiver,
            address feeToken,
            uint256 feeAmount,
            bool claimable
        )
    {
        _isNonZeroAddr(_tokenA);
        _isNonZeroAddr(_tokenB);
        if (_tokenA == _tokenB) {
            revert InvalidTokenPair();
        }
        return _calculateFees(_tokenA, _tokenB);
    }

    /**
     * @notice Collect the calculated fee and transfer it to the feeReceiver.
     * @param _tokenA Address of token A.
     * @param _tokenB Address of token B.
     */
    function _collectFee(address _tokenA, address _tokenB) internal virtual {
        (
            address feeReceiver,
            address feeToken,
            uint256 feeAmount,
            bool claimable
        ) = _calculateFees(_tokenA, _tokenB);
        if (feeAmount != 0) {
            IERC20(feeToken).safeTransferFrom(
                msg.sender,
                feeReceiver,
                feeAmount
            );
            emit FeeCollected(msg.sender, feeToken, feeAmount, claimable);
        }
    }

    /**
     * @notice Internal function to calculate the fees for creating a farm.
     * @param _tokenA Address of token A.
     * @param _tokenB Address of token B.
     * @return feeReceiver Address that will receive the fee.
     * @return feeToken Address of the fee token.
     * @return feeAmount Amount of the fee.
     * @return claimable True if the fee is claimable, false otherwise.
     */
    function _calculateFees(address _tokenA, address _tokenB)
        internal
        view
        returns (
            address feeReceiver,
            address feeToken,
            uint256 feeAmount,
            bool claimable
        )
    {
        (feeReceiver, feeToken, feeAmount) = IFarmFactory(factory)
            .getFeeParams();
        if (IFarmFactory(factory).isPrivilegedDeployer(msg.sender)) {
            // No fees for privileged deployers
            feeAmount = 0;
            return (feeReceiver, feeToken, feeAmount, false);
        }
        if (_checkToken(_tokenA) || _checkToken(_tokenB)) {
            // DiscountedFee if either of the tokens is SPA or USDs
            // This fee is claimable
            return (feeReceiver, feeToken, discountedFee, true);
        } else {
            // No discount because neither of the tokens is SPA or USDs
            return (feeReceiver, feeToken, feeAmount, false);
        }
    }

    /**
     * @notice Check if a token is either SPA or USDs.
     * @param _token Address of the desired token.
     * @return True if the token is SPA or USDs, false otherwise.
     */
    function _checkToken(address _token) internal pure returns (bool) {
        return _token == SPA || _token == USDS;
    }

    /**
     * @notice Validate address is non-zero.
     * @param _addr Address to be validated.
     */
    function _isNonZeroAddr(address _addr) internal pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }
}
