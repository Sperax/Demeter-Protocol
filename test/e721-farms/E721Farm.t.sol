// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {FarmTest, IFarm} from "../Farm.t.sol";
import {Deposit} from "../../contracts/interfaces/DataTypes.sol";
import {UniV3Farm, E721Farm} from "../../contracts/e721-farms/uniswapV3/UniV3Farm.sol";

abstract contract E721FarmTest is FarmTest {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function createPosition(address from) public virtual returns (uint256 tokenId, address nftContract);
    function getLiquidity(uint256 tokenId) public view virtual returns (uint256 liquidity);
    function nfpm() internal view virtual returns (address);
}

abstract contract NFTDepositTest is E721FarmTest {
    function test_NFTDeposit_RevertWhen_UnauthorisedNFTContract() public {
        vm.expectRevert(abi.encodeWithSelector(E721Farm.UnauthorisedNFTContract.selector));
        E721Farm(lockupFarm).onERC721Received(address(0), address(0), 0, "");
    }

    function test_NFTDeposit_RevertWhen_NoData() public useKnownActor(user) {
        (uint256 tokenId, address nftContract) = createPosition(user);
        vm.expectRevert(abi.encodeWithSelector(E721Farm.NoData.selector));
        IERC721(nftContract).safeTransferFrom(user, lockupFarm, tokenId, "");
    }

    function test_NFTDeposit() public useKnownActor(user) {
        for (uint8 j; j < 2; ++j) {
            bool lockup = j == 0 ? true : false;
            address farm = lockup ? lockupFarm : nonLockupFarm;
            (uint256 tokenId, address nftContract) = createPosition(user);
            uint256 liquidity = getLiquidity(tokenId);

            if (!lockup) {
                vm.expectEmit(address(farm));
                emit IFarm.PoolSubscribed(IFarm(farm).totalDeposits() + 1, COMMON_FUND_ID);
            } else {
                vm.expectEmit(address(farm));
                emit IFarm.PoolSubscribed(IFarm(farm).totalDeposits() + 1, COMMON_FUND_ID);
                vm.expectEmit(address(farm));
                emit IFarm.PoolSubscribed(IFarm(farm).totalDeposits() + 1, LOCKUP_FUND_ID);
            }
            vm.expectEmit(address(farm));
            emit IFarm.Deposited(IFarm(farm).totalDeposits() + 1, currentActor, lockup, liquidity);
            IERC721(nftContract).safeTransferFrom(currentActor, farm, tokenId, abi.encode(lockup));
            uint256 depositId = E721Farm(farm).totalDeposits();
            Deposit memory userDeposit = E721Farm(farm).getDepositInfo(depositId);
            assertEq(userDeposit.depositor, user);
            assertEq(userDeposit.liquidity, liquidity);
            assertEq(E721Farm(farm).depositToTokenId(depositId), tokenId);
        }
    }
}

abstract contract WithdrawAdditionalTest is E721FarmTest {
    function test_Withdraw_RevertWhen_DepositDoesNotExist_during_withdraw() public useKnownActor(user) {
        vm.expectRevert(abi.encodeWithSelector(IFarm.DepositDoesNotExist.selector));
        E721Farm(lockupFarm).withdraw(0);
    }

    function test_Withdraw() public depositSetup(lockupFarm, true) useKnownActor(user) {
        uint256 depositId = 1;
        IFarm(lockupFarm).initiateCooldown(depositId);
        skip((COOLDOWN_PERIOD_DAYS * 1 days) + 100); //100 seconds after the end of CoolDown Period
        vm.expectEmit(nfpm());
        emit Transfer(lockupFarm, currentActor, E721Farm(lockupFarm).depositToTokenId(depositId));
        E721Farm(lockupFarm).withdraw(depositId);
    }

    function test_Withdraw_paused() public depositSetup(lockupFarm, true) {
        uint256 depositId = 1;
        vm.startPrank(owner);
        IFarm(lockupFarm).farmPauseSwitch(true);
        vm.startPrank(user);
        vm.expectEmit(nfpm());
        emit Transfer(lockupFarm, currentActor, E721Farm(lockupFarm).depositToTokenId(depositId));
        E721Farm(lockupFarm).withdraw(depositId);
    }

    function test_Withdraw_closed() public depositSetup(lockupFarm, true) {
        uint256 depositId = 1;
        vm.startPrank(owner);
        IFarm(lockupFarm).closeFarm();
        vm.startPrank(user);
        vm.expectEmit(nfpm());
        emit Transfer(lockupFarm, currentActor, E721Farm(lockupFarm).depositToTokenId(depositId));
        E721Farm(lockupFarm).withdraw(depositId);
    }

    function test_Withdraw_closedAndExpired() public depositSetup(lockupFarm, true) {
        uint256 depositId = 1;
        vm.startPrank(owner);
        IFarm(lockupFarm).closeFarm();
        vm.warp(block.timestamp + 1);
        vm.startPrank(user);
        vm.expectEmit(nfpm());
        emit Transfer(lockupFarm, currentActor, E721Farm(lockupFarm).depositToTokenId(depositId));
        E721Farm(lockupFarm).withdraw(depositId);
    }
}

abstract contract E721FarmInheritTest is NFTDepositTest, WithdrawAdditionalTest {}
