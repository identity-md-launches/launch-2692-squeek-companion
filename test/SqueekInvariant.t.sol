// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekCompanion} from "../src/SqueekCompanion.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";

/// @dev Independent model of ownership, balances and care, driven through the real external API.
contract CompanionHandler is Test {
    SqueekCompanion public immutable nft;
    address[4] public actors;
    uint256[12] public tokenIds = [uint256(1), 2, 3, 497, 498, 499, 500, 501, 502, 997, 998, 999];
    uint256[12] public modelOwnerIndex;
    uint8[12] public modelBond;
    uint256[12] public modelNextPet;
    uint256[4] public modelBalance = [uint256(999), 0, 0, 0];
    uint256 public successfulPets;
    uint256 public successfulTransfers;
    uint256 public rejectedActions;

    constructor(SqueekCompanion nft_, address[4] memory actors_) {
        nft = nft_;
        actors = actors_;
    }

    function move(uint256 tokenSeed, uint256 recipientSeed) public {
        uint256 index = tokenSeed % 12;
        uint256 from = modelOwnerIndex[index];
        uint256 to = recipientSeed % 4;
        vm.prank(actors[from]);
        nft.transferFrom(actors[from], actors[to], tokenIds[index]);
        _recordTransfer(index, from, to);
    }

    function approvedMove(uint256 tokenSeed, uint256 recipientSeed, bool operatorApproval) public {
        uint256 index = tokenSeed % 12;
        uint256 from = modelOwnerIndex[index];
        uint256 to = recipientSeed % 4;
        address approved = actors[(from + 1) % 4];
        vm.prank(actors[from]);
        if (operatorApproval) nft.setApprovalForAll(approved, true);
        else nft.approve(approved, tokenIds[index]);
        vm.prank(approved);
        nft.transferFrom(actors[from], actors[to], tokenIds[index]);
        if (operatorApproval) {
            vm.prank(actors[from]);
            nft.setApprovalForAll(approved, false);
        }
        _recordTransfer(index, from, to);
    }

    function pet(uint256 tokenSeed) public {
        uint256 index = tokenSeed % 12;
        uint256 tokenId = tokenIds[index];
        address holder = actors[modelOwnerIndex[index]];
        vm.prank(holder);
        (bool success, bytes memory reason) = address(nft).call(abi.encodeCall(nft.pet, (tokenId)));
        if (modelBond[index] == 30) {
            assertFalse(success);
            assertEq(reason, abi.encodeWithSelector(SqueekCompanion.FullyBonded.selector, tokenId));
            ++rejectedActions;
        } else if (vm.getBlockTimestamp() < modelNextPet[index]) {
            assertFalse(success);
            assertEq(reason, abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, tokenId, modelNextPet[index]));
            ++rejectedActions;
        } else {
            assertTrue(success);
            ++modelBond[index];
            modelNextPet[index] = vm.getBlockTimestamp() + 1 days;
            ++successfulPets;
        }
    }

    function unauthorizedPet(uint256 tokenSeed) public {
        uint256 index = tokenSeed % 12;
        address stranger = actors[(modelOwnerIndex[index] + 1) % 4];
        vm.prank(stranger);
        (bool success, bytes memory reason) = address(nft).call(abi.encodeCall(nft.pet, (tokenIds[index])));
        assertFalse(success);
        assertEq(reason, abi.encodeWithSelector(SqueekCompanion.NotTokenOwner.selector, stranger, tokenIds[index]));
        ++rejectedActions;
    }

    function unauthorizedTransfer(uint256 tokenSeed) public {
        uint256 index = tokenSeed % 12;
        address holder = actors[modelOwnerIndex[index]];
        address stranger = actors[(modelOwnerIndex[index] + 1) % 4];
        vm.prank(stranger);
        (bool success, bytes memory reason) =
            address(nft).call(abi.encodeCall(nft.transferFrom, (holder, stranger, tokenIds[index])));
        assertFalse(success);
        assertEq(
            reason, abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, stranger, tokenIds[index])
        );
        ++rejectedActions;
    }

    function advanceTime(uint32 elapsed) public {
        vm.warp(vm.getBlockTimestamp() + uint256(elapsed) % 3 days);
    }

    function _recordTransfer(uint256 index, uint256 from, uint256 to) private {
        --modelBalance[from];
        ++modelBalance[to];
        modelOwnerIndex[index] = to;
        ++successfulTransfers;
        assertEq(nft.getApproved(tokenIds[index]), address(0));
    }
}

contract SqueekInvariantTest is CompanionTestBase {
    CompanionHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new CompanionHandler(nft, [INITIAL_OWNER, alice, bob, operator]);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = CompanionHandler.move.selector;
        selectors[1] = CompanionHandler.approvedMove.selector;
        selectors[2] = CompanionHandler.pet.selector;
        selectors[3] = CompanionHandler.unauthorizedPet.selector;
        selectors[4] = CompanionHandler.unauthorizedTransfer.selector;
        selectors[5] = CompanionHandler.advanceTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyBalancesOwnershipAndCareMatchModel() public view {
        assertEq(nft.totalSupply(), 999);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            uint256 balance = nft.balanceOf(handler.actors(i));
            assertEq(balance, handler.modelBalance(i));
            sum += balance;
        }
        assertEq(sum, 999);
        for (uint256 i; i < 12; ++i) {
            uint256 tokenId = handler.tokenIds(i);
            assertEq(nft.ownerOf(tokenId), handler.actors(handler.modelOwnerIndex(i)));
            SqueekCompanion.Companion memory companion = nft.companionOf(tokenId);
            assertEq(companion.bond, handler.modelBond(i));
            assertEq(companion.nextPetAt, handler.modelNextPet(i));
            assertLe(companion.bond, 30);
            uint8 expectedStage = companion.bond < 5 ? 0 : companion.bond < 15 ? 1 : companion.bond < 30 ? 2 : 3;
            assertEq(nft.stageOf(tokenId), expectedStage);
            assertEq(nft.getApproved(tokenId), address(0));
        }
        assertEq(address(nft).balance, 0);
    }

    /// @dev Check the entire inventory after every generated sequence, including untouched consecutive IDs.
    function afterInvariant() public view {
        uint256[4] memory counted;
        for (uint256 tokenId = 1; tokenId <= 999; ++tokenId) {
            address holder = nft.ownerOf(tokenId);
            bool found;
            for (uint256 actor; actor < 4; ++actor) {
                if (holder == handler.actors(actor)) {
                    ++counted[actor];
                    found = true;
                    break;
                }
            }
            assertTrue(found);
        }
        for (uint256 i; i < 4; ++i) {
            assertEq(counted[i], nft.balanceOf(handler.actors(i)));
        }
    }

    function test_handlerExercisesSuccessAndFailure() public {
        handler.pet(0);
        handler.pet(0);
        handler.unauthorizedPet(0);
        handler.move(0, 1);
        handler.approvedMove(0, 2, true);
        handler.approvedMove(0, 3, false);
        handler.unauthorizedTransfer(0);
        handler.advanceTime(1 days);
        handler.pet(0);
        invariant_supplyBalancesOwnershipAndCareMatchModel();
        afterInvariant();
        assertEq(handler.successfulPets(), 2);
        assertEq(handler.successfulTransfers(), 3);
        assertEq(handler.rejectedActions(), 3);
    }
}
