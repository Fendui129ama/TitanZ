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

    struct TnzEpochSnapshot {
        bytes32 rootHash;
        uint256 sightTotal;
        uint64 stampedAt;
        bool exists;
    }

    uint256 public constant TNZ_PRIVACY_MAX = 8;
    uint256 public constant TNZ_SIGHT_FEE = 0.004 ether;
    uint256 public constant TNZ_BOT_STAKE = 0.05 ether;
    uint256 public constant TNZ_MAX_SIGHTINGS = 143;
    uint256 public constant TNZ_OPEN_ALERT_CAP = 44;
    uint256 public constant TNZ_DELTA_FLOOR = 587;
    uint256 public constant TNZ_DELTA_CEIL = 9130;
    uint256 public constant TNZ_EPOCH_BLOCKS = 525;
    uint256 public constant TNZ_REP_CAP = 15024;
    uint256 public constant TNZ_CONF_FLOOR = 387;
    uint256 public constant TNZ_CONF_CEIL = 9282;
    uint256 public constant TNZ_MAX_BOUNTIES = 68;
    uint256 public constant TNZ_MAX_WATCH_SUBS = 235;
    uint256 public constant TNZ_MAX_RELAYS = 120;
    uint256 public constant TNZ_RANK_SCOUT = 595;
    uint256 public constant TNZ_RANK_HUNTER = 1377;
    uint256 public constant TNZ_RANK_TITAN = 3211;

    bytes32 private constant _MIX_0 = 0xcda94532c86431835bcb3953efc61163810c47be421e280890f677d1dcb69406;
    bytes32 private constant _MIX_1 = 0x0c4af312383d0dff1956b262fbb2d10ae7da2ec2be35142a4500d90f93da7c24;
    bytes32 private constant _MIX_2 = 0x66bb1e82dd1d27a83e3f54d49c9488b3b7fcb2f003c02a2035b201920b8df960;
    bytes32 private constant _MIX_3 = 0xbf50fb2a4167f3a6844c79e891069c979aaf6678fd2a9d56a4aa6f9d516ce39f;
    bytes32 private constant _MIX_4 = 0xe698b2891e6c884ef4d28498a4177ecc8852ec84dd6ea026d919ac18a4ecbfad;
    bytes32 private constant _MIX_5 = 0xd17d3e8c1c64b52340e9fac6560c6f0d6cf855463dad9d704d6685e0e72dd215;
    bytes32 private constant _MIX_6 = 0xb2abc124ccae6c547f697700780cac7d31a5f9c69a705ec5cc37e56cf6300faf;
    bytes32 private constant _MIX_7 = 0xa29287fbb5117e25299bcd1bb7fb511f365a9a523a0a085c276985c0882b980e;
    bytes32 private constant TNZ_DOMAIN = keccak256("TitanZ.obsidianRelayCrawl");

    address public immutable ADDRESS_A;
    address public immutable ADDRESS_B;
    address public immutable ADDRESS_C;

    address public sheriff;
    bool public deskFrozen;
    uint256 public activeEpoch;
    uint256 public lineSerial;
    uint256 public openScanJobs;
    uint256 public totalStakeWei;
    uint256 public genesisBlock;
    uint256 public openBountyCount;
    uint256 public watchSubCount;
    uint256 public relayCount;
    uint256 public bountyPoolWei;

    mapping(uint256 => TnzWatchLane) public watchLanes;
    mapping(bytes32 => TnzSighting) public sightings;
    mapping(bytes32 => TnzScanJob) public scanJobs;
    mapping(bytes32 => TnzAlertCell) public alerts;
    mapping(uint256 => TnzEpochRail) public epochRails;
    mapping(uint256 => mapping(address => uint256)) public botRep;
    mapping(bytes32 => mapping(address => bool)) public ackCast;
    mapping(bytes32 => bool) public sightIdUsed;
    mapping(bytes32 => bool) public scanIdUsed;
    mapping(bytes32 => bool) public alertIdUsed;
    mapping(address => TnzBotOperator) public botOperators;
    mapping(address => TnzRank) public botRank;
    mapping(bytes32 => TnzBountyCell) public bounties;
    mapping(bytes32 => TnzWatchSub) public watchSubs;
    mapping(bytes32 => TnzRelayCell) public relays;
    mapping(uint256 => TnzEpochSnapshot) public epochSnapshots;
    mapping(bytes32 => bool) public bountyIdUsed;
    mapping(bytes32 => bool) public subIdUsed;
    mapping(bytes32 => bool) public relayIdUsed;
    mapping(address => bytes32[]) private _sightsByBot;
    uint256 private _guard;

    modifier nonReentrant() {
        if (_guard == 2) revert TNZ_Reentered();
        _guard = 2;
        _;
        _guard = 1;
    }

    modifier onlySheriff() {
        if (msg.sender != sheriff) revert TNZ_NotSheriff();
        _;
    }

    modifier whenDeskOpen() {
        if (deskFrozen) revert TNZ_DeskFrozen();
        _;
    }

    modifier onlyActiveBot() {
        if (!botOperators[msg.sender].active) revert TNZ_NotBot();
        _;
    }

    constructor() {
        ADDRESS_A = 0xC44D2D4D7ee5ac623415cFA4f0f21D583C3b5A2e;
        ADDRESS_B = 0x631d83d78FDF1b1911620527276be819907fE3a2;
        ADDRESS_C = 0x8D00632E249c1f9629afB83554D90F327072E2F6;
        sheriff = msg.sender;
        _guard = 1;
        genesisBlock = block.number;
        activeEpoch = 1;
        _primeEpoch(1);
        _seedWatchLanes();
    }

    function transferSheriff(address next_) external onlySheriff {
        if (next_ == address(0)) revert TNZ_BadSheriff();
        address prev = sheriff;
        sheriff = next_;
        emit SheriffShifted(prev, next_);
    }

    function setDeskFrozen(bool v) external onlySheriff {
        deskFrozen = v;
        emit Frozen(v, msg.sender);
    }

    function advanceEpoch() external onlySheriff whenDeskOpen {
        uint256 n = activeEpoch + 1;
