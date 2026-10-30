// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SqueekCompanion} from "src/SqueekCompanion.sol";
import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";

/// @dev Each hop pets, grants approvals and forwards in the same EVM transaction. Rejection
/// occurs only after the downstream receiver has completed all of its effects.
contract CareRelayReceiver is IERC721Receiver {
    SqueekCompanion public immutable nft;
    address public immutable destination;
    address public immutable delegate;
    bool public immutable reject;
    uint256 public callbacks;
    address public receivedOperator;
    address public receivedFrom;
    bytes public receivedData;
    bool public petSucceeded;
    bytes public petError;

    error RejectAfterForward();

    constructor(SqueekCompanion nft_, address destination_, address delegate_, bool reject_) {
        nft = nft_;
        destination = destination_;
        delegate = delegate_;
        reject = reject_;
    }

    function onERC721Received(address operator_, address from_, uint256 id, bytes calldata data)
        external
        returns (bytes4)
    {
        require(msg.sender == address(nft), "unexpected collection");
        require(nft.ownerOf(id) == address(this), "ownership not settled before callback");
        require(nft.balanceOf(address(this)) == 1, "balance not settled before callback");
        require(nft.getApproved(id) == address(0), "old token approval visible in callback");
        ++callbacks;
        receivedOperator = operator_;
        receivedFrom = from_;
        receivedData = data;
        (petSucceeded, petError) = address(nft).call(abi.encodeCall(nft.pet, (id)));
        nft.approve(delegate, id);
        nft.setApprovalForAll(delegate, true);
        nft.safeTransferFrom(address(this), destination, id, data);
        if (reject) revert RejectAfterForward();
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// forge-config: default.fuzz.runs = 512
contract SqueekNestedCallbacksTest is CompanionTestBase {
    function testFuzz_nestedReceiversCannotAccelerateCare(uint256 id, uint8 priorBond, bytes memory data) public {
        id = bound(id, 1, 999);
        priorBond = uint8(bound(priorBond, 0, 30));
        _petTo(id, priorBond);
        _makeEligible(id);
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 oldDeadline = nft.companionOf(id).nextPetAt;
        (CareRelayReceiver first, CareRelayReceiver second) = _route(false, false);
        _send(first, id, data);

        assertEq(first.callbacks(), 1);
        assertEq(second.callbacks(), 1);
        assertEq(first.receivedOperator(), operator);
        assertEq(first.receivedFrom(), INITIAL_OWNER);
        assertEq(second.receivedOperator(), address(first));
        assertEq(second.receivedFrom(), address(first));
        assertEq(first.receivedData(), data);
        assertEq(second.receivedData(), data);
        assertEq(nft.ownerOf(id), alice);
        assertEq(nft.balanceOf(INITIAL_OWNER), 998);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.balanceOf(address(first)), 0);
        assertEq(nft.balanceOf(address(second)), 0);
        assertEq(nft.getApproved(id), address(0));
        assertTrue(nft.isApprovedForAll(address(first), operator));
        assertTrue(nft.isApprovedForAll(address(second), operator));

        uint8 expectedBond = priorBond == 30 ? 30 : priorBond + 1;
        uint256 expectedDeadline = priorBond == 30 ? oldDeadline : timestamp + 1 days;
        assertEq(nft.companionOf(id).bond, expectedBond, "one transaction must not grant two bond increments");
        assertEq(nft.companionOf(id).nextPetAt, expectedDeadline);
        assertEq(first.petSucceeded(), priorBond < 30);
        if (priorBond == 30) {
            assertEq(first.petError(), abi.encodeWithSelector(SqueekCompanion.FullyBonded.selector, id));
        }
        assertFalse(second.petSucceeded());
        bytes memory expectedError = expectedBond == 30
            ? abi.encodeWithSelector(SqueekCompanion.FullyBonded.selector, id)
            : abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, id, expectedDeadline);
        assertEq(second.petError(), expectedError);
        vm.prank(alice);
        vm.expectRevert(expectedError);
        nft.pet(id);
        assertEq(nft.totalSupply(), 999);
    }

    function testFuzz_rejectionRollsBackAllNestedEffects(uint256 id, uint8 priorBond, bool rejectAtFirst) public {
        id = bound(id, 1, 999);
        priorBond = uint8(bound(priorBond, 0, 29));
        _petTo(id, priorBond);
        _makeEligible(id);
        (CareRelayReceiver first, CareRelayReceiver second) = _route(rejectAtFirst, !rejectAtFirst);
        SqueekCompanion.Companion memory beforeCare = nft.companionOf(id);
        string memory beforeURI = nft.tokenURI(id);
        vm.prank(INITIAL_OWNER);
        nft.approve(operator, id);
        vm.prank(operator);
        vm.expectRevert(CareRelayReceiver.RejectAfterForward.selector);
        nft.safeTransferFrom(INITIAL_OWNER, address(first), id, hex"000102ff");

        assertEq(nft.ownerOf(id), INITIAL_OWNER);
        assertEq(nft.balanceOf(INITIAL_OWNER), 999);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(address(first)), 0);
        assertEq(nft.balanceOf(address(second)), 0);
        assertEq(nft.getApproved(id), operator, "original approval must be restored");
        assertFalse(nft.isApprovedForAll(address(first), operator));
        assertFalse(nft.isApprovedForAll(address(second), operator));
        assertEq(first.callbacks(), 0, "receiver storage must roll back too");
        assertEq(second.callbacks(), 0);
        assertEq(nft.companionOf(id).bond, beforeCare.bond);
        assertEq(nft.companionOf(id).nextPetAt, beforeCare.nextPetAt);
        assertEq(nft.tokenURI(id), beforeURI);
        assertEq(nft.totalSupply(), 999);

        // Failure must not consume eligibility or block the legitimate owner from making progress.
        vm.prank(INITIAL_OWNER);
        nft.pet(id);
        assertEq(nft.companionOf(id).bond, priorBond + 1);
        assertEq(nft.getApproved(id), operator, "care must not clear a transfer approval");
    }

    function test_rejectedLegendTransitionCanBeRetriedThroughAcceptingReceivers() public {
        _petTo(999, 29);
        _makeEligible(999);
        (CareRelayReceiver rejecting,) = _route(true, false);
        vm.prank(INITIAL_OWNER);
        nft.approve(operator, 999);
        vm.prank(operator);
        vm.expectRevert(CareRelayReceiver.RejectAfterForward.selector);
        nft.safeTransferFrom(INITIAL_OWNER, address(rejecting), 999);
        assertEq(nft.companionOf(999).bond, 29);
        assertEq(nft.stageOf(999), 2);

        (CareRelayReceiver first, CareRelayReceiver second) = _route(false, false);
        vm.prank(operator); // Reuses the approval restored by the reverted transaction.
        nft.safeTransferFrom(INITIAL_OWNER, address(first), 999);
        assertTrue(first.petSucceeded());
        assertFalse(second.petSucceeded());
        assertEq(second.petError(), abi.encodeWithSelector(SqueekCompanion.FullyBonded.selector, 999));
        assertEq(nft.companionOf(999).bond, 30);
        assertEq(nft.stageOf(999), 3);
        assertEq(nft.ownerOf(999), alice);
    }

    function _route(bool rejectFirst, bool rejectSecond)
        private
        returns (CareRelayReceiver first, CareRelayReceiver second)
    {
        second = new CareRelayReceiver(nft, alice, operator, rejectSecond);
        first = new CareRelayReceiver(nft, address(second), operator, rejectFirst);
    }

    function _makeEligible(uint256 id) private {
        uint256 deadline = nft.companionOf(id).nextPetAt;
        if (deadline > vm.getBlockTimestamp()) vm.warp(deadline);
    }

    function _send(CareRelayReceiver first, uint256 id, bytes memory data) private {
        vm.prank(INITIAL_OWNER);
        nft.approve(operator, id);
        vm.prank(operator);
        nft.safeTransferFrom(INITIAL_OWNER, address(first), id, data);
    }
}
