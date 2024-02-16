// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {BaseUniV3Farm} from "../../../../contracts/e721-farms/uniswapV3/BaseUniV3Farm.sol";
import {Demeter_BaseUniV3FarmDeployer} from
    "../../../../contracts/e721-farms/uniswapV3/Demeter_BaseUniV3FarmDeployer.sol";
import {INFPM} from "../../../../contracts/e721-farms/uniswapV3/interfaces/IUniswapV3.sol";

// import tests
import "../BaseUniV3Farm.t.sol";

contract Demeter_UniV3FarmTest is
    BaseFarmInheritTest,
    BaseE721FarmInheritTest,
    BaseUniV3FarmInheritTest,
    ExpirableFarmInheritTest
{
    // Define variables
    string public FARM_NAME = "Demeter_UniV3_v4";

    function setUp() public virtual override(BaseUniV3FarmTest, BaseFarmTest) {
        NFPM = UNISWAP_V3_NFPM;
        UNIV3_FACTORY = UNISWAP_V3_FACTORY;
        SWAP_ROUTER = UNISWAP_V3_SWAP_ROUTER;
        FARM_ID = FARM_NAME;
        super.setUp();
    }
}
