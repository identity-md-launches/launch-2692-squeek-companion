// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekCompanion} from "src/SqueekCompanion.sol";
import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";

/// forge-config: default.fuzz.runs = 1000
contract SqueekBoundaryPropertiesTest is CompanionTestBase {
    function test_largeIdsCannotAliasConsecutiveTokensBeforeOrAfterTransfer() public {
        uint256[10] memory invalidIds = [
            uint256(0),
            1000,
            type(uint96).max,
            uint256(1) << 96,
            (uint256(1) << 96) + 1,
            (uint256(1) << 96) + 999,
            type(uint128).max,
            (uint256(1) << 128) + 1,
            (uint256(1) << 128) + 999,
            type(uint256).max
        ];
        for (uint256 pass; pass < 2; ++pass) {
            for (uint256 i; i < invalidIds.length; ++i) {
                _assertMissingEverywhere(invalidIds[i]);
            }
            if (pass == 0) {
                _give(alice, 1);
                _give(bob, 999);
            }
        }
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(999), bob);
        assertEq(nft.balanceOf(INITIAL_OWNER), 997);
        assertEq(nft.totalSupply(), 999);
    }

    function test_entireInventoryCanLeaveAndReturnWithoutResettingProgress() public {
        _petTo(1, 5);
        _petTo(256, 15);
        _petTo(999, 30);
        uint256[3] memory caredIds = [uint256(1), 256, 999];
        SqueekCompanion.Companion[3] memory beforeCare;
        bytes32[3] memory beforeURI;
        for (uint256 i; i < 3; ++i) {
            beforeCare[i] = nft.companionOf(caredIds[i]);
            beforeURI[i] = keccak256(bytes(nft.tokenURI(caredIds[i])));
        }
        vm.prank(INITIAL_OWNER);
        nft.setApprovalForAll(operator, true);
        // Separate external calls model individual holder distribution transactions.
        for (uint256 id = 1; id <= 999; ++id) {
            vm.prank(operator);
            nft.safeTransferFrom(INITIAL_OWNER, alice, id);
            assertEq(nft.ownerOf(id), alice);
        }
        assertEq(nft.balanceOf(INITIAL_OWNER), 0);
        assertEq(nft.balanceOf(alice), 999);
        assertEq(nft.totalSupply(), 999);

        vm.prank(alice);
        nft.setApprovalForAll(bob, true);
        for (uint256 id = 999; id > 0; --id) {
            vm.prank(bob);
            nft.safeTransferFrom(alice, INITIAL_OWNER, id, hex"ff");
            assertEq(nft.ownerOf(id), INITIAL_OWNER);
            assertEq(nft.getApproved(id), address(0));
        }
        assertEq(nft.balanceOf(INITIAL_OWNER), 999);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 0);
        assertEq(nft.balanceOf(operator), 0);
        assertEq(nft.totalSupply(), 999);
        for (uint256 i; i < 3; ++i) {
            SqueekCompanion.Companion memory afterCare = nft.companionOf(caredIds[i]);
            assertEq(afterCare.bond, beforeCare[i].bond);
            assertEq(afterCare.nextPetAt, beforeCare[i].nextPetAt);
            assertEq(keccak256(bytes(nft.tokenURI(caredIds[i]))), beforeURI[i]);
        }
    }

    function testFuzz_latePetStartsANewRollingCooldown(uint256 id, uint64 start, uint32 delay) public {
        id = bound(id, 1, 999);
        delay = uint32(bound(delay, 1, 365 days));
        vm.warp(start);
        vm.prank(INITIAL_OWNER);
        nft.pet(id);
        uint256 firstDeadline = uint256(start) + 1 days;
        assertEq(nft.companionOf(id).nextPetAt, firstDeadline);
        vm.warp(firstDeadline + delay);
        _give(alice, id);
        vm.prank(alice);
        nft.pet(id);
        uint256 secondDeadline = firstDeadline + delay + 1 days;
        assertEq(nft.companionOf(id).bond, 2, "missed time does not accrue additional pets");
        assertEq(nft.companionOf(id).nextPetAt, secondDeadline, "cooldown must start at actual pet time");
        vm.warp(secondDeadline - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, id, secondDeadline));
        nft.pet(id);
        vm.warp(secondDeadline);
        vm.prank(alice);
        nft.pet(id);
        assertEq(nft.companionOf(id).bond, 3);
        assertEq(nft.companionOf(id).nextPetAt, secondDeadline + 1 days);
    }

    function test_cooldownDoesNotTruncateAtTimestampTypeBoundaries() public {
        uint256[3] memory starts = [uint256(0), uint256(type(uint32).max), uint256(type(uint64).max)];
        for (uint256 i; i < starts.length; ++i) {
            uint256 id = i + 1;
            vm.warp(starts[i]);
            vm.prank(INITIAL_OWNER);
            nft.pet(id);
            uint256 deadline = starts[i] + 1 days;
            assertEq(nft.companionOf(id).nextPetAt, deadline);
            vm.warp(deadline - 1);
            vm.prank(INITIAL_OWNER);
            vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, id, deadline));
            nft.pet(id);
            vm.warp(deadline);
            vm.prank(INITIAL_OWNER);
            nft.pet(id);
            assertEq(nft.companionOf(id).bond, 2);
            assertEq(nft.companionOf(id).nextPetAt, deadline + 1 days);
        }
    }

    function testFuzz_valueCannotBuyCareAuthorityOrTransfers(uint128 value) public {
        _assertPaymentsRejected(bound(value, 1, type(uint128).max));
    }

    function test_oneWeiAndMaximumUint128PaymentsRejected() public {
        _assertPaymentsRejected(1);
        _assertPaymentsRejected(type(uint128).max);
    }

    function _assertMissingEverywhere(uint256 id) private {
        bytes[] memory calls = new bytes[](10);
        calls[0] = abi.encodeCall(nft.ownerOf, (id));
        calls[1] = abi.encodeCall(nft.getApproved, (id));
        calls[2] = abi.encodeCall(nft.companionOf, (id));
        calls[3] = abi.encodeCall(nft.stageOf, (id));
        calls[4] = abi.encodeCall(nft.tokenURI, (id));
        calls[5] = abi.encodeCall(nft.pet, (id));
        calls[6] = abi.encodeCall(nft.approve, (alice, id));
        calls[7] = abi.encodeCall(nft.transferFrom, (INITIAL_OWNER, alice, id));
        calls[8] = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", INITIAL_OWNER, alice, id);
        calls[9] =
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", INITIAL_OWNER, alice, id, "");
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(INITIAL_OWNER);
            (bool ok, bytes memory reason) = address(nft).call(calls[i]);
            assertFalse(ok, "nonexistent token accepted");
            assertEq(reason, abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
        }
    }

    function _assertPaymentsRejected(uint256 value) private {
        bytes[] memory calls = new bytes[](8);
        calls[0] = "";
        calls[1] = hex"ffffffff";
        calls[2] = abi.encodeCall(nft.pet, (1));
        calls[3] = abi.encodeCall(nft.approve, (alice, 1));
        calls[4] = abi.encodeCall(nft.setApprovalForAll, (operator, true));
        calls[5] = abi.encodeCall(nft.transferFrom, (INITIAL_OWNER, alice, 1));
        calls[6] = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", INITIAL_OWNER, alice, 1);
        calls[7] =
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", INITIAL_OWNER, alice, 1, "");
        vm.deal(INITIAL_OWNER, value);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(INITIAL_OWNER);
            (bool ok,) = address(nft).call{value: value}(calls[i]);
            assertFalse(ok, "collection unexpectedly accepted payment");
            assertEq(INITIAL_OWNER.balance, value, "failed call retained payment");
            assertEq(address(nft).balance, 0);
            assertEq(nft.ownerOf(1), INITIAL_OWNER);
            assertEq(nft.balanceOf(INITIAL_OWNER), 999);
            assertEq(nft.balanceOf(alice), 0);
            assertEq(nft.getApproved(1), address(0));
            assertFalse(nft.isApprovedForAll(INITIAL_OWNER, operator));
            assertEq(nft.companionOf(1).bond, 0);
            assertEq(nft.companionOf(1).nextPetAt, 0);
        }
    }
}
