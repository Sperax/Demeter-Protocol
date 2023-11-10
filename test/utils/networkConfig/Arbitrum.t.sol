// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BaseSetup} from "../BaseSetup.t.sol";
import {INetworkConfig} from "./INetworkConfig.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IVault {
    function mintBySpecifyingCollateralAmt(
        address _collateral,
        uint256 _collateralAmt,
        uint256 _minUSDSAmt,
        uint256 _maxSPAburnt,
        uint256 _deadline
    ) external;
}

abstract contract Arbitrum is BaseSetup, INetworkConfig {
    // Tokens
    address public constant SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;
    address public constant USDS = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
    address public constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    // Demeter constants
    // @note Add only demeter related constants and configurations
    address public constant SPA_REWARD_MANAGER = 0x432c3BcdF5E26Ec010dF9C1ddf8603bbe261c188;
    address public constant USDS_VAULT = 0xF783DD830A4650D2A8594423F123250652340E3f;

    // Farm constants
    // @note Add only specific farm related params, try to group them together
    // Balancer
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    function fundFeeToken() public useKnownActor(owner) {
        uint256 amt = 1e22;
        deal(USDCe, currentActor, amt);
        IERC20(USDCe).approve(USDS_VAULT, amt);
        IVault(USDS_VAULT).mintBySpecifyingCollateralAmt(USDCe, amt, 0, 0, block.timestamp + 1200);
    }

    function setForkNetwork() public override {
        uint256 forkBlock = vm.envUint("FORK_BLOCK");
        string memory arbRpcUrl = vm.envString("ARB_URL");
        forkCheck = vm.createFork(arbRpcUrl);
        vm.selectFork(forkCheck);
        if (forkBlock != 0) vm.rollFork(forkBlock);
    }

    function setUp() public virtual override {
        super.setUp();
        setForkNetwork();

        fundFeeToken();

        // ** Setup global addresses ** //
        // Demeter addresses
        PROXY_OWNER = 0x6d5240f086637fb408c7F727010A10cf57D51B62;
        PROXY_ADMIN = 0x3E49925A79CbFb68BAa5bc9DFb4f7D955D1ddF25;
        DEMETER_FACTORY = 0xC4fb09E0CD212367642974F6bA81D8e23780A659;
    }

    function FEE_TOKEN() public pure override returns (address) {
        return USDS;
    }

    function NETWORK_ID() public pure override returns (string memory) {
        return "Arbitrum";
    }
}