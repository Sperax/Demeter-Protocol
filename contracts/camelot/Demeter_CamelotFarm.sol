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

import {INFTPoolFactory, INFTPool, INFTHandler} from "./interfaces/CamelotInterfaces.sol";
import "../BaseFarm.sol";

contract Demeter_CamelotFarm is BaseFarm, INFTHandler {
    // constants
    string public constant FARM_ID = "Demeter_Camelot_v1";
    address public constant NFTPoolFactory =
        0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d;

    // Camelot nft pool
    address public nftPool;

    event PoolRewardsCollected(
        address indexed recipient,
        uint256 indexed tokenId,
        uint256 grailAmt,
        uint256 xGrailAmt
    );

    /// @notice constructor
    /// @param _farmStartTime - time of farm start
    /// @param _cooldownPeriod - cooldown period for locked deposits in days
    /// @dev _cooldownPeriod = 0 Disables lockup functionality for the farm.
    /// @param _camelotPairPool - Camelot lp pool address
    /// @param _rwdTokenData - init data for reward tokens
    function initialize(
        uint256 _farmStartTime,
        uint256 _cooldownPeriod,
        address _camelotPairPool,
        RewardTokenData[] memory _rwdTokenData
    ) external initializer {
        // initialize uniswap related data
        nftPool = INFTPoolFactory(NFTPoolFactory).getPool(_camelotPairPool);
        require(nftPool != address(0), "Invalid camelot pool config");

        _setupFarm(_farmStartTime, _cooldownPeriod, _rwdTokenData);
    }

    /// @notice Function is called when user transfers the NFT to the contract.
    /// @param _from The address of the owner.
    /// @param _tokenId nft Id generated by camelot.
    /// @param _data The data should be the lockup flag (bool).
    function onERC721Received(
        address, // unused variable. not named
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        require(msg.sender == nftPool, "onERC721Received: incorrect nft");
        require(_data.length > 0, "onERC721Received: no data");
        bool lockup = abi.decode(_data, (bool));
        uint256 liquidity = _getLiquidity(_tokenId);
        // Execute common deposit function
        _deposit(_from, lockup, _tokenId, liquidity);
        return this.onERC721Received.selector;
    }

    /// @notice Function to lock a staked deposit
    /// @param _depositId The id of the deposit to be locked
    /// @dev _depositId is corresponding to the user's deposit
    function initiateCooldown(uint256 _depositId) external nonReentrant {
        _initiateCooldown(_depositId);
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param _depositId The id of the deposit to be withdrawn
    function withdraw(uint256 _depositId) external nonReentrant {
        address account = msg.sender;
        _isValidDeposit(account, _depositId);
        Deposit memory userDeposit = deposits[account][_depositId];

        _withdraw(msg.sender, _depositId, userDeposit);
        // Transfer the nft back to the user.
        INFTPool(nftPool).safeTransferFrom(
            address(this),
            account,
            userDeposit.tokenId
        );
    }

    /// @notice Claim uniswap pool fee for a deposit.
    /// @dev Only the deposit owner can claim the fee.
    /// @param _depositId Id of the deposit
    function claimPoolRewards(uint256 _depositId) external nonReentrant {
        _farmNotClosed();
        address account = msg.sender;
        _isValidDeposit(account, _depositId);
        Deposit memory userDeposit = deposits[account][_depositId];
        INFTPool(nftPool).harvestPositionTo(userDeposit.tokenId, account);
    }

    /// @notice callback function for harvestPosition().
    function onNFTHarvest(
        address,
        address _to,
        uint256 _tokenId,
        uint256 _grailAmount,
        uint256 _xGrailAmount
    ) external override returns (bool) {
        require(msg.sender == nftPool, "Not Allowed");
        emit PoolRewardsCollected(_to, _tokenId, _grailAmount, _xGrailAmount);
        return true;
    }

    /// @notice Get the accrued uniswap fee for a deposit.
    /// @return amount Grail rewards.
    function computePoolRewards(uint256 _tokenId)
        external
        view
        returns (uint256 amount)
    {
        // Validate token.
        amount = INFTPool(nftPool).pendingRewards(_tokenId);
        return amount;
    }

    /// @notice Validate the position for the pool and get Liquidity
    /// @param _tokenId The tokenId of the position
    /// @dev the position must adhere to the price ranges
    /// @dev Only allow specific pool token to be staked.
    function _getLiquidity(uint256 _tokenId) private view returns (uint256) {
        /// @dev Get the info of the required token
        (uint256 liquidity, , , , , , , ) = INFTPool(nftPool)
            .getStakingPosition(_tokenId);

        /// @dev Check if the token belongs to correct pool
        // @todo add any validation if required

        return uint256(liquidity);
    }
}
