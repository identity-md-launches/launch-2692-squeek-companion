// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Consecutive} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Consecutive.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {SqueekArt} from "./SqueekArt.sol";

/// @title Squeek Companion
/// @notice 999 on-chain companions whose bond and artwork grow with their holder's care.
/// @dev All tokens are created with ERC-2309 in the constructor. There are no subsequent mint,
///      burn, administration, upgrade, or metadata replacement entry points.
contract SqueekCompanion is ERC721Consecutive, IERC4906 {
    uint96 public constant MAX_SUPPLY = 999;
    uint8 public constant MAX_BOND = 30;
    uint256 public constant PET_COOLDOWN = 1 days;

    struct Companion {
        uint8 bond;
        uint256 nextPetAt;
    }

    mapping(uint256 tokenId => Companion) private _companions;

    error NotTokenOwner(address caller, uint256 tokenId);
    error PetTooSoon(uint256 tokenId, uint256 nextPetAt);
    error FullyBonded(uint256 tokenId);

    event CompanionPetted(uint256 indexed tokenId, address indexed holder, uint8 bond, uint256 nextPetAt);

    /// @param initialOwner Receives every token (IDs 1 through 999). Must be the launch owner's wallet,
    ///                     not the deploying factory. No receiver callback is made during construction.
    constructor(address initialOwner) ERC721("Squeek Companion", "SQCOMP") {
        _mintConsecutive(initialOwner, MAX_SUPPLY);
    }

    /// @notice Exactly 999 tokens exist from deployment onward; none can be minted or burned later.
    function totalSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    /// @notice Increase a companion's bond by one, at most once per rolling 24 hours, up to 30.
    /// @dev Only the current token owner may pet; transfer approvals do not grant care permission.
    ///      The first pet is immediately available. Progress and cooldown persist across transfers.
    function pet(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner(msg.sender, tokenId);

        Companion storage companion = _companions[tokenId];
        if (companion.bond == MAX_BOND) revert FullyBonded(tokenId);
        if (block.timestamp < companion.nextPetAt) revert PetTooSoon(tokenId, companion.nextPetAt);

        companion.bond += 1;
        companion.nextPetAt = block.timestamp + PET_COOLDOWN;

        emit CompanionPetted(tokenId, msg.sender, companion.bond, companion.nextPetAt);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Read care progress. nextPetAt is zero before the first pet; at MAX_BOND no more pets are allowed.
    function companionOf(uint256 tokenId) external view returns (Companion memory) {
        _requireOwned(tokenId);
        return _companions[tokenId];
    }

    /// @notice Stage 0: Pup (0-4); 1: Squeeker (5-14); 2: Companion (15-29); 3: Legend (30).
    function stageOf(uint256 tokenId) external view returns (uint8) {
        _requireOwned(tokenId);
        return SqueekArt.stage(_companions[tokenId].bond);
    }

    /// @notice Fully on-chain Base64 JSON containing an embedded Base64 SVG and current attributes.
    /// @dev Only a successful pet changes the metadata; time passing or transfers alone do not change it.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return SqueekArt.tokenURI(tokenId, _companions[tokenId].bond);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == 0x49064906 || super.supportsInterface(interfaceId);
    }

    function _firstConsecutiveId() internal pure override returns (uint96) {
        return 1;
    }
}
