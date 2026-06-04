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
    error TNZ_BountyClosed();
    error TNZ_BountyTaken();
    error TNZ_SubExists();
    error TNZ_SubMissing();
    error TNZ_RelayExists();
    error TNZ_RankLow();
    error TNZ_SnapshotSet();

    event Watched(bytes32 indexed sightId, uint256 indexed laneId, address indexed bot, uint8 tier);
    event Acked(bytes32 indexed sightId, address indexed acker, bool up);
    event Staked(bytes32 indexed sightId, address indexed from, uint256 weiAmt);
    event Scanned(bytes32 indexed scanId, uint256 indexed laneId, bytes32 walletTag);
    event Sealed(bytes32 indexed scanId, bytes32 payloadHash, uint16 confidence);
    event Alerted(bytes32 indexed alertId, uint256 indexed laneId, uint16 deltaBand);
    event Opened(uint256 indexed laneId, bytes32 laneTag, uint8 tier);
    event Rolled(uint256 indexed epochId, uint64 wallTs, uint256 sightWeight);
    event Frozen(bool deskFrozen, address indexed by);
    event SheriffShifted(address indexed prev, address indexed next);
    event BotJoined(address indexed bot, bytes32 label);
    event BotLeft(address indexed bot);
    event BountyPosted(bytes32 indexed bountyId, uint256 indexed laneId, uint256 rewardWei);
    event BountyClaimed(bytes32 indexed bountyId, address indexed bot, uint256 rewardWei);
    event Subscribed(bytes32 indexed subId, address indexed watcher, bytes32 walletTag);
    event Unsubscribed(bytes32 indexed subId, address indexed watcher);
    event Relayed(bytes32 indexed relayId, uint256 fromLane, uint256 toLane, address bot);
    event RankRaised(address indexed bot, uint8 newRank);
    event SnapshotSaved(uint256 indexed epochId, bytes32 rootHash, uint256 sightTotal);
    event Pulse_0(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_1(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_2(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_3(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_4(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_5(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_6(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_7(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_8(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_9(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Pulse_10(uint256 indexed lineId, address indexed actor, uint256 meta);

    enum TnzLanePhase { Draft, Live, Archived }
    enum TnzScanPhase { Queued, Running, Done, Failed }
    enum TnzRank { Scout, Hunter, Titan, Mythic }

    struct TnzWatchLane {
        TnzLanePhase phase;
        uint8 privacyTier;
        uint64 openedAt;
        uint32 sightCount;
        uint32 scanCount;
        uint256 reputationSum;
        bytes32 laneTag;
    }

    struct TnzSighting {
        uint256 laneId;
        address bot;
        bytes32 walletFingerprint;
        uint8 privacyTier;
        uint32 upAcks;
        uint32 downAcks;
        uint256 stakeWei;
        uint64 loggedAt;
        bool exists;
    }

    struct TnzScanJob {
        uint256 laneId;
        address requester;
        bytes32 walletTag;
        TnzScanPhase phase;
        bytes32 resultHash;
        uint16 confidence;
        uint64 queuedAt;
    }

    struct TnzAlertCell {
        uint256 laneId;
        bytes32 deltaTag;
        bytes32 summaryHash;
        uint16 deltaBand;
        uint64 stampedAt;
    }

    struct TnzEpochRail {
        uint64 startedAt;
        uint256 sightWeight;
        uint256 scanWeight;
        bytes32 mixHA;
        bytes32 mixHB;
    }

    struct TnzBotOperator {
        bool active;
        bytes32 label;
        uint64 joinedAt;
        uint32 sightTally;
    }

    struct TnzBountyCell {
        uint256 laneId;
        bytes32 targetTag;
        uint256 rewardWei;
        address poster;
        address claimer;
        bool open;
        bool claimed;
    }

    struct TnzWatchSub {
        address watcher;
        bytes32 walletTag;
        uint64 subscribedAt;
        bool active;
    }

    struct TnzRelayCell {
        uint256 fromLane;
        uint256 toLane;
        bytes32 fingerprint;
        address relayer;
        uint64 relayAt;
    }
