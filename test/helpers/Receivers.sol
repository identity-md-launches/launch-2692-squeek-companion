// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SqueekCompanion} from "../../src/SqueekCompanion.sol";

contract RecordingReceiver is IERC721Receiver {
    address public operator;
    address public from;
    uint256 public tokenId;
    bytes public data;
    address public ownerDuringCallback;
    uint256 public balanceDuringCallback;

    function onERC721Received(address operator_, address from_, uint256 tokenId_, bytes calldata data_)
        external
        returns (bytes4)
    {
        operator = operator_;
        from = from_;
        tokenId = tokenId_;
        data = data_;
        ownerDuringCallback = SqueekCompanion(msg.sender).ownerOf(tokenId_);
        balanceDuringCallback = SqueekCompanion(msg.sender).balanceOf(address(this));
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract RejectingReceiver is IERC721Receiver {
    error Rejected();

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        revert Rejected();
    }
}

contract WrongSelectorReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(0);
    }
}

contract NonReceiver {}

/// @dev An NFT receiver is the legitimate new owner during its hook. Exercise both authorized
///      callback actions and attempts to bypass cooldowns or steal another token.
contract ReenteringReceiver is IERC721Receiver {
    address public immutable destination;
    bool public immutable rejectAfterPet;
    bool public duplicatePetSucceeded;
    bytes public duplicatePetError;
    bool public theftSucceeded;
    bytes public theftError;

    error RejectAfterPet();

    constructor(address destination_, bool rejectAfterPet_) {
        destination = destination_;
        rejectAfterPet = rejectAfterPet_;
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes calldata) external returns (bytes4) {
        SqueekCompanion token = SqueekCompanion(msg.sender);
        token.pet(tokenId);
        if (rejectAfterPet) revert RejectAfterPet();
        (duplicatePetSucceeded, duplicatePetError) = address(token).call(abi.encodeCall(token.pet, (tokenId)));
        (theftSucceeded, theftError) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, destination, tokenId + 1)));
        token.transferFrom(address(this), destination, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract CompanionFactory {
    function deploy(address initialOwner, bytes32 salt) external returns (SqueekCompanion) {
        return new SqueekCompanion{salt: salt}(initialOwner);
    }
}
