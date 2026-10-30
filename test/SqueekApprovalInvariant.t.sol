// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekCompanion} from "src/SqueekCompanion.sol";
import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";

/// @dev Approvals are independent actions: they may remain live, be replaced/revoked, or become
/// irrelevant when ownership changes. Expected authority comes only from the action history.
contract PersistentApprovalHandler is Test {
    SqueekCompanion public immutable nft;
    address[4] public actors;
    uint256[8] public ids = [uint256(1), 2, 255, 256, 257, 500, 998, 999];
    mapping(uint256 => address) private owners;
    mapping(uint256 => address) public tokenApproval;
    mapping(address => mapping(address => bool)) public operatorApproval;
    mapping(address => uint256) public balances;
    mapping(uint256 => uint8) public bonds;
    mapping(uint256 => uint256) public deadlines;
    uint256 public acceptedTransfers;
    uint256 public acceptedPets;
    uint256 public rejectedCalls;

    constructor(SqueekCompanion nft_, address[4] memory actors_) {
        nft = nft_;
        actors = actors_;
        balances[actors_[0]] = 999;
    }

    function expectedOwner(uint256 id) public view returns (address) {
        return owners[id] == address(0) ? actors[0] : owners[id];
    }

    function changeTokenApproval(uint256 tokenSeed, uint256 callerSeed, uint256 delegateSeed) external {
        uint256 id = ids[tokenSeed % ids.length];
        address holder = expectedOwner(id);
        address caller = actors[callerSeed % actors.length];
        address delegate = _recipient(delegateSeed);
        bool authorized = caller == holder || operatorApproval[holder][caller];
        vm.prank(caller);
        (bool ok, bytes memory reason) = address(nft).call(abi.encodeCall(nft.approve, (delegate, id)));
        if (authorized) {
            assertTrue(ok, "owner or operator must be able to approve");
            tokenApproval[id] = delegate;
        } else {
            _rejected(ok, reason, abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, caller));
        }
    }

    function changeOperatorApproval(uint256 ownerSeed, uint256 delegateSeed, bool enabled) external {
        address holder = actors[ownerSeed % actors.length];
        address delegate = _recipient(delegateSeed);
        vm.prank(holder);
        (bool ok, bytes memory reason) = address(nft).call(abi.encodeCall(nft.setApprovalForAll, (delegate, enabled)));
        if (delegate == address(0)) {
            _rejected(ok, reason, abi.encodeWithSelector(IERC721Errors.ERC721InvalidOperator.selector, address(0)));
        } else {
            assertTrue(ok, "nonzero operator approval must succeed");
            operatorApproval[holder][delegate] = enabled;
        }
    }

    /// @dev All three transfer entry points, including zero recipients, wrong `from`, stale
    /// approvals, and self-transfers. Expected failures are checked, never swallowed.
    function move(uint256 tokenSeed, uint256 callerSeed, uint256 toSeed, uint256 fromSeed, uint8 kind) external {
        uint256 id = ids[tokenSeed % ids.length];
        address holder = expectedOwner(id);
        address caller = actors[callerSeed % actors.length];
        address to = _recipient(toSeed);
        address from = fromSeed % 5 == 4 ? address(0) : holder;
        bool authorized = caller == holder || tokenApproval[id] == caller || operatorApproval[holder][caller];
        bytes memory payload;
        if (kind % 3 == 0) {
            payload = abi.encodeCall(nft.transferFrom, (from, to, id));
        } else if (kind % 3 == 1) {
            payload = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", from, to, id);
        } else {
            payload =
                abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", from, to, id, hex"00ff01");
        }

        vm.prank(caller);
        (bool ok, bytes memory reason) = address(nft).call(payload);
        if (to == address(0)) {
            _rejected(ok, reason, abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, to));
        } else if (!authorized) {
            _rejected(ok, reason, abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, caller, id));
        } else if (from != holder) {
            _rejected(ok, reason, abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, from, id, holder));
        } else {
            assertTrue(ok, "authorized transfer must succeed");
            --balances[holder];
            ++balances[to];
            owners[id] = to;
            tokenApproval[id] = address(0);
            ++acceptedTransfers;
        }
    }

    function care(uint256 tokenSeed, uint256 callerSeed) external {
        _care(ids[tokenSeed % ids.length], actors[callerSeed % actors.length]);
    }

    function advanceTime(uint256 tokenSeed, uint8 edge) external {
        uint256 deadline = deadlines[ids[tokenSeed % ids.length]];
        uint256 now_ = vm.getBlockTimestamp();
        uint256 destination;
        if (edge % 5 == 0) destination = deadline == 0 ? 0 : deadline - 1;
        else if (edge % 5 == 1) destination = deadline;
        else if (edge % 5 == 2) destination = deadline + 1;
        else if (edge % 5 == 3) destination = now_ + 1 days;
        else destination = now_ + 365 days;
        // Sequences model a real chain: time never travels backwards.
        if (destination > now_) vm.warp(destination);
    }

    /// @dev Reach the terminal state during random campaigns instead of hoping 30 ordinary
    /// care actions happen to hit the same token. A fully bonded token still attempts care.
    function grow(uint256 tokenSeed, uint8 steps) external {
        uint256 id = ids[tokenSeed % ids.length];
        uint256 count = bound(steps, 1, 30);
        for (uint256 i; i < count; ++i) {
            if (deadlines[id] > vm.getBlockTimestamp()) vm.warp(deadlines[id]);
            _care(id, expectedOwner(id));
        }
    }

    function _care(uint256 id, address caller) private {
        vm.prank(caller);
        (bool ok, bytes memory reason) = address(nft).call(abi.encodeCall(nft.pet, (id)));
        if (caller != expectedOwner(id)) {
            _rejected(ok, reason, abi.encodeWithSelector(SqueekCompanion.NotTokenOwner.selector, caller, id));
        } else if (bonds[id] == 30) {
            _rejected(ok, reason, abi.encodeWithSelector(SqueekCompanion.FullyBonded.selector, id));
        } else if (vm.getBlockTimestamp() < deadlines[id]) {
            _rejected(ok, reason, abi.encodeWithSelector(SqueekCompanion.PetTooSoon.selector, id, deadlines[id]));
        } else {
            assertTrue(ok, "eligible holder must be able to pet");
            ++bonds[id];
            deadlines[id] = vm.getBlockTimestamp() + 1 days;
            ++acceptedPets;
        }
    }

    function _recipient(uint256 seed) private view returns (address) {
        uint256 choice = seed % 5;
        return choice == 4 ? address(0) : actors[choice];
    }

    function _rejected(bool ok, bytes memory actual, bytes memory expected) private {
        assertFalse(ok, "invalid call unexpectedly succeeded");
        assertEq(actual, expected, "incorrect failure reason");
        ++rejectedCalls;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract SqueekApprovalInvariantTest is CompanionTestBase {
    PersistentApprovalHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new PersistentApprovalHandler(nft, [INITIAL_OWNER, alice, bob, operator]);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.changeTokenApproval.selector;
        selectors[1] = handler.changeOperatorApproval.selector;
        selectors[2] = handler.move.selector;
        selectors[3] = handler.care.selector;
        selectors[4] = handler.advanceTime.selector;
        selectors[5] = handler.grow.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_inventoryAuthorityAndProgressMatchHistory() public view {
        assertEq(nft.totalSupply(), 999, "supply changed");
        uint256 total;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(nft.balanceOf(actor), handler.balances(actor), "balance differs from transfer history");
            total += nft.balanceOf(actor);
            for (uint256 j; j < 4; ++j) {
                address delegate = handler.actors(j);
                assertEq(
                    nft.isApprovedForAll(actor, delegate), handler.operatorApproval(actor, delegate), "operator scope"
                );
            }
            assertFalse(nft.isApprovedForAll(actor, address(0)));
        }
        assertEq(total, 999, "inventory not conserved");
        for (uint256 i; i < 8; ++i) {
            uint256 id = handler.ids(i);
            assertEq(nft.ownerOf(id), handler.expectedOwner(id), "owner differs from transfer history");
            assertEq(nft.getApproved(id), handler.tokenApproval(id), "token approval differs from history");
            SqueekCompanion.Companion memory companion = nft.companionOf(id);
            assertEq(companion.bond, handler.bonds(id), "only successful care may increase bond");
            assertEq(companion.nextPetAt, handler.deadlines(id), "cooldown changed unexpectedly");
            assertLe(companion.bond, 30);
        }
    }

    function afterInvariant() public view {
        // Also inspect untouched consecutive IDs: a correct totalSupply getter alone is insufficient.
        uint256[4] memory inventory;
        for (uint256 id = 1; id <= 999; ++id) {
            address holder = nft.ownerOf(id);
            assertEq(holder, handler.expectedOwner(id), "unexpected change to consecutive ownership");
            for (uint256 i; i < 4; ++i) {
                if (holder == handler.actors(i)) ++inventory[i];
            }
        }
        for (uint256 i; i < 4; ++i) {
            assertEq(nft.balanceOf(handler.actors(i)), inventory[i]);
        }
    }

    function test_persistentApprovalHistoryExercisesEveryAuthorityTransition() public {
        handler.changeOperatorApproval(0, 3, true);
        handler.changeTokenApproval(0, 3, 1); // Operator delegates token 1 to Alice.
        handler.care(0, 3); // Transfer authority is not care authority.
        handler.move(0, 1, 2, 0, 0); // Alice sends it to Bob.
        handler.care(0, 0); // Former owner cannot pet.
        handler.move(0, 3, 1, 0, 1); // Former owner's operator cannot move Bob's token.
        handler.changeOperatorApproval(2, 3, true);
        handler.changeTokenApproval(0, 3, 1);
        handler.changeOperatorApproval(2, 3, false);
        handler.move(0, 3, 1, 0, 2); // Revoked operator fails.
        handler.move(0, 1, 0, 0, 2); // Independent token approval remains usable.
        handler.move(0, 3, 1, 0, 0); // Original owner's still-live operator approval applies again.
        handler.changeTokenApproval(0, 1, 2);
        handler.move(0, 2, 1, 0, 1); // Approved self-transfer clears token approval.
        handler.move(0, 2, 0, 0, 0); // Cleared authority cannot be reused.
        invariant_inventoryAuthorityAndProgressMatchHistory();
        afterInvariant();
        assertEq(handler.acceptedTransfers(), 4);
        assertEq(handler.rejectedCalls(), 5);
    }

    function test_terminalCareRemainsClosedAfterApprovalChangesAndTransfers() public {
        handler.grow(0, 30);
        handler.changeTokenApproval(0, 0, 3);
        handler.move(0, 3, 1, 0, 2);
        handler.care(0, 1);
        handler.grow(0, 2);
        invariant_inventoryAuthorityAndProgressMatchHistory();
        assertEq(handler.acceptedPets(), 30);
        assertEq(handler.rejectedCalls(), 3);
        assertEq(nft.stageOf(1), 3);
    }

    function test_failureActionsPreservePendingApprovalAndCare() public {
        handler.care(0, 0);
        handler.care(0, 0); // Exact same timestamp.
        handler.advanceTime(0, 0); // One second too early.
        handler.care(0, 0);
        handler.advanceTime(0, 1); // Exact deadline is eligible.
        handler.care(0, 0);
        handler.changeTokenApproval(0, 0, 1);
        handler.changeTokenApproval(0, 1, 2); // Token delegate cannot delegate further.
        handler.move(0, 1, 4, 0, 0); // Zero recipient.
        handler.move(0, 1, 2, 4, 2); // Incorrect from.
        handler.changeOperatorApproval(0, 4, true); // Zero operator.
        invariant_inventoryAuthorityAndProgressMatchHistory();
        assertEq(nft.getApproved(1), alice);
        assertEq(handler.acceptedPets(), 2);
        assertEq(handler.acceptedTransfers(), 0);
        assertEq(handler.rejectedCalls(), 6);
    }
}
