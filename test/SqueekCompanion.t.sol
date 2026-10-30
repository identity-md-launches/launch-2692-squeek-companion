// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekCompanion} from "../src/SqueekCompanion.sol";
import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";
import {
    CompanionFactory,
    RecordingReceiver,
    RejectingReceiver,
    WrongSelectorReceiver,
    NonReceiver,
    ReenteringReceiver
} from "./helpers/Receivers.sol";

contract SqueekCompanionTest is CompanionTestBase {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function test_collectionIdentityAndFixedSupply() public view {
        assertEq(nft.name(), "Squeek Companion");
        assertEq(nft.symbol(), "SQCOMP");
        assertEq(nft.MAX_SUPPLY(), 999);
        assertEq(nft.totalSupply(), 999);
        assertEq(nft.balanceOf(INITIAL_OWNER), 999);
        assertEq(nft.balanceOf(address(this)), 0);
        for (uint256 i = 1; i <= 999; ++i) {
            assertEq(nft.ownerOf(i), INITIAL_OWNER);
        }
    }

    function test_constructorEmitsOneConsecutiveMintAndNoTransferEvents() public {
        vm.recordLogs();
        SqueekCompanion created = new SqueekCompanion(INITIAL_OWNER);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(created));
        assertEq(logs[0].topics.length, 4);
        assertEq(logs[0].topics[0], keccak256("ConsecutiveTransfer(uint256,uint256,address,address)"));
        assertEq(logs[0].topics[1], bytes32(uint256(1)));
        assertEq(logs[0].topics[2], bytes32(0));
        assertEq(logs[0].topics[3], bytes32(uint256(uint160(INITIAL_OWNER))));
        assertEq(abi.decode(logs[0].data, (uint256)), 999);
    }

    function test_factoryDeploymentAllocatesToExplicitOwner() public {
        CompanionFactory factory = new CompanionFactory();
        bytes32 salt = keccak256("squeek-deployment-test");
        bytes memory initcode = bytes.concat(type(SqueekCompanion).creationCode, abi.encode(INITIAL_OWNER));
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(initcode)))))
        );
        vm.prank(bob);
        SqueekCompanion created = factory.deploy(INITIAL_OWNER, salt);
        assertEq(address(created), predicted);
        assertEq(created.balanceOf(INITIAL_OWNER), 999);
        assertEq(created.balanceOf(address(factory)), 0);
        assertEq(created.balanceOf(bob), 0);
        assertEq(created.ownerOf(999), INITIAL_OWNER);
    }

    function test_constructorRejectsZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        new SqueekCompanion(address(0));
    }

    function test_constructorDoesNotCallRecipient() public {
        RejectingReceiver receiver = new RejectingReceiver();
        SqueekCompanion created = new SqueekCompanion(address(receiver));
        assertEq(created.balanceOf(address(receiver)), 999);
    }

    function test_interfaces() public view {
        assertTrue(nft.supportsInterface(0x01ffc9a7)); // ERC-165
        assertTrue(nft.supportsInterface(0x80ac58cd)); // ERC-721
        assertTrue(nft.supportsInterface(0x5b5e139f)); // ERC-721 metadata
        assertTrue(nft.supportsInterface(0x49064906)); // ERC-4906, explicitly defined by the EIP
        assertFalse(nft.supportsInterface(0x780e9d63)); // Not enumerable
        assertFalse(nft.supportsInterface(0x2a55205a)); // No ERC-2981 royalties
        assertFalse(nft.supportsInterface(0xffffffff));
        assertFalse(nft.supportsInterface(0x00000000));
    }

    function testFuzz_nonexistentTokensRevertEveryReadAndPet(uint256 tokenId) public {
        if (tokenId > 0 && tokenId <= 999) tokenId += 999;
        bytes memory reason = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId);
        vm.expectRevert(reason);
        nft.ownerOf(tokenId);
        vm.expectRevert(reason);
        nft.getApproved(tokenId);
        vm.expectRevert(reason);
        nft.companionOf(tokenId);
        vm.expectRevert(reason);
        nft.stageOf(tokenId);
        vm.expectRevert(reason);
        nft.tokenURI(tokenId);
        vm.expectRevert(reason);
        nft.pet(tokenId);
    }

    function test_balanceOfZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOwner.selector, address(0)));
        nft.balanceOf(address(0));
    }

    function test_transferEmitsEventAndMovesOnlyOneToken() public {
        vm.expectEmit(true, true, true, true, address(nft));
        emit Transfer(INITIAL_OWNER, alice, 500);
        _give(alice, 500);
        assertEq(nft.balanceOf(INITIAL_OWNER), 998);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.ownerOf(499), INITIAL_OWNER);
        assertEq(nft.ownerOf(500), alice);
        assertEq(nft.ownerOf(501), INITIAL_OWNER);
        assertEq(nft.totalSupply(), 999);
    }

    function testFuzz_transferConservesBalancesAndOwnership(uint256 tokenId) public {
        tokenId = bound(tokenId, 1, 999);
        _give(alice, tokenId);
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);
        assertEq(nft.ownerOf(tokenId), bob);
        assertEq(nft.balanceOf(INITIAL_OWNER), 998);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
        vm.prank(bob);
        nft.transferFrom(bob, INITIAL_OWNER, tokenId);
        assertEq(nft.ownerOf(tokenId), INITIAL_OWNER);
        assertEq(nft.balanceOf(INITIAL_OWNER), 999);
        assertEq(nft.balanceOf(bob), 0);
    }

    function test_transferFirstAndLastTokenPreservesInterior() public {
        _give(alice, 1);
        _give(bob, 999);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(999), bob);
        for (uint256 i = 2; i < 999; ++i) {
            assertEq(nft.ownerOf(i), INITIAL_OWNER);
        }
    }

    function test_transferRequiresOwnerOrApproval() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, alice, 1));
        nft.transferFrom(INITIAL_OWNER, alice, 1);
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
    }

    function test_transferRejectsWrongFromAndRollsBackApprovalAndBalances() public {
        vm.prank(INITIAL_OWNER);
        nft.approve(operator, 1);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, alice, 1, INITIAL_OWNER));
        nft.transferFrom(alice, bob, 1);
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
        assertEq(nft.getApproved(1), operator);
        assertEq(nft.balanceOf(INITIAL_OWNER), 999);
        assertEq(nft.balanceOf(bob), 0);
    }

    function test_transferToZeroCannotBurn() public {
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        nft.transferFrom(INITIAL_OWNER, address(0), 1);
        assertEq(nft.totalSupply(), 999);
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
    }

    function test_nonexistentTokenCannotBeTransferredOrApproved() public {
        vm.startPrank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1000));
        nft.transferFrom(INITIAL_OWNER, alice, 1000);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        nft.approve(alice, 0);
        vm.stopPrank();
    }

    function test_tokenApprovalClearedAfterTransferAndCannotBeReused() public {
        vm.expectEmit(true, true, true, true, address(nft));
        emit Approval(INITIAL_OWNER, operator, 1);
        vm.prank(INITIAL_OWNER);
        nft.approve(operator, 1);
        assertEq(nft.getApproved(1), operator);
        vm.prank(operator);
        nft.transferFrom(INITIAL_OWNER, alice, 1);
        assertEq(nft.getApproved(1), address(0));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, operator, 1));
        nft.transferFrom(alice, operator, 1);
    }

    function test_selfTransferPreservesBalanceAndClearsApproval() public {
        vm.startPrank(INITIAL_OWNER);
        nft.approve(operator, 1);
        nft.transferFrom(INITIAL_OWNER, INITIAL_OWNER, 1);
        vm.stopPrank();
        assertEq(nft.balanceOf(INITIAL_OWNER), 999);
        assertEq(nft.getApproved(1), address(0));
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
    }

    function test_revokeTokenApproval() public {
        vm.startPrank(INITIAL_OWNER);
        nft.approve(operator, 1);
        nft.approve(address(0), 1);
        vm.stopPrank();
        assertEq(nft.getApproved(1), address(0));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, operator, 1));
        nft.transferFrom(INITIAL_OWNER, alice, 1);
    }

    function test_approvalForAllAndRevocation() public {
        vm.expectEmit(true, true, false, true, address(nft));
        emit ApprovalForAll(INITIAL_OWNER, operator, true);
        vm.prank(INITIAL_OWNER);
        nft.setApprovalForAll(operator, true);
        assertTrue(nft.isApprovedForAll(INITIAL_OWNER, operator));
        vm.prank(operator);
        nft.transferFrom(INITIAL_OWNER, alice, 999);
        vm.prank(INITIAL_OWNER);
        nft.setApprovalForAll(operator, false);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, operator, 1));
        nft.transferFrom(INITIAL_OWNER, alice, 1);
    }

    function test_operatorCanApproveButTokenApprovedAddressCannotDelegateApproval() public {
        vm.prank(INITIAL_OWNER);
        nft.setApprovalForAll(operator, true);
        vm.prank(operator);
        nft.approve(alice, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, alice));
        nft.approve(bob, 1);
        assertEq(nft.getApproved(1), alice);
    }

    function test_strangerCannotApprove() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, bob));
        nft.approve(bob, 1);
    }

    function test_zeroOperatorRejected() public {
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOperator.selector, address(0)));
        nft.setApprovalForAll(address(0), true);
    }

    function test_safeTransferToEOA() public {
        vm.prank(INITIAL_OWNER);
        nft.safeTransferFrom(INITIAL_OWNER, alice, 1);
        assertEq(nft.ownerOf(1), alice);
    }

    function test_safeTransferPassesDataAndSettlesStateBeforeCallback() public {
        RecordingReceiver receiver = new RecordingReceiver();
        vm.prank(INITIAL_OWNER);
        nft.approve(operator, 999);
        vm.prank(operator);
        nft.safeTransferFrom(INITIAL_OWNER, address(receiver), 999, hex"010203");
        assertEq(receiver.operator(), operator);
        assertEq(receiver.from(), INITIAL_OWNER);
        assertEq(receiver.tokenId(), 999);
        assertEq(receiver.data(), hex"010203");
        assertEq(receiver.ownerDuringCallback(), address(receiver));
        assertEq(receiver.balanceDuringCallback(), 1);
        assertEq(nft.getApproved(999), address(0));
    }

    function test_safeTransferNoDataOverloadCallsReceiver() public {
        RecordingReceiver receiver = new RecordingReceiver();
        vm.prank(INITIAL_OWNER);
        nft.safeTransferFrom(INITIAL_OWNER, address(receiver), 1);
        assertEq(receiver.data(), bytes(""));
        assertEq(receiver.operator(), INITIAL_OWNER);
        assertEq(nft.ownerOf(1), address(receiver));
    }

    function test_rejectingReceiverRollsBackTransfer() public {
        RejectingReceiver receiver = new RejectingReceiver();
        vm.prank(INITIAL_OWNER);
        nft.approve(operator, 1);
        vm.prank(operator);
        vm.expectRevert(RejectingReceiver.Rejected.selector);
        nft.safeTransferFrom(INITIAL_OWNER, address(receiver), 1);
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
        assertEq(nft.getApproved(1), operator);
        assertEq(nft.balanceOf(INITIAL_OWNER), 999);
        assertEq(nft.balanceOf(address(receiver)), 0);
    }

    function test_wrongSelectorReceiverRejected() public {
        WrongSelectorReceiver receiver = new WrongSelectorReceiver();
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver)));
        nft.safeTransferFrom(INITIAL_OWNER, address(receiver), 1, "");
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
    }

    function test_nonReceiverRejected() public {
        NonReceiver receiver = new NonReceiver();
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver)));
        nft.safeTransferFrom(INITIAL_OWNER, address(receiver), 1);
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
    }

    function test_callbackCanPetAndForwardButCannotDoublePetOrSteal() public {
        ReenteringReceiver receiver = new ReenteringReceiver(alice, false);
        uint256 expectedNextPet = vm.getBlockTimestamp() + 1 days;
        vm.prank(INITIAL_OWNER);
        nft.safeTransferFrom(INITIAL_OWNER, address(receiver), 1);
        assertFalse(receiver.duplicatePetSucceeded());
        assertEq(
            receiver.duplicatePetError(),
            abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, 1, expectedNextPet)
        );
        assertFalse(receiver.theftSucceeded());
        assertEq(
            receiver.theftError(),
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(receiver), 2)
        );
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), INITIAL_OWNER);
        assertEq(nft.balanceOf(address(receiver)), 0);
        assertEq(nft.balanceOf(INITIAL_OWNER), 998);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.companionOf(1).bond, 1);
        assertEq(nft.companionOf(1).nextPetAt, expectedNextPet);
    }

    function test_receiverRevertRollsBackCallbackPetAndMetadata() public {
        ReenteringReceiver receiver = new ReenteringReceiver(alice, true);
        string memory beforeURI = nft.tokenURI(1);
        vm.prank(INITIAL_OWNER);
        vm.expectRevert(ReenteringReceiver.RejectAfterPet.selector);
        nft.safeTransferFrom(INITIAL_OWNER, address(receiver), 1);
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
        assertEq(nft.companionOf(1).bond, 0);
        assertEq(nft.companionOf(1).nextPetAt, 0);
        assertEq(nft.tokenURI(1), beforeURI);
    }

    function test_noMintBurnOrMetadataAdminEntryPoints() public {
        vm.startPrank(INITIAL_OWNER);
        (bool minted,) = address(nft).call(abi.encodeWithSignature("mint(address,uint256)", INITIAL_OWNER, 1000));
        (bool burned,) = address(nft).call(abi.encodeWithSignature("burn(uint256)", 1));
        (bool changed,) = address(nft).call(abi.encodeWithSignature("setBaseURI(string)", "https://example.invalid/"));
        vm.stopPrank();
        assertFalse(minted);
        assertFalse(burned);
        assertFalse(changed);
        assertEq(nft.totalSupply(), 999);
        assertEq(nft.ownerOf(1), INITIAL_OWNER);
    }

    function test_nonpayableEntryPointsAndPlainEtherRejectPayment() public {
        vm.deal(INITIAL_OWNER, 1 ether);
        vm.startPrank(INITIAL_OWNER);
        (bool plain,) = address(nft).call{value: 1 wei}("");
        (bool paidPet,) = address(nft).call{value: 1 wei}(abi.encodeCall(nft.pet, (1)));
        vm.stopPrank();
        assertFalse(plain);
        assertFalse(paidPet);
        assertEq(address(nft).balance, 0);
        assertEq(nft.companionOf(1).bond, 0);
    }

    /// @dev Mirror the supplied protected runtime scan, with source creation rather than environment inputs.
    function test_runtimeBoundedAndContainsNoReachableEscapeOpcodes() public view {
        bytes memory code = address(nft).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        assertLe(type(SqueekCompanion).creationCode.length + 32, 49_152);
        bool reachable = true;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op == 0x5b) reachable = true;
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            if (reachable) assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
            if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) reachable = false;
        }
    }
}
