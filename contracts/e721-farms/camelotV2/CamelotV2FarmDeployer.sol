// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@***@@@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@(****@@@@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@((******@@@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@(((*******@@@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@((((********@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@(((((********@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@(((((((********@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@@@(((((((/*******@@@@@@@ //
// @@@@@@@@@@&*****@@@@@@@@@@(((((((*******@@@@@ //
// @@@@@@***************@@@@@@@(((((((/*****@@@@ //
// @@@@********************@@@@@@@(((((((****@@@ //
// @@@************************@@@@@@(/((((***@@@ //
// @@@**************@@@@@@@@@***@@@@@@(((((**@@@ //
// @@@**************@@@@@@@@*****@@@@@@*((((*@@@ //
// @@@**************@@@@@@@@@@@@@@@@@@@**(((@@@@ //
// @@@@***************@@@@@@@@@@@@@@@@@**((@@@@@ //
// @@@@@****************@@@@@@@@@@@@@****(@@@@@@ //
// @@@@@@@*****************************/@@@@@@@@ //
// @@@@@@@@@@************************@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@***************@@@@@@@@@@@@@@@ //
// @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ //

import {FarmDeployer, IFarmRegistry} from "../../FarmDeployer.sol";
import {CamelotV2Farm, RewardTokenData} from "./CamelotV2Farm.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ICamelotV2Factory} from "./interfaces/ICamelotV2.sol";

/// @title Deployer for Camelot V2 farm.
/// @author Sperax Foundation.
/// @notice This contract allows anyone to calculate fees, pay fees and create farms.
/// @dev It consults Camelot V2 factory to validate the pool.
contract CamelotV2FarmDeployer is FarmDeployer {
    // @dev the token Order is not important.
    struct CamelotPoolData {
        address tokenA;
        address tokenB;
    }

    // farmAdmin - Address to which ownership of farm is transferred to, post deployment.
    // farmStartTime - Time after which the rewards start accruing for the deposits in the farm.
    // cooldownPeriod -  cooldown period for locked deposits (in days).
    //                   make cooldownPeriod = 0 for disabling lockup functionality of the farm.
    // lpTokenData - data for camelot pool (tokenA, tokenB).
    // rewardTokenData - An array containing pairs of reward token addresses and their corresponding token manager addresses.
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        CamelotPoolData camelotPoolData;
        RewardTokenData[] rewardData;
    }

    address public immutable PROTOCOL_FACTORY;
    address public immutable ROUTER;
    address public immutable NFT_POOL_FACTORY;

    /// @notice Constructor of the contract.
    /// @param _farmRegistry Address of the Demeter Farm Registry.
    /// @param _farmId Id of the farm.
    /// @param _protocolFactory Address of Camelot factory.
    /// @param _router Address of Camelot router.
    /// @param _nftPoolFactory Address of Camelot NFT pool factory.
    constructor(
        address _farmRegistry,
        string memory _farmId,
        address _protocolFactory,
        address _router,
        address _nftPoolFactory
    ) FarmDeployer(_farmRegistry, _farmId) {
        _validateNonZeroAddr(_protocolFactory);
        _validateNonZeroAddr(_nftPoolFactory);

        PROTOCOL_FACTORY = _protocolFactory;
        ROUTER = _router;
        NFT_POOL_FACTORY = _nftPoolFactory;
        farmImplementation = address(new CamelotV2Farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    /// @return address of the deployed farm.
    /// @dev The caller of this function should approve feeAmount to this contract before calling this function.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _validateNonZeroAddr(_data.farmAdmin);
        CamelotV2Farm farmInstance = CamelotV2Farm(Clones.clone(farmImplementation));

        address pairPool = validatePool(_data.camelotPoolData.tokenA, _data.camelotPoolData.tokenB);

        farmInstance.initialize({
            _farmId: farmId,
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _farmRegistry: FARM_REGISTRY,
            _camelotPairPool: pairPool,
            _rwdTokenData: _data.rewardData,
            _router: ROUTER,
            _nftPoolFactory: NFT_POOL_FACTORY
        });
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required.
        _collectFee();
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        IFarmRegistry(FARM_REGISTRY).registerFarm(farm, msg.sender);
        return farm;
    }

    /// @notice Validates the pool.
    /// @param _tokenA Address of token A.
    /// @param _tokenB Address of token B.
    /// @return pool Address.
    function validatePool(address _tokenA, address _tokenB) public view returns (address pool) {
        pool = ICamelotV2Factory(PROTOCOL_FACTORY).getPair(_tokenA, _tokenB);
        _validateNonZeroAddr(pool);
        return pool;
    }
}
