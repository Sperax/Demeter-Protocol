// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {UniV3Farm} from "../../../../contracts/e721-farms/uniswapV3/UniV3Farm.sol";
import {UniV3FarmDeployer} from "../../../../contracts/e721-farms/uniswapV3/UniV3FarmDeployer.sol";
import {INFPM} from "../../../../contracts/e721-farms/uniswapV3/interfaces/IUniswapV3.sol";

// import tests
import "../UniV3Farm.t.sol";
import "../../../utils/UpgradeUtil.t.sol";

contract SushiV3FarmTest is FarmInheritTest, E721FarmInheritTest, UniV3FarmInheritTest, ExpirableFarmInheritTest {
    // Define variables
    string public constant FARM_NAME = "Demeter_SushiV3_v1";

    function setUp() public virtual override(FarmTest, UniV3FarmTest) {
        NFPM = SUSHISWAP_NFPM;
        UNIV3_FACTORY = SUSHISWAP_FACTORY;
        SWAP_ROUTER = SUSHISWAP_SWAP_ROUTER;
        FARM_ID = FARM_NAME;
        UniV3FarmTest.setUp();
    }
}
