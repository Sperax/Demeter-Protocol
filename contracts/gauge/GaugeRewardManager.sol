pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IGaugeController.sol";
import "./interfaces/IFarm.sol";

contract GaugeRewardManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    uint256 public constant WEEK = 1 weeks;
    uint256 public constant PREC = 10000;
    uint256 public constant MULTIPLIER = 1e18;
    bool public distributionsOn;
    address public immutable EMERGENCY_RETURN;
    address public gaugeController;
    uint256 public globalSPAEmission; // SPA Emissions per week

    mapping(address => uint256) public nextRewardTime; // Tracks the last reward time for a gauge.

    // Essential for lockup farm
    // If not set a 100% will go to common fund
    mapping(address => uint256) public lockupFundSplit; // 500 for 5%

    event RewardsRecovered(address _recoveryAddr, uint256 _amount);
    event RewardsDistributed(address _gAddr, uint256 _amount);
    event DistributionsToggled(bool _distributionsOn);
    event LockupFundSplitUpdated(uint256 _oldSplit, uint256 _newSplit);

    constructor(
        uint256 _globalEmissionRate,
        address _gaugeController,
        address _emergencyReturn
    ) public {
        gaugeController = _gaugeController;
        globalSPAEmission = _globalEmissionRate;
        EMERGENCY_RETURN = _emergencyReturn;
        distributionsOn = true;
    }

    /// @notice Function set the global SPA emission rate per week
    /// @param _newEmission New emission rate
    function updateGlobalEmission(uint256 _newEmission) external onlyOwner {
        globalSPAEmission = _newEmission;
    }

    /// @notice Function to recover reward funds on Emergencies
    function recoverRewards() external onlyOwner nonReentrant {
        uint256 rewardBal = IERC20(SPA).balanceOf(address(this));
        IERC20(SPA).safeTransfer(EMERGENCY_RETURN, rewardBal);
        emit RewardsRecovered(EMERGENCY_RETURN, rewardBal);
    }

    /// @notice Switch reward distributions on/off
    function toggleDistributions() external onlyOwner {
        distributionsOn = !distributionsOn;
        emit DistributionsToggled(distributionsOn);
    }

    /// @notice Updates the reward split for lockup and no-lockup reward funds.
    /// @param _gAddr Gauge address
    /// @param _newSplit new split percent
    /// @dev _newSplit = 500 for 5%
    function updateLockupRewardSplit(address _gAddr, uint256 _newSplit)
        external
        onlyOwner
    {
        IFarm farm = IFarm(_gAddr);
        require(farm.cooldownPeriod() != 0, "Lockup not enabled.");
        require(_newSplit <= PREC, "Invalid split value");
        uint256 oldSplit = lockupFundSplit[_gAddr];
        lockupFundSplit[_gAddr] = _newSplit;
        emit LockupFundSplitUpdated(oldSplit, _newSplit);
    }

    /// @notice Transfer SPA token management to new Address.
    /// @dev Ensure the _newSPAManager is a wallet | a contract which has
    ///      a transferSPAManagement function.
    /// @param _gAddr Address of the gauge.
    /// @param _newSPAManager New manager address.
    function transferSPAManagement(address _gAddr, address _newSPAManager)
        external
        onlyOwner
    {
        IFarm(_gAddr).updateTokenManager(SPA, _newSPAManager);
    }

    /// @notice Get the remaining balance out of the  farm
    /// @param _gAddr Address of the gauge
    /// @param _amount The amount of the reward token to be withdrawn
    /// @dev Function recovers minOf(_amount, rewardsLeft)
    function recoverRewardsFromFarm(address _gAddr, uint256 _amount)
        external
        onlyOwner
    {
        IFarm(_gAddr).recoverRewardFunds(SPA, _amount);
    }

    /// @notice Update SPA token management in bulk
    /// @param _gAddrs Array of gauge Addresses.
    /// @param _newSPAManager New manager address.
    function transferSPAManagement(
        address[] calldata _gAddrs,
        address _newSPAManager
    ) external {
        for (uint8 i = 0; i < _gAddrs.length; i++) {
            IFarm(_gAddrs[i]).updateTokenManager(SPA, _newSPAManager);
        }
    }

    /// @notice Function to send rewards and update the reward rates for a gauge.
    /// @param _gAddr Address of the gauge
    function distributeReward(address _gAddr) external nonReentrant {
        _distributeReward(_gAddr);
    }

    /// @notice Function get the rewards for gauge, for current cycle.
    /// @param _gAddr Address of the gauge.
    /// @return Returns the pending amount to be distributed.
    function currentReward(address _gAddr) public view returns (uint256) {
        if (block.timestamp < nextRewardTime[_gAddr]) {
            return 0;
        }
        uint256 nextRwdTime = ((block.timestamp + WEEK) / WEEK) * WEEK;
        uint256 gaugeRelativeWt = IGaugeController(gaugeController)
            .gaugeRelativeWeight(_gAddr);
        uint256 rewardRate = (globalSPAEmission * gaugeRelativeWt) / MULTIPLIER;
        return rewardRate * (nextRwdTime - block.timestamp);
    }

    /// @notice Function to send rewards to a gauge for the cycle.
    /// @param _gAddr Address of the gauge.
    /// @dev if there is a gap in reward distribution, for multiple cycles,
    ///      only the latest cycle is considered for rewards.
    function _distributeReward(address _gAddr) private {
        require(distributionsOn, "Distributions are off");
        uint256 nextRwdTime = nextRewardTime[_gAddr];
        require(
            nextRwdTime == 0 || (block.timestamp > nextRwdTime),
            "Invalid distribution"
        );
        IFarm farm = IFarm(_gAddr);
        nextRwdTime = ((block.timestamp + WEEK) / WEEK) * WEEK;
        // Relative weights are always calculated based on the current cycle.
        uint256 gaugeRelativeWt = IGaugeController(gaugeController)
            .gaugeRelativeWeightWrite(_gAddr);
        uint256 rewards = (globalSPAEmission * gaugeRelativeWt) / MULTIPLIER;
        uint256 rewardRate = rewards / WEEK;

        // Transfers rewards for remaining time till next cycle!
        rewards = rewardRate * (nextRwdTime - block.timestamp);
        if (!farm.isPaused() && rewards > 0) {
            IERC20(SPA).safeTransfer(_gAddr, rewards);
            uint256[] memory rewardRates;
            if (farm.cooldownPeriod() == 0) {
                rewardRates[0] = rewardRate;
            } else {
                rewardRates[1] = (rewardRate * lockupFundSplit[_gAddr]) / PREC; // lockup-reward fund
                rewardRates[0] = rewardRate - rewardRates[1];
            }
            farm.setRewardRate(SPA, rewardRates);
            emit RewardsDistributed(_gAddr, rewards);
        }
        nextRewardTime[_gAddr] = nextRwdTime;
    }
}
