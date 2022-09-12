// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

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

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./UniswapFarmV1.sol";

contract UniswapFarmV1Factory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDs = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public constant feeReceiver =
        0x5b12d9846F8612E439730d18E1C12634753B1bF1;

    address public immutable implementation;
    address public feeToken;
    uint256 public feeAmount;
    uint256 public numFarmCreated;
    address[] public farms;

    event FeeCollected(address token, uint256 amount);
    event FarmCreated(address farmAdmin, address farm);

    /// @notice constructor
    /// @param _feeToken The fee token for farm creation.
    /// @param _feeAmount The fee amount to be paid by the creator.
    constructor(address _feeToken, uint256 _feeAmount) {
        _isNonZeroAddr(_feeToken);
        feeToken = _feeToken;
        feeAmount = _feeAmount;
        implementation = address(new UniswapFarmV1());
    }

    /// @notice Creates a new farm
    /// @param _farmAdmin Address that manages and configures the farm.
    /// @param _farmStartTime Start time for the farm.
    /// @param _cooldownPeriod (0 for disabling lockup functionality).
    /// @param _uniswapPoolData Configuration for uniswap pool tokens.
    /// @param _rewardData List of rewardTokens and tknManagers.
    function createFarm(
        address _farmAdmin,
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        UniswapPoolData memory _uniswapPoolData,
        RewardTokenData[] memory _rewardData
    ) external nonReentrant returns (address farm) {
        _isNonZeroAddr(_farmAdmin);
        _collectFees(_uniswapPoolData.tokenA, _uniswapPoolData.tokenB);
        UniswapFarmV1 farmInstance = UniswapFarmV1(
            Clones.clone(implementation)
        );
        farmInstance.initialize(
            _farmStartTime,
            _cooldownPeriod,
            _uniswapPoolData,
            _rewardData
        );
        farmInstance.transferOwnership(_farmAdmin);
        farm = address(farmInstance);
        farms.push(farm);
        numFarmCreated += 1;
        emit FarmCreated(_farmAdmin, farm);
    }

    /// @notice Collect fees for farm creation.
    /// @dev Collect fees only if neither of the tokens are SPA | USDs.
    /// @param _tokenA Address of tokenA from uniswapPoolConfig.
    /// @param _tokenB Address of tokenB from uniswapPoolConfig.
    function _collectFees(address _tokenA, address _tokenB) private {
        if (!_validateToken(_tokenA) && !_validateToken(_tokenB)) {
            IERC20(feeToken).safeTransferFrom(
                msg.sender,
                feeReceiver,
                feeAmount
            );
            emit FeeCollected(feeToken, feeAmount);
        }
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
