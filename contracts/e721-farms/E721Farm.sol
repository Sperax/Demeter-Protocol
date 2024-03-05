// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

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

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Farm} from "../Farm.sol";

abstract contract E721Farm is Farm, IERC721Receiver {
    // Could be NFPM for Uniswap or nft pool for Camelot
    address public nftContract;

    mapping(uint256 => uint256) public depositToTokenId;

    error UnauthorisedNFTContract();
    error NoData();

    /// @notice Function is called when user transfers the NFT to this farm.
    /// @param _from The address of the owner.
    /// @param _tokenId nft Id generated by other protocol (e.g. Camelot or Uniswap).
    /// @param _data The data should be the lockup flag (bool).
    function onERC721Received(
        address, // unused variable. not named
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        if (msg.sender != nftContract) {
            revert UnauthorisedNFTContract();
        }
        if (_data.length == 0) {
            revert NoData();
        }
        uint256 liquidity = _getLiquidity(_tokenId);
        // Execute common deposit function
        uint256 depositId = _deposit(_from, abi.decode(_data, (bool)), liquidity);
        depositToTokenId[depositId] = _tokenId;
        return this.onERC721Received.selector;
    }

    /// @notice Function to withdraw a deposit from the farm.
    /// @param _depositId The id of the deposit to be withdrawn
    function withdraw(uint256 _depositId) external override nonReentrant {
        _withdraw(msg.sender, _depositId);
        // Transfer the nft back to the user.
        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, depositToTokenId[_depositId]);
        delete depositToTokenId[_depositId];
    }

    /// @notice A function to get the liquidity. Must be defined by the farm.
    function _getLiquidity(uint256 _tokenId) internal view virtual returns (uint256);
}