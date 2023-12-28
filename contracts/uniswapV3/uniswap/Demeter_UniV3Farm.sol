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

import {BaseUniV3Farm} from "../BaseUniV3Farm.sol";

contract Demeter_UniV3Farm is BaseUniV3Farm {
    // constants
    string public constant FARM_ID = "Demeter_UniV3_v4";

    // solhint-disable-next-line func-name-mixedcase
    function NFPM() public pure override returns (address) {
        return 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    }

    // solhint-disable-next-line func-name-mixedcase
    function UNIV3_FACTORY() public pure override returns (address) {
        return 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    }
}
