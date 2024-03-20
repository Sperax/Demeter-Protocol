// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {UniV3Farm} from "../../../../contracts/e721-farms/uniswapV3/UniV3Farm.sol";
import {UniV3FarmDeployer} from "../../../../contracts/e721-farms/uniswapV3/UniV3FarmDeployer.sol";
import {INFPM} from "../../../../contracts/e721-farms/uniswapV3/interfaces/IUniswapV3.sol";

// import tests
import "../UniV3Farm.t.sol";

contract UniswapV3FarmTest is FarmInheritTest, E721FarmInheritTest, UniV3FarmInheritTest, ExpirableFarmInheritTest {
    // Define variables
    string public FARM_NAME = "Demeter_UniV3_v4";

    function setUp() public virtual override(UniV3FarmTest, FarmTest) {
        NFPM = UNISWAP_V3_NFPM;
        UNIV3_FACTORY = UNISWAP_V3_FACTORY;
        SWAP_ROUTER = UNISWAP_V3_SWAP_ROUTER;
        FARM_ID = FARM_NAME;
        super.setUp();
    }
}
