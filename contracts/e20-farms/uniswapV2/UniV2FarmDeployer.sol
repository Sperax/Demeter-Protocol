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

import {FarmDeployer, SafeERC20, IERC20, IFarmRegistry} from "../../FarmDeployer.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RewardTokenData} from "../E20Farm.sol";
import {UniV2Farm} from "./UniV2Farm.sol";

/// @title Deployer for Uniswap V2 farm.
/// @author Sperax Foundation.
/// @notice This contract allows anyone to calculate fees, pay fees and create farms.
/// @dev It consults Uniswap V2 Factory to validate the pool.
contract UniV2FarmDeployer is FarmDeployer {
    using SafeERC20 for IERC20;

    // @dev the token Order is not important.
    struct PoolData {
        address tokenA;
        address tokenB;
    }

    // farmAdmin - Address to which ownership of farm is transferred to post deployment.
    // farmStartTime - Time after which the rewards start accruing for the deposits in the farm.
    // cooldownPeriod -  cooldown period for locked deposits (in days).
    //                   make cooldownPeriod = 0 for disabling lockup functionality of the farm.
    // camelotPoolData - data for camelot pool (tokenA, tokenB).
    // rewardTokenData - [(rewardTokenAddress, tknManagerAddress), ... ].
    struct FarmData {
        address farmAdmin;
        uint256 farmStartTime;
        uint256 cooldownPeriod;
        PoolData camelotPoolData;
        RewardTokenData[] rewardData;
    }

    address public immutable PROTOCOL_FACTORY;

    /// @notice Constructor of the contract.
    /// @param _farmRegistry Address of the Demeter Farm Registry.
    /// @param _farmId Id of the farm.
    /// @param _protocolFactory Address of UniswapV2 factory.
    constructor(address _farmRegistry, string memory _farmId, address _protocolFactory)
        FarmDeployer(_farmRegistry, _farmId)
    {
        _validateNonZeroAddr(_protocolFactory);
        PROTOCOL_FACTORY = _protocolFactory;
        farmImplementation = address(new UniV2Farm());
    }

    /// @notice Deploys a new UniswapV3 farm.
    /// @param _data data for deployment.
    /// @return address of the deployed farm.
    /// @dev The caller of this function should approve feeAmount to this contract before calling this function.
    function createFarm(FarmData memory _data) external nonReentrant returns (address) {
        _validateNonZeroAddr(_data.farmAdmin);
        UniV2Farm farmInstance = UniV2Farm(Clones.clone(farmImplementation));

        address pairPool = validatePool(_data.camelotPoolData.tokenA, _data.camelotPoolData.tokenB);

        farmInstance.initialize({
            _farmId: farmId,
            _farmStartTime: _data.farmStartTime,
            _cooldownPeriod: _data.cooldownPeriod,
            _farmRegistry: FARM_REGISTRY,
            _farmToken: pairPool,
            _rwdTokenData: _data.rewardData
        });
        farmInstance.transferOwnership(_data.farmAdmin);
        address farm = address(farmInstance);
        // Calculate and collect fee if required.
        _collectFee();
        IFarmRegistry(FARM_REGISTRY).registerFarm(farm, msg.sender);
        emit FarmCreated(farm, msg.sender, _data.farmAdmin);
        return farm;
    }

    /// @notice Validates the pool.
    /// @param _tokenA Address of token A.
    /// @param _tokenB Address of token B.
    /// @return pool Address.
    function validatePool(address _tokenA, address _tokenB) public view returns (address pool) {
        pool = IUniswapV2Factory(PROTOCOL_FACTORY).getPair(_tokenA, _tokenB);
        _validateNonZeroAddr(pool);
        return pool;
    }
}
