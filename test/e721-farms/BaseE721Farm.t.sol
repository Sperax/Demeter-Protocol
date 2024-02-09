// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {BaseFarmTest} from "../BaseFarm.t.sol";
import {Deposit} from "../../contracts/interfaces/DataTypes.sol";
import {BaseUniV3Farm} from "../../../contracts/e721-farms/uniswapV3/BaseUniV3Farm.sol";
import {BaseE721Farm} from "../../../contracts/e721-farms/BaseE721Farm.sol";

abstract contract BaseE721FarmTest is BaseFarmTest {
    function createPosition(address from) public virtual returns (uint256 tokenId, address nftContract);
    function getLiquidity(uint256 tokenId) public virtual returns (uint256 liquidity);
}

abstract contract NFTDepositTest is BaseE721FarmTest {
    function test_RevertWhen_UnauthorisedNFTContract() public {
        vm.expectRevert(abi.encodeWithSelector(BaseE721Farm.UnauthorisedNFTContract.selector));
        BaseUniV3Farm(lockupFarm).onERC721Received(address(0), address(0), 0, "");
    }

    function test_RevertWhen_NoData() public useKnownActor(user) {
        (uint256 tokenId, address nftContract) = createPosition(user);
        IERC721(nftContract).safeTransferFrom(user, lockupFarm, tokenId, "");
        vm.expectRevert(abi.encodeWithSelector(BaseE721Farm.NoData.selector));
        BaseUniV3Farm(lockupFarm).onERC721Received(address(0), address(0), 0, "");
    }

    function test_onERC721Received() public useKnownActor(user) {
        (uint256 tokenId, address nftContract) = createPosition(user);
        IERC721(nftContract).safeTransferFrom(user, lockupFarm, tokenId, abi.encode(true));
        uint256 depositId = BaseUniV3Farm(lockupFarm).totalDeposits();
        Deposit memory userDeposit = BaseUniV3Farm(lockupFarm).getDepositInfo(depositId);
        assertEq(userDeposit.depositor, user);
        assertEq(userDeposit.liquidity, getLiquidity(tokenId));
        assertEq(BaseUniV3Farm(lockupFarm).depositToTokenId(depositId), tokenId);
    }
}
