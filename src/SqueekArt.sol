// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Internal-only renderer, inlined into SqueekCompanion. No deployment or library linking needed.
///      All text is fixed or numeric, so user-supplied JSON/XML escaping is unnecessary.
library SqueekArt {
    using Strings for uint256;

    uint8 internal constant SQUEEKER_BOND = 5;
    uint8 internal constant COMPANION_BOND = 15;
    uint8 internal constant LEGEND_BOND = 30;
    uint256 internal constant PALETTE_COUNT = 6;

    function stage(uint8 bond) internal pure returns (uint8) {
        if (bond >= LEGEND_BOND) return 3;
        if (bond >= COMPANION_BOND) return 2;
        if (bond >= SQUEEKER_BOND) return 1;
        return 0;
    }

    function stageName(uint8 currentStage) internal pure returns (string memory) {
        if (currentStage == 3) return "Legend";
        if (currentStage == 2) return "Companion";
        if (currentStage == 1) return "Squeeker";
        return "Pup";
    }

    function tokenURI(uint256 tokenId, uint8 bond) internal pure returns (string memory) {
        uint8 currentStage = stage(bond);
        string memory json = string.concat(
            '{"name":"Squeek Companion #',
            tokenId.toString(),
            '","description":"A Squeekchain companion. Pet once per day to grow your bond. '
            '999 companions, with artwork and progress stored entirely on-chain.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg(tokenId, bond, currentStage))),
            '","attributes":[{"trait_type":"Stage","value":"',
            stageName(currentStage),
            '"},{"trait_type":"Bond","display_type":"number","value":',
            uint256(bond).toString(),
            ',"max_value":30},{"trait_type":"Palette","value":',
            ((tokenId - 1) % PALETTE_COUNT + 1).toString(),
            "}]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function svg(uint256 tokenId, uint8 bond, uint8 currentStage) internal pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="560" viewBox="0 0 480 560" '
            'role="img" aria-label="Squeek Companion">' '<rect width="480" height="560" rx="32" fill="#15192b"/>'
            '<rect x="20" y="20" width="440" height="520" rx="22" fill="#222940"/>'
            '<g font-family="monospace" text-anchor="middle" fill="#f5f1e8">'
            '<text x="240" y="58" font-size="15" letter-spacing="4">SQUEEKCHAIN</text>'
            '<text x="240" y="88" font-size="12" fill="#a6b6cb">COMPANION #',
            tokenId.toString(),
            "</text></g>",
            _mouse(tokenId, currentStage),
            '<g font-family="monospace" text-anchor="middle" fill="#f5f1e8">' '<text x="240" y="425" font-size="28">',
            stageName(currentStage),
            '</text><text x="240" y="456" font-size="14" fill="#a6b6cb">BOND ',
            uint256(bond).toString(),
            ' / 30</text></g><rect x="90" y="480" width="300" height="12" rx="6" fill="#15192b"/>'
            '<rect x="90" y="480" height="12" rx="6" fill="#baf2d8" width="',
            (uint256(bond) * 10).toString(),
            '"/><text x="240" y="521" font-family="monospace" text-anchor="middle" '
            'font-size="11" fill="#a6b6cb">A LITTLE CARE. A LASTING BOND.</text></svg>'
        );
    }

    function _mouse(uint256 tokenId, uint8 currentStage) private pure returns (string memory) {
        return string.concat(
            '<circle cx="240" cy="250" r="140" fill="#2e3854"/>'
            '<ellipse cx="240" cy="365" rx="100" ry="13" fill="#15192b"/>'
            '<path d="M315 323 Q405 355 365 283" fill="none" stroke="#edacbb" stroke-width="12" '
            'stroke-linecap="round"/><g fill="',
            _color(tokenId),
            '" stroke="#15192b" stroke-width="6">'
            '<circle cx="160" cy="191" r="48"/><circle cx="320" cy="191" r="48"/>'
            '<ellipse cx="240" cy="286" rx="100" ry="84"/></g>'
            '<g fill="#edacbb"><circle cx="160" cy="191" r="28"/><circle cx="320" cy="191" r="28"/></g>'
            '<g fill="#15192b"><ellipse cx="205" cy="270" rx="9" ry="13"/>'
            '<ellipse cx="275" cy="270" rx="9" ry="13"/></g>'
            '<g fill="#ffffff"><circle cx="208" cy="266" r="3"/><circle cx="278" cy="266" r="3"/></g>'
            '<ellipse cx="240" cy="298" rx="12" ry="8" fill="#cf7c96"/>'
            '<path d="M225 314 Q240 330 255 314" fill="none" stroke="#15192b" stroke-width="4" '
            'stroke-linecap="round"/>' '<g stroke="#f5f1e8" stroke-width="3" stroke-linecap="round">'
            '<path d="M188 295 L145 286 M188 305 L145 308 M292 295 L335 286 M292 305 L335 308"/></g>',
            _accessories(currentStage)
        );
    }

    function _accessories(uint8 currentStage) private pure returns (string memory) {
        if (currentStage == 0) return "";
        string memory scarf = '<path d="M178 340 Q240 370 302 340 L292 360 Q240 388 188 360Z" fill="#baf2d8"/>'
            '<path d="M280 355 L304 392 L280 395 L261 361Z" fill="#8ed8bd"/>';
        if (currentStage == 1) return scarf;
        string memory heart = '<path d="M359 153 C330 132 334 110 349 111 Q359 111 359 123 '
            'Q359 111 369 111 C384 110 388 132 359 153Z" fill="#f1a9b8"/>';
        if (currentStage == 2) return string.concat(scarf, heart);
        return string.concat(
            scarf,
            heart,
            '<path d="M196 190 L188 145 L218 162 L240 130 L262 162 L292 145 L284 190Z" '
            'fill="#f7d774" stroke="#15192b" stroke-width="5"/>' '<circle cx="240" cy="169" r="7" fill="#edacbb"/>'
            '<path d="M115 238 L121 252 L135 258 L121 264 L115 278 L109 264 L95 258 L109 252Z" fill="#f7d774"/>'
        );
    }

    /// @dev Six deterministic palettes, cycling by token ID. This is cosmetic variation, not randomness.
    function _color(uint256 tokenId) private pure returns (string memory) {
        uint256 palette = (tokenId - 1) % PALETTE_COUNT;
        if (palette == 0) return "#b7b2ed";
        if (palette == 1) return "#9ed8c8";
        if (palette == 2) return "#e7bd98";
        if (palette == 3) return "#a8c8e8";
        if (palette == 4) return "#e0accb";
        return "#d4d69b";
    }
}
