// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";
import {MetadataDecoder} from "./helpers/MetadataDecoder.sol";

contract SqueekMetadataTest is CompanionTestBase {
    function test_metadataContainsValidJSONAndEmbeddedSVG() public {
        _assertMetadata(1, 0, "Pup");
        _assertMetadata(999, 0, "Pup");
    }

    function test_stageChangesAppearInMetadataAndArtwork() public {
        string memory pup = _assertMetadata(1, 0, "Pup");
        assertFalse(vm.contains(pup, 'fill="#baf2d8"/><path'));
        _petTo(1, 5);
        string memory squeeker = _assertMetadata(1, 5, "Squeeker");
        assertTrue(vm.contains(squeeker, 'fill="#8ed8bd"'));
        assertFalse(vm.contains(squeeker, 'fill="#f1a9b8"'));
        _petTo(1, 15);
        string memory companion = _assertMetadata(1, 15, "Companion");
        assertTrue(vm.contains(companion, 'fill="#f1a9b8"'));
        assertFalse(vm.contains(companion, 'fill="#f7d774"'));
        _petTo(1, 30);
        string memory legend = _assertMetadata(1, 30, "Legend");
        assertTrue(vm.contains(legend, 'fill="#f7d774"'));
        assertNotEq(pup, squeeker);
        assertNotEq(squeeker, companion);
        assertNotEq(companion, legend);
    }

    function test_everyPetChangesMetadataEvenWithinSameStageAndEmitsRefresh() public {
        string memory beforeURI = nft.tokenURI(1);
        for (uint8 i = 1; i <= 30; ++i) {
            vm.recordLogs();
            _petTo(1, i);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(logs.length, 2);
            assertEq(logs[1].emitter, address(nft));
            assertEq(logs[1].topics.length, 1); // ERC-4906 token ID is deliberately not indexed.
            assertEq(logs[1].topics[0], keccak256("MetadataUpdate(uint256)"));
            assertEq(abi.decode(logs[1].data, (uint256)), 1);
            string memory afterURI = nft.tokenURI(1);
            assertNotEq(beforeURI, afterURI);
            beforeURI = afterURI;
        }
    }

    function test_timeAndTransferDoNotChangeMetadata() public {
        _petTo(1, 7);
        string memory uri = nft.tokenURI(1);
        vm.warp(vm.getBlockTimestamp() + 365 days);
        assertEq(nft.tokenURI(1), uri);
        vm.recordLogs();
        _give(alice, 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(nft.tokenURI(1), uri);
    }

    function test_oneCompanionsCareDoesNotAffectAnother() public {
        string memory uri = nft.tokenURI(2);
        _petTo(1, 30);
        assertEq(nft.tokenURI(2), uri);
    }

    function test_sixPalettesCycleDeterministically() public {
        string[6] memory colors = ["#b7b2ed", "#9ed8c8", "#e7bd98", "#a8c8e8", "#e0accb", "#d4d69b"];
        for (uint256 i = 1; i <= 12; ++i) {
            string memory svg = _assertMetadata(i, 0, "Pup");
            assertTrue(vm.contains(svg, string.concat('fill="', colors[(i - 1) % 6], '"')));
        }
    }

    function testFuzz_metadataMatchesTokenAndProgress(uint256 tokenId, uint8 bond) public {
        tokenId = bound(tokenId, 1, 999);
        bond = uint8(bound(bond, 0, 30));
        _petTo(tokenId, bond);
        string memory expected = bond < 5 ? "Pup" : bond < 15 ? "Squeeker" : bond < 30 ? "Companion" : "Legend";
        _assertMetadata(tokenId, bond, expected);
    }

    function test_decoderKnownVectors() public pure {
        assertEq(MetadataDecoder.decodeURI("test:TQ==", "test:"), "M");
        assertEq(MetadataDecoder.decodeURI("test:TWE=", "test:"), "Ma");
        assertEq(MetadataDecoder.decodeURI("test:TWFu", "test:"), "Man");
    }

    function _assertMetadata(uint256 tokenId, uint8 bond, string memory expectedStage)
        internal
        returns (string memory svg)
    {
        string memory json = MetadataDecoder.decodeURI(nft.tokenURI(tokenId), "data:application/json;base64,");
        assertEq(vm.parseJsonString(json, ".name"), string.concat("Squeek Companion #", vm.toString(tokenId)));
        assertTrue(vm.contains(vm.parseJsonString(json, ".description"), "Squeekchain"));
        assertEq(vm.parseJsonString(json, ".attributes[0].trait_type"), "Stage");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), expectedStage);
        assertEq(vm.parseJsonString(json, ".attributes[1].trait_type"), "Bond");
        assertEq(vm.parseJsonString(json, ".attributes[1].display_type"), "number");
        assertEq(vm.parseJsonUint(json, ".attributes[1].value"), bond);
        assertEq(vm.parseJsonUint(json, ".attributes[1].max_value"), 30);
        assertEq(vm.parseJsonUint(json, ".attributes[2].value"), (tokenId - 1) % 6 + 1);
        svg = MetadataDecoder.decodeURI(vm.parseJsonString(json, ".image"), "data:image/svg+xml;base64,");
        assertTrue(vm.contains(svg, '<svg xmlns="http://www.w3.org/2000/svg"'));
        assertTrue(vm.contains(svg, "</svg>"));
        assertTrue(vm.contains(svg, string.concat("COMPANION #", vm.toString(tokenId), "</text>")));
        assertTrue(vm.contains(svg, string.concat(">", expectedStage, "</text>")));
        assertTrue(vm.contains(svg, string.concat("BOND ", vm.toString(bond), " / 30")));
        assertTrue(vm.contains(svg, string.concat('fill="#baf2d8" width="', vm.toString(uint256(bond) * 10), '"')));
        assertFalse(vm.contains(svg, "<script"));
        assertFalse(vm.contains(svg, "href="));
    }
}
