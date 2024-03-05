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
    address public constant USDS_VAULT = 0x6Bbc476Ee35CBA9e9c3A59fc5b10d7a0BC6f74Ca;

    // Farm constants
    // @note Add only specific farm related params, try to group them together
    // Balancer
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    // UniswapUtils
    address public constant UNISWAP_UTILS = 0xd2Aa19D3B7f8cdb1ea5B782c5647542055af415e;
    // NonfungiblePositionManagerUtils
    address constant NONFUNGIBLE_POSITION_MANAGER_UTILS = 0x7A7526d127CEF9c3b315B466685AFA6aF74275fb;

    // Sushiswap
    address public constant SUSHISWAP_FACTORY = 0x1af415a1EbA07a4986a52B6f2e7dE7003D82231e;
    address public constant SUSHISWAP_NFPM = 0xF0cBce1942A68BEB3d1b73F0dd86C8DCc363eF49;
    address public constant SUSHISWAP_SWAP_ROUTER = 0x8A21F6768C1f8075791D08546Dadf6daA0bE820c;
    // Uniswap
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant UNISWAP_V3_NFPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant UNISWAP_V3_SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    // Camelot
    address public constant NFT_POOL_FACTORY = 0x6dB1EF0dF42e30acF139A70C1Ed0B7E6c51dBf6d;
    address public constant CAMELOT_FACTORY = 0x6EcCab422D763aC031210895C81787E87B43A652;
    address public constant LP_TOKEN = 0x01efEd58B534d7a7464359A6F8d14D986125816B;
    address public constant POSITION_HELPER = 0xe458018Ad4283C90fB7F5460e24C4016F81b8175;
    address public constant ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;
    // Camelot V3
    address public constant CAMELOT_V3_FACTORY = 0x1a3c9B1d2F0529D97f2afC5136Cc23e58f1FD35B;
    address public constant CAMELOT_V3_NFPM = 0x00c7f3082833e796A5b3e4Bd59f6642FF44DCD15;
    address public constant CAMELOT_V3_SWAP_ROUTER = 0x1F721E2E82F6676FCE4eA07A5958cF098D339e18;
    address public constant CAMELOT_V3_UTILS = address(1); // TODO -> need to update this address.
    address public constant CAMELOT_V3_NONFUNGIBLE_POSITION_MANAGER_UTILS = 0xaB39C3d042BA31978087a4b946baBc8C80d868a4;

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
        FARM_REGISTRY = 0xC4fb09E0CD212367642974F6bA81D8e23780A659;
    }

    function FEE_TOKEN() public pure override returns (address) {
        return USDS;
    }

    function NETWORK_ID() public pure override returns (string memory) {
        return "Arbitrum";
    }
}
