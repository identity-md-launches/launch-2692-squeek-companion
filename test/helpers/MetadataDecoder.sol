// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Test-only independent Base64 decoder. JSON parsing is done by Foundry, not the production renderer.
library MetadataDecoder {
    function decodeURI(string memory uri, string memory prefix) internal pure returns (string memory) {
        bytes memory input = bytes(uri);
        bytes memory head = bytes(prefix);
        require(input.length >= head.length, "missing URI prefix");
        for (uint256 i; i < head.length; ++i) {
            require(input[i] == head[i], "wrong URI prefix");
        }
        uint256 length = input.length - head.length;
        require(length > 0 && length % 4 == 0, "invalid Base64 length");
        uint256 padding = input[input.length - 1] == "=" ? 1 : 0;
        if (input[input.length - 2] == "=") ++padding;
        bytes memory decoded = new bytes(length / 4 * 3 - padding);
        uint256 index;
        for (uint256 i = head.length; i < input.length; i += 4) {
            uint256 word = (_value(input[i]) << 18) | (_value(input[i + 1]) << 12) | (_value(input[i + 2]) << 6)
                | _value(input[i + 3]);
            if (index < decoded.length) decoded[index++] = bytes1(uint8(word >> 16));
            if (index < decoded.length) decoded[index++] = bytes1(uint8(word >> 8));
            if (index < decoded.length) decoded[index++] = bytes1(uint8(word));
        }
        return string(decoded);
    }

    function _value(bytes1 char) private pure returns (uint256) {
        uint8 value = uint8(char);
        if (value >= 65 && value <= 90) return value - 65;
        if (value >= 97 && value <= 122) return value - 71;
        if (value >= 48 && value <= 57) return value + 4;
        if (char == "+") return 62;
        if (char == "/") return 63;
        require(char == "=", "invalid Base64 character");
        return 0;
    }
}
