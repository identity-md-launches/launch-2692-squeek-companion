# Security review and test boundaries

## Application surface

The deployed application inherits OpenZeppelin v5.2.0 `ERC721Consecutive` and overrides the token-ID offset, metadata, and interface support. Its only new state-changing entry point is `pet(uint256)`. The renderer is an internal library using fixed strings and numeric attributes; it accepts no user-controlled text, URLs, or external contract addresses.

All 999 tokens are created in the nonpayable constructor. There is no external mint, burn, initializer, administrator, upgrade entry point, delegatecall, asset withdrawal, or external dependency. The supplied recipient is the sole constructor argument; factory/caller identities do not receive privileges. A zero recipient reverts. Tests rehearse CREATE2 deployment to the supplied recipient and scan the runtime using the same opcode-walk logic as the supplied deployment check.

## Access and state transitions

- ERC-721 transfers and approvals use the vendored implementation. Transfer clears token approval, conserves balances, and preserves care state. It does not bypass the cooldown or create a new token when given an invalid ID.
- Care requires the current token owner, checked through the same `ownerOf` used by ERC-721. Approval alone does not authorize care. Once an approved address transfers a token to itself, it is its owner and may care for it.
- Bond starts at zero and increases by exactly one per successful call, stopping at 30. The first call is available even at timestamp zero. Subsequent calls use `nextPetAt`, with equality allowed. Cooldowns are per token, not per account. All arithmetic is checked by Solidity.
- Transfers and time alone do not change the metadata, so no refresh event is needed on those paths. Every successful care call emits the application event and ERC-4906 metadata update event. Failed care leaves the state and metadata unchanged.

## External calls and callbacks

The constructor and `pet` make no external calls. Standard safe transfers invoke ERC-721 receiver callbacks only after ownership, balances, and token approval have been settled. No custom application logic writes state after those hooks. A blanket reentrancy guard is unnecessary here and would interfere with legitimate receiver composition.

The callback tests demonstrate that a receiver, as the new owner, may pet and forward its NFT; cannot pet it twice in the same block; cannot steal an unapproved neighboring token; and leaves the full transaction, including its pet, rolled back if it rejects receipt. Reverting receivers, invalid return selectors, and non-receivers are tested separately. The initial constructor allocation is deliberately not a safe mint: the launch must provide a usable recipient wallet.

## Supply, metadata and dependencies

The fixed range is 1–999. Tests check ownership of every ID initially and count all 999 after each stateful sequence. The stateful handler mixes owner and approved transfers, attempted unauthorized transfers and care, valid/early care, and time changes. An independent model tracks balances, ownership, bond and the next valid care timestamp. Dedicated tests drive all stage boundaries and the final cap, which random sequences might not reach.

Metadata tests decode Base64 using a separate test implementation and parse JSON through Foundry. They check numeric attributes, embedded SVG, progress bar, palettes, accessories, URI changes, and ERC-4906 event shape. There are no scripts, remote image references, mutable URIs, or user text in the generated SVG. All six palettes and the maximum bond are exercised. This does not prove that every marketplace renders SVG or honors ERC-2309/4906 correctly.

OpenZeppelin and forge-std are pinned, vendored, and licensed. `docs/dependencies.sha256` records their unmodified contents. The compiler is pinned to 0.8.26; compilation requires no remote Solidity imports or linked libraries. No proxy or auxiliary deployed contract is needed.

## Validation scope

Local validation uses `forge build`, `forge test` with the assignment's fuzz seed, `forge fmt --check`, and runtime size/opcode checks. The supplied environment-driven protected tests are deployment-handoff checks; this repository's tests do not supply or mutate their inputs. No Slither, Mythril, independent audit, live Sepolia deployment, explorer verification, or marketplace integration test is claimed.

Remaining release responsibilities are confirming deployment parameters and recipient control, reviewing the immutable implementation independently, verifying the deployed source, and checking the chosen indexer's support for constructor consecutive minting, Base64 SVG metadata, and metadata refresh events. Block timestamps can be influenced at the network's margins; this affects only the timing of cosmetic progression. There are no economic payouts or valuable random outcomes based on time.
