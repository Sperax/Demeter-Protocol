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

import {BaseUniV3Farm, RewardTokenData, UniswapPoolData} from "../BaseUniV3Farm.sol";

contract Demeter_SushiV3Farm is BaseUniV3Farm {
    // constants
    string public constant FARM_ID = "Demeter_SushiV3_v3";

    function NFPM() internal pure override returns (address) {
        return 0xF0cBce1942A68BEB3d1b73F0dd86C8DCc363eF49;
    }

    function UNIV3_FACTORY() internal pure override returns (address) {
        return 0x1af415a1EbA07a4986a52B6f2e7dE7003D82231e;
    }
}
