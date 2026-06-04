// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TitanZ
/// @notice codename: obsidian relay / titan cohort crawl
/// @dev TitanZ v2: ZEC wallet watch bot + bounties, watch subs, cross-lane relays,
///      titan ranks, and epoch snapshots. Pull-only stakes; no sinks.

library TnzMath {
    error TNZ_MathFault();
    uint256 internal constant RATIO_BASE = 10_000;
    function clampU16(uint256 v, uint16 lo, uint16 hi) internal pure returns (uint16) {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return uint16(v);
    }
    function mulBps(uint256 amt, uint256 bps) internal pure returns (uint256) {
        unchecked { return (amt * bps) / RATIO_BASE; }
    }
    function saturatingAdd(uint256 a, uint256 b, uint256 cap) internal pure returns (uint256) {
        unchecked {
            uint256 s = a + b;
            if (s < a || s > cap) revert TNZ_MathFault();
            return s;
        }
    }
}

contract TitanZ {
    // ── faults ───────────────────────────────────────────────────────────
    error TNZ_NotSheriff();
    error TNZ_DeskFrozen();
    error TNZ_ZeroAddr();
    error TNZ_ZeroAmt();
    error TNZ_Reentered();
    error TNZ_LaneMissing();
    error TNZ_LaneRetired();
    error TNZ_SightingExists();
    error TNZ_SightingMissing();
    error TNZ_TierOutOfRange();
    error TNZ_CapHit();
    error TNZ_BadEpoch();
    error TNZ_AlertOpen();
    error TNZ_AlertMissing();
    error TNZ_AlertClosed();
    error TNZ_StaleBot();
    error TNZ_ConfLow();
    error TNZ_ConfHigh();
    error TNZ_SheriffLocked();
    error TNZ_NoSheriff();
    error TNZ_BadSheriff();
    error TNZ_DigestVoid();
    error TNZ_AlreadyAck();
    error TNZ_SelfAck();
    error TNZ_StakeTooSmall();
    error TNZ_TransferFail();
    error TNZ_BatchTooWide();
    error TNZ_ArrayMismatch();
    error TNZ_NotBot();
    error TNZ_BotExists();
    error TNZ_BountyMissing();
