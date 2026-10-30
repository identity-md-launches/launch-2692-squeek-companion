# Squeek Companion test properties

This extension builds on the existing deployment, care, metadata, and inventory tests.
All tests use the real `SqueekCompanion` external API. Production contracts and dependencies
are unchanged. Actors and receiver contracts are local test fixtures; no deployed address,
RPC, private key, FFI, or additional dependency is needed.

## Discovery and scope

The five supplied Pashov discovery perspectives were applied locally, with the Trail of Bits
guidance used to distinguish meaningful properties from implementation restatements and
unreachable assertions. The following are required properties of this implementation's
documented design and inherited ERC-721 behavior, rather than speculative economic assumptions.

| Perspective | Property and basis | Coverage |
| --- | --- | --- |
| Conservation | There are exactly 999 NFTs; an account's balance equals its owned inventory. `SqueekCompanion.sol:34–40` and inherited ERC-721 ownership/balance accounting. | Both invariant suites track balances and owners. The new suite inspects all 999 owners after every sequence. The full-inventory test empties and restores the original holder's balance. |
| State transitions | Only the current owner may increase bond, one unit per eligible call, to a terminal maximum of 30. Transfer and approval changes preserve care. `SqueekCompanion.sol:43–57`. | The persistent-approval handler interleaves care with changing authority. Its `grow` action reaches terminal states in random sequences. Scripted regressions exercise early calls, exact deadlines, and terminal rejection after transfer. |
| Round trips and boundaries | Transferring out and back conserves the entire inventory and preserves care/metadata. Delayed care starts a fresh rolling cooldown, rather than accruing missed pets. `SqueekCompanion.sol:43–54,72–76`. | Full-inventory round trip; fuzzed late care at arbitrary `uint64` starting times; explicit zero, `uint32`, and `uint64` timestamp boundaries. No share-price or rounding property applies: the application has no such accounting. |
| Adversarial sequences | Token approval cannot delegate authority; operator approval belongs to the granting owner; a reverted receiver chain commits no nested effects. Inherited `ERC721._approve`, `_update`, `safeTransferFrom`, and `ERC721Utils.checkOnERC721Received`. | Persistent grant/revoke/replace actions, wrong senders and recipients, stale approvals, self-transfers, and two reentrant receiver hops with rejection at either hop. All expected errors are checked. |
| Token-specific properties | IDs outside 1–999 cannot alias a real token through the consecutive implementation's narrower ID representation. All transfer overloads clear token approval, while owner-scoped operator grants persist. `SqueekCompanion.sol:34–35,83–84` and inherited ERC-721 behavior. | Explicit high-bit aliases and maximum-width IDs across ten read/write paths, before and after moving boundary tokens; all three transfer overloads in random sequences. |

## New suites

- `SqueekApprovalInvariant.t.sol`: four actors, eight active IDs including the endpoints and
  IDs 255–257, with independent ownership, balance, token-approval, operator-approval, bond,
  and deadline models. Approvals remain live between handler actions. The invariant checks
  these models after every action; `afterInvariant` counts the complete 999-token inventory.
  Inline settings request 256 runs of depth 96 and fail on unexpected handler reverts.
  Three deterministic tests demonstrate successful transfers, rejected authority, exact
  cooldown boundaries, and terminal care, so coverage does not depend on chance alone.
- `SqueekNestedCallbacks.t.sol`: both receivers attempt care, grant approvals, and forward
  the token during a single outer safe-transfer call. Successful chains permit at most one
  bond increase. A rejection after forwarding restores every observed effect, including
  persistent operator approvals and the receivers' own storage. A failed Legend transition
  can be retried successfully with the original token approval. Fuzz tests use 512 runs.
- `SqueekBoundaryProperties.t.sol`: invalid-ID aliasing, full-inventory round trips, irregular
  rolling cooldowns, timestamp-width boundaries, and nonpayable entry points with one wei
  through maximum `uint128` payments. Fuzz tests use 1,000 runs; failure checks also verify
  that funds, ownership, approvals, and care remain unchanged.

The stateful model is driven only by attempted actions and their expected results, never
repaired from production getters. Invalid calls are checked for failure and the exact error;
they are not silently caught or discarded. Inputs are bounded or mapped into meaningful
cases without `vm.assume`. Higher ID and payment boundaries have explicit unit cases.

## Validation

Run from the repository root:

```sh
forge build --offline
FOUNDRY_FUZZ_SEED=0x236797faf6acfed737a13774e3160ca8a22b4ee390c285dbe0414d36976fc26b forge test --offline
```

Build output and cache can be directed into disposable scratch space with
`FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache`.
No submitted file depends on scratch content.

These are local behavioral tests, not a live Sepolia deployment rehearsal. The supplied
protected floor checks are environment-driven deployment checks and are not copied or
modified here. There is no ETH deposit/withdrawal ledger in this application; value
conservation is tested through its NFT inventory. The zero-ETH assertions concern rejected
normal payments, not ETH forced onto an address by unrelated EVM mechanisms.
