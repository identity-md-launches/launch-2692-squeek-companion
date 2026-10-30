// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekCompanion} from "../../src/SqueekCompanion.sol";

abstract contract CompanionTestBase is Test {
    SqueekCompanion internal nft;
    address internal constant INITIAL_OWNER = address(bytes20(hex"3c7838665ff8215c95500e1a6306e19e146674a0"));
    address internal alice;
    address internal bob;
    address internal operator;

    function setUp() public virtual {
        vm.chainId(11_155_111);
        vm.warp(1_800_000_000);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        operator = makeAddr("operator");
        nft = new SqueekCompanion(INITIAL_OWNER);
    }

    function _give(address to, uint256 tokenId) internal {
        vm.prank(INITIAL_OWNER);
        nft.transferFrom(INITIAL_OWNER, to, tokenId);
    }

    function _petTo(uint256 tokenId, uint8 targetBond) internal {
        address holder = nft.ownerOf(tokenId);
        while (nft.companionOf(tokenId).bond < targetBond) {
            uint256 next = nft.companionOf(tokenId).nextPetAt;
            if (next > vm.getBlockTimestamp()) vm.warp(next);
            vm.prank(holder);
            nft.pet(tokenId);
        }
    }
}
