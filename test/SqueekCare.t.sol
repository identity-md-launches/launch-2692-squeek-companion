// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekCompanion} from "../src/SqueekCompanion.sol";
import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";

contract SqueekCareTest is CompanionTestBase {
    event CompanionPetted(uint256 indexed tokenId, address indexed holder, uint8 bond, uint256 nextPetAt);
    event MetadataUpdate(uint256 tokenId);

    function test_initialStateAndImmediateFirstPet() public {
        SqueekCompanion.Companion memory companion = nft.companionOf(1);
        assertEq(companion.bond, 0);
        assertEq(companion.nextPetAt, 0);
        assertEq(nft.stageOf(1), 0);
        assertEq(nft.MAX_BOND(), 30);
        assertEq(nft.PET_COOLDOWN(), 1 days);

        vm.expectEmit(true, true, false, true, address(nft));
        emit CompanionPetted(1, INITIAL_OWNER, 1, vm.getBlockTimestamp() + 1 days);
        vm.expectEmit(false, false, false, true, address(nft));
        emit MetadataUpdate(1);
        vm.prank(INITIAL_OWNER);
        nft.pet(1);

        companion = nft.companionOf(1);
        assertEq(companion.bond, 1);
        assertEq(companion.nextPetAt, vm.getBlockTimestamp() + 1 days);
        assertEq(nft.companionOf(2).bond, 0);
    }

    function test_firstPetWorksAtTimestampZero() public {
        vm.warp(0);
        vm.prank(INITIAL_OWNER);
        nft.pet(1);
        assertEq(nft.companionOf(1).bond, 1);
        assertEq(nft.companionOf(1).nextPetAt, 1 days);
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, 1, 1 days));
        nft.pet(1);
    }

    function test_onlyCurrentOwnerCanPet() public {
        _give(alice, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.NotTokenOwner.selector, bob, 1));
        nft.pet(1);
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.NotTokenOwner.selector, INITIAL_OWNER, 1));
        nft.pet(1);
        vm.prank(alice);
        nft.pet(1);
        assertEq(nft.companionOf(1).bond, 1);
    }

    function test_transferApprovalsDoNotGrantPetPermission() public {
        vm.startPrank(INITIAL_OWNER);
        nft.approve(alice, 1);
        nft.setApprovalForAll(operator, true);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.NotTokenOwner.selector, alice, 1));
        nft.pet(1);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.NotTokenOwner.selector, operator, 1));
        nft.pet(1);
        assertEq(nft.companionOf(1).bond, 0);
    }

    function test_duplicatePetInSameBlockRejectedWithoutStateChange() public {
        vm.startPrank(INITIAL_OWNER);
        nft.pet(1);
        uint256 nextPet = nft.companionOf(1).nextPetAt;
        string memory uri = nft.tokenURI(1);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, 1, nextPet));
        nft.pet(1);
        vm.stopPrank();
        assertEq(nft.companionOf(1).bond, 1);
        assertEq(nft.companionOf(1).nextPetAt, nextPet);
        assertEq(nft.tokenURI(1), uri);
    }

    function test_petRejectsOneSecondBeforeCooldownAndAcceptsExactBoundary() public {
        vm.prank(INITIAL_OWNER);
        nft.pet(1);
        uint256 nextPet = nft.companionOf(1).nextPetAt;
        vm.warp(nextPet - 1);
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, 1, nextPet));
        nft.pet(1);

        vm.warp(nextPet);
        vm.prank(INITIAL_OWNER);
        nft.pet(1);
        assertEq(nft.companionOf(1).bond, 2);
        assertEq(nft.companionOf(1).nextPetAt, nextPet + 1 days);
    }

    function testFuzz_cannotPetDuringCooldown(uint32 elapsed) public {
        elapsed = uint32(bound(elapsed, 0, 1 days - 1));
        uint256 start = vm.getBlockTimestamp();
        vm.prank(INITIAL_OWNER);
        nft.pet(1);
        vm.warp(start + elapsed);
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, 1, start + 1 days));
        nft.pet(1);
        assertEq(nft.companionOf(1).bond, 1);
    }

    function test_longAbsenceDoesNotDecayOrAccumulateMultiplePets() public {
        _petTo(1, 5);
        uint256 lastNextPet = nft.companionOf(1).nextPetAt;
        vm.warp(lastNextPet + 1000 days);
        assertEq(nft.companionOf(1).bond, 5);
        assertEq(nft.stageOf(1), 1);
        vm.prank(INITIAL_OWNER);
        nft.pet(1);
        assertEq(nft.companionOf(1).bond, 6);
        assertEq(nft.companionOf(1).nextPetAt, lastNextPet + 1001 days);
    }

    function test_progressAndCooldownPersistThroughTransfers() public {
        _petTo(1, 15);
        SqueekCompanion.Companion memory beforeTransfer = nft.companionOf(1);
        string memory uri = nft.tokenURI(1);
        _give(alice, 1);
        assertEq(nft.companionOf(1).bond, beforeTransfer.bond);
        assertEq(nft.companionOf(1).nextPetAt, beforeTransfer.nextPetAt);
        assertEq(nft.stageOf(1), 2);
        assertEq(nft.tokenURI(1), uri);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, 1, beforeTransfer.nextPetAt));
        nft.pet(1);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);
        vm.warp(beforeTransfer.nextPetAt);
        vm.prank(bob);
        nft.pet(1);
        assertEq(nft.companionOf(1).bond, 16);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.NotTokenOwner.selector, alice, 1));
        nft.pet(1);
    }

    function test_selfTransferDoesNotResetCooldown() public {
        _petTo(1, 1);
        uint256 nextPet = nft.companionOf(1).nextPetAt;
        vm.startPrank(INITIAL_OWNER);
        nft.transferFrom(INITIAL_OWNER, INITIAL_OWNER, 1);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, 1, nextPet));
        nft.pet(1);
        vm.stopPrank();
        assertEq(nft.companionOf(1).nextPetAt, nextPet);
    }

    function test_eachTokenHasIndependentCooldownAndBond() public {
        vm.startPrank(INITIAL_OWNER);
        nft.pet(1);
        nft.pet(2);
        nft.pet(999);
        vm.stopPrank();
        assertEq(nft.companionOf(1).bond, 1);
        assertEq(nft.companionOf(2).bond, 1);
        assertEq(nft.companionOf(999).bond, 1);
        assertEq(nft.companionOf(500).bond, 0);
        assertEq(nft.companionOf(500).nextPetAt, 0);
    }

    function test_stageThresholdsAndFinalCap() public {
        _petTo(1, 4);
        assertEq(nft.stageOf(1), 0);
        _petTo(1, 5);
        assertEq(nft.stageOf(1), 1);
        _petTo(1, 14);
        assertEq(nft.stageOf(1), 1);
        _petTo(1, 15);
        assertEq(nft.stageOf(1), 2);
        _petTo(1, 29);
        assertEq(nft.stageOf(1), 2);
        _petTo(1, 30);
        assertEq(nft.stageOf(1), 3);
        uint256 finalNextPet = nft.companionOf(1).nextPetAt;
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.FullyBonded.selector, 1));
        nft.pet(1);
        vm.warp(finalNextPet + 1000 days);
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.FullyBonded.selector, 1));
        nft.pet(1);
        assertEq(nft.companionOf(1).bond, 30);
        assertEq(nft.companionOf(1).nextPetAt, finalNextPet);
    }

    function test_transferCannotResetFinalCap() public {
        _petTo(1, 30);
        _give(alice, 1);
        vm.warp(vm.getBlockTimestamp() + 100 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekCompanion.FullyBonded.selector, 1));
        nft.pet(1);
        assertEq(nft.stageOf(1), 3);
    }

    function testFuzz_evolutionForEveryTokenAndBond(uint256 tokenId, uint8 targetBond) public {
        tokenId = bound(tokenId, 1, 999);
        targetBond = uint8(bound(targetBond, 0, 30));
        _give(alice, tokenId);
        uint256 start = vm.getBlockTimestamp();
        _petTo(tokenId, targetBond);
        assertEq(nft.companionOf(tokenId).bond, targetBond);
        uint8 expectedStage = targetBond < 5 ? 0 : targetBond < 15 ? 1 : targetBond < 30 ? 2 : 3;
        assertEq(nft.stageOf(tokenId), expectedStage);
        assertEq(nft.companionOf(tokenId).nextPetAt, targetBond == 0 ? 0 : start + uint256(targetBond) * 1 days);
        assertEq(nft.totalSupply(), 999);
    }
}
