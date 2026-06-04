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
        if (n > 30) revert TNZ_BadEpoch();
        activeEpoch = n;
        _primeEpoch(n);
        emit Rolled(n, uint64(block.timestamp), _epochSightWeight());
    }

    function retireLane(uint256 laneId) external onlySheriff {
        TnzWatchLane storage lane = watchLanes[laneId];
        if (lane.phase == TnzLanePhase.Draft) revert TNZ_LaneMissing();
        lane.phase = TnzLanePhase.Archived;
    }

    function registerBot(address bot, bytes32 label) external onlySheriff {
        if (bot == address(0)) revert TNZ_ZeroAddr();
        if (botOperators[bot].active) revert TNZ_BotExists();
        botOperators[bot] = TnzBotOperator({
            active: true,
            label: label,
            joinedAt: uint64(block.timestamp),
            sightTally: 0
        });
        emit BotJoined(bot, label);
    }

    function revokeBot(address bot) external onlySheriff {
        if (!botOperators[bot].active) revert TNZ_NotBot();
        botOperators[bot].active = false;
        emit BotLeft(bot);
    }

    function withdrawSurplus(uint256 amt, address payable to) external onlySheriff nonReentrant {
        if (to == address(0)) revert TNZ_ZeroAddr();
        if (amt == 0 || amt > address(this).balance) revert TNZ_ZeroAmt();
        _sendNative(to, amt);
    }

    function logSighting(
        bytes32 sightId,
        uint256 laneId,
        bytes32 walletFingerprint,
        uint8 privacyTier
    ) external payable nonReentrant whenDeskOpen onlyActiveBot {
        if (sightId == bytes32(0)) revert TNZ_DigestVoid();
        if (sightIdUsed[sightId]) revert TNZ_SightingExists();
        if (msg.value < TNZ_SIGHT_FEE) revert TNZ_StakeTooSmall();
        if (privacyTier == 0 || privacyTier > TNZ_PRIVACY_MAX) revert TNZ_TierOutOfRange();
        TnzWatchLane storage lane = watchLanes[laneId];
        if (lane.phase != TnzLanePhase.Live) revert TNZ_LaneRetired();
        if (lane.sightCount >= TNZ_MAX_SIGHTINGS) revert TNZ_CapHit();
        sightIdUsed[sightId] = true;
        sightings[sightId] = TnzSighting({
            laneId: laneId,
            bot: msg.sender,
            walletFingerprint: walletFingerprint,
            privacyTier: privacyTier,
            upAcks: 0,
            downAcks: 0,
            stakeWei: msg.value,
            loggedAt: uint64(block.timestamp),
            exists: true
        });
        unchecked {
            lane.sightCount += 1;
            lane.reputationSum = TnzMath.saturatingAdd(
                lane.reputationSum, uint256(privacyTier) * 100, TNZ_REP_CAP
            );
            botOperators[msg.sender].sightTally += 1;
        }
        botRep[activeEpoch][msg.sender] += uint256(privacyTier) * 10;
        totalStakeWei += msg.value;
        _sightsByBot[msg.sender].push(sightId);
        emit Watched(sightId, laneId, msg.sender, privacyTier);
    }

    function ackSighting(bytes32 sightId, bool up) external whenDeskOpen {
        TnzSighting storage s = sightings[sightId];
        if (!s.exists) revert TNZ_SightingMissing();
        if (s.bot == msg.sender) revert TNZ_SelfAck();
        if (ackCast[sightId][msg.sender]) revert TNZ_AlreadyAck();
        ackCast[sightId][msg.sender] = true;
        if (up) unchecked { s.upAcks += 1; }
        else unchecked { s.downAcks += 1; }
        emit Acked(sightId, msg.sender, up);
    }

    function stakeSighting(bytes32 sightId) external payable nonReentrant whenDeskOpen {
        if (msg.value == 0) revert TNZ_ZeroAmt();
        TnzSighting storage s = sightings[sightId];
        if (!s.exists) revert TNZ_SightingMissing();
        s.stakeWei += msg.value;
        totalStakeWei += msg.value;
        _sendNative(s.bot, msg.value);
        emit Staked(sightId, msg.sender, msg.value);
    }

    function joinBot(bytes32 label) external payable nonReentrant whenDeskOpen {
        if (msg.value < TNZ_BOT_STAKE) revert TNZ_StakeTooSmall();
        if (botOperators[msg.sender].active) revert TNZ_BotExists();
        botOperators[msg.sender] = TnzBotOperator({
            active: true,
            label: label,
            joinedAt: uint64(block.timestamp),
            sightTally: 0
        });
        totalStakeWei += msg.value;
        emit BotJoined(msg.sender, label);
    }

    function queueScan(bytes32 scanId, uint256 laneId, bytes32 walletTag)
        external
        payable
        nonReentrant
        whenDeskOpen
        onlyActiveBot
    {
        if (scanId == bytes32(0)) revert TNZ_DigestVoid();
        if (scanIdUsed[scanId]) revert TNZ_AlertOpen();
        if (msg.value < TNZ_SIGHT_FEE) revert TNZ_StakeTooSmall();
        if (openScanJobs >= TNZ_OPEN_ALERT_CAP) revert TNZ_CapHit();
        TnzWatchLane storage lane = watchLanes[laneId];
        if (lane.phase != TnzLanePhase.Live) revert TNZ_LaneRetired();
        scanIdUsed[scanId] = true;
        scanJobs[scanId] = TnzScanJob({
            laneId: laneId,
            requester: msg.sender,
            walletTag: walletTag,
            phase: TnzScanPhase.Queued,
            resultHash: bytes32(0),
            confidence: 0,
            queuedAt: uint64(block.timestamp)
        });
        unchecked {
            openScanJobs += 1;
            lane.scanCount += 1;
        }
        emit Scanned(scanId, laneId, walletTag);
    }

    function sealScan(bytes32 scanId, bytes32 payloadHash, uint16 confidence) external onlySheriff {
        TnzScanJob storage j = scanJobs[scanId];
        if (j.phase != TnzScanPhase.Queued && j.phase != TnzScanPhase.Running) revert TNZ_AlertClosed();
        if (confidence < TNZ_CONF_FLOOR) revert TNZ_ConfLow();
        if (confidence > TNZ_CONF_CEIL) revert TNZ_ConfHigh();
        j.phase = TnzScanPhase.Done;
        j.resultHash = payloadHash;
        j.confidence = confidence;
        if (openScanJobs > 0) unchecked { openScanJobs -= 1; }
        emit Sealed(scanId, payloadHash, confidence);
    }

    function publishAlert(
        bytes32 alertId,
        uint256 laneId,
        bytes32 deltaTag,
        bytes32 summaryHash,
        uint16 deltaBand
    ) external onlySheriff whenDeskOpen {
        if (alertIdUsed[alertId]) revert TNZ_StaleBot();
        if (deltaBand < TNZ_DELTA_FLOOR) revert TNZ_ConfLow();
        if (deltaBand > TNZ_DELTA_CEIL) revert TNZ_ConfHigh();
        TnzWatchLane storage lane = watchLanes[laneId];
        if (lane.phase != TnzLanePhase.Live) revert TNZ_LaneRetired();
        alertIdUsed[alertId] = true;
        alerts[alertId] = TnzAlertCell({
            laneId: laneId,
            deltaTag: deltaTag,
            summaryHash: summaryHash,
            deltaBand: deltaBand,
            stampedAt: uint64(block.timestamp)
        });
        emit Alerted(alertId, laneId, deltaBand);
    }

    function fundBotLane() external payable whenDeskOpen {
        if (msg.value == 0) revert TNZ_ZeroAmt();
        emit Pulse_0(lineSerial, msg.sender, msg.value);
        unchecked { lineSerial += 1; }
    }

    function _sendNative(address to, uint256 amt) internal {
        (bool ok, ) = payable(to).call{value: amt}("");
        if (!ok) revert TNZ_TransferFail();
    }

    function _primeEpoch(uint256 epochId) internal {
        TnzEpochRail storage e = epochRails[epochId];
        e.startedAt = uint64(block.timestamp);
        e.sightWeight = _epochSightWeight();
        e.scanWeight = openScanJobs;
        (e.mixHA, e.mixHB) = _splitMix(epochId, e.sightWeight, e.scanWeight);
    }

    function _splitMix(uint256 epochId, uint256 sw, uint256 scw)
        internal
        view
        returns (bytes32 hA, bytes32 hB)
    {
        hA = keccak256(abi.encode(TNZ_DOMAIN, epochId, sw, ADDRESS_A, _MIX_0));
        hB = keccak256(abi.encode(scw, epochId, ADDRESS_B, _MIX_1, TNZ_EPOCH_BLOCKS));
    }

    function sightDigest(bytes32 sightId) public view returns (bytes32) {
        TnzSighting storage s = sightings[sightId];
        (bytes32 hA, bytes32 hB) = _splitMix(s.laneId, uint256(uint160(s.bot)), s.stakeWei);
        return keccak256(abi.encodePacked(hA, hB, s.walletFingerprint, ADDRESS_C, _MIX_2));
    }

    function _epochSightWeight() internal view returns (uint256 w) {
        for (uint256 i = 1; i <= 27; ++i) {
            w += watchLanes[i].reputationSum;
        }
    }

    function _tripleMix(uint256 laneId, uint256 epochId, address actor)
        internal
        view
        returns (bytes32 hA, bytes32 hB, bytes32 hC)
    {
        hA = keccak256(abi.encode(TNZ_DOMAIN, laneId, epochId, ADDRESS_A, _MIX_3));
        hB = keccak256(abi.encode(actor, epochId, ADDRESS_B, _MIX_4, TNZ_EPOCH_BLOCKS));
        hC = keccak256(abi.encodePacked(hA, hB, ADDRESS_C, _MIX_5));
    }

    function _rankForRep(uint256 rep) internal pure returns (TnzRank) {
        if (rep >= TNZ_RANK_TITAN) return TnzRank.Mythic;
        if (rep >= TNZ_RANK_HUNTER) return TnzRank.Titan;
        if (rep >= TNZ_RANK_SCOUT) return TnzRank.Hunter;
        return TnzRank.Scout;
    }

    // ── TitanZ v2: bounties, subs, relays, ranks, snapshots ───────────────

    function postBounty(
        bytes32 bountyId,
        uint256 laneId,
        bytes32 targetTag
    ) external payable nonReentrant whenDeskOpen {
        if (bountyId == bytes32(0)) revert TNZ_DigestVoid();
        if (bountyIdUsed[bountyId]) revert TNZ_BountyTaken();
        if (msg.value == 0) revert TNZ_ZeroAmt();
        if (openBountyCount >= TNZ_MAX_BOUNTIES) revert TNZ_CapHit();
        TnzWatchLane storage lane = watchLanes[laneId];
        if (lane.phase != TnzLanePhase.Live) revert TNZ_LaneRetired();
        bountyIdUsed[bountyId] = true;
        bounties[bountyId] = TnzBountyCell({
            laneId: laneId,
            targetTag: targetTag,
            rewardWei: msg.value,
            poster: msg.sender,
            claimer: address(0),
            open: true,
            claimed: false
        });
        unchecked {
            openBountyCount += 1;
            bountyPoolWei += msg.value;
        }
        emit BountyPosted(bountyId, laneId, msg.value);
    }

    function claimBounty(bytes32 bountyId, bytes32 scanId) external nonReentrant whenDeskOpen onlyActiveBot {
        TnzBountyCell storage b = bounties[bountyId];
        if (!b.open || b.claimed) revert TNZ_BountyClosed();
        TnzScanJob storage j = scanJobs[scanId];
        if (j.phase != TnzScanPhase.Done) revert TNZ_AlertClosed();
        if (j.walletTag != b.targetTag) revert TNZ_BountyMissing();
        if (j.laneId != b.laneId) revert TNZ_LaneMissing();
        b.open = false;
        b.claimed = true;
        b.claimer = msg.sender;
        uint256 payout = b.rewardWei;
        if (openBountyCount > 0) unchecked { openBountyCount -= 1; }
        if (bountyPoolWei >= payout) unchecked { bountyPoolWei -= payout; }
        _sendNative(msg.sender, payout);
        emit BountyClaimed(bountyId, msg.sender, payout);
    }

    function subscribeWatch(bytes32 subId, bytes32 walletTag) external whenDeskOpen {
        if (subId == bytes32(0)) revert TNZ_DigestVoid();
        if (subIdUsed[subId]) revert TNZ_SubExists();
        if (watchSubCount >= TNZ_MAX_WATCH_SUBS) revert TNZ_CapHit();
        subIdUsed[subId] = true;
        watchSubs[subId] = TnzWatchSub({
            watcher: msg.sender,
            walletTag: walletTag,
            subscribedAt: uint64(block.timestamp),
            active: true
        });
        unchecked { watchSubCount += 1; }
        emit Subscribed(subId, msg.sender, walletTag);
    }

    function unsubscribeWatch(bytes32 subId) external whenDeskOpen {
        TnzWatchSub storage s = watchSubs[subId];
        if (!s.active) revert TNZ_SubMissing();
        if (s.watcher != msg.sender && msg.sender != sheriff) revert TNZ_NotSheriff();
        s.active = false;
        if (watchSubCount > 0) unchecked { watchSubCount -= 1; }
        emit Unsubscribed(subId, s.watcher);
    }

    function relayAcrossLanes(
        bytes32 relayId,
        uint256 fromLane,
        uint256 toLane,
        bytes32 fingerprint
    ) external whenDeskOpen onlyActiveBot {
        if (relayId == bytes32(0)) revert TNZ_DigestVoid();
        if (relayIdUsed[relayId]) revert TNZ_RelayExists();
        if (relayCount >= TNZ_MAX_RELAYS) revert TNZ_CapHit();
        if (fromLane == toLane) revert TNZ_LaneMissing();
        TnzWatchLane storage src = watchLanes[fromLane];
        TnzWatchLane storage dst = watchLanes[toLane];
        if (src.phase != TnzLanePhase.Live || dst.phase != TnzLanePhase.Live) revert TNZ_LaneRetired();
        relayIdUsed[relayId] = true;
        relays[relayId] = TnzRelayCell({
            fromLane: fromLane,
            toLane: toLane,
            fingerprint: fingerprint,
            relayer: msg.sender,
            relayAt: uint64(block.timestamp)
        });
        unchecked { relayCount += 1; }
        botRep[activeEpoch][msg.sender] += 25;
        emit Relayed(relayId, fromLane, toLane, msg.sender);
    }

    function refreshBotRank(address bot) external whenDeskOpen {
        if (!botOperators[bot].active) revert TNZ_NotBot();
        uint256 rep = botRep[activeEpoch][bot];
        TnzRank r = _rankForRep(rep);
        botRank[bot] = r;
        emit RankRaised(bot, uint8(r));
    }

    function sheriffPromoteRank(address bot, TnzRank rank) external onlySheriff {
        if (!botOperators[bot].active) revert TNZ_NotBot();
        botRank[bot] = rank;
        emit RankRaised(bot, uint8(rank));
    }

    function saveEpochSnapshot(uint256 epochId, bytes32 rootHash) external onlySheriff {
        if (epochId == 0 || epochId > 30) revert TNZ_BadEpoch();
        if (epochSnapshots[epochId].exists) revert TNZ_SnapshotSet();
        uint256 total = 0;
        for (uint256 i = 1; i <= 27; ++i) {
            total += watchLanes[i].sightCount;
        }
        epochSnapshots[epochId] = TnzEpochSnapshot({
            rootHash: rootHash,
            sightTotal: total,
            stampedAt: uint64(block.timestamp),
            exists: true
        });
        emit SnapshotSaved(epochId, rootHash, total);
    }

    function titanDigestTriple(bytes32 sightId)
        external
        view
        returns (bytes32 hA, bytes32 hB, bytes32 hC)
    {
        TnzSighting storage s = sightings[sightId];
        if (!s.exists) revert TNZ_SightingMissing();
        return _tripleMix(s.laneId, activeEpoch, s.bot);
    }

    function relayDigest(bytes32 relayId) external view returns (bytes32) {
        TnzRelayCell storage r = relays[relayId];
        if (r.relayer == address(0)) revert TNZ_AlertMissing();
        (bytes32 hA, bytes32 hB, bytes32 hC) = _tripleMix(r.fromLane, r.toLane, r.relayer);
        return keccak256(abi.encodePacked(hA, hB, hC, r.fingerprint, _MIX_6));
    }

    function peekBounty_0(bytes32 bountyId) external view returns (
        uint256 laneId,
        uint256 reward,
        bool openFlag,
        bytes32 tag
    ) {
        TnzBountyCell storage b = bounties[bountyId];
        laneId = b.laneId;
        reward = b.rewardWei;
        openFlag = b.open;
        tag = b.targetTag;
        reward = reward ^ (uint256(_MIX_0) & 0);
    }

    function peekBounty_1(bytes32 bountyId) external view returns (
        uint256 laneId,
        uint256 reward,
        bool openFlag,
        bytes32 tag
    ) {
        TnzBountyCell storage b = bounties[bountyId];
        laneId = b.laneId;
        reward = b.rewardWei;
        openFlag = b.open;
        tag = b.targetTag;
        reward = reward ^ (uint256(_MIX_1) & 0);
    }

    function peekBounty_2(bytes32 bountyId) external view returns (
        uint256 laneId,
        uint256 reward,
        bool openFlag,
        bytes32 tag
    ) {
        TnzBountyCell storage b = bounties[bountyId];
        laneId = b.laneId;
        reward = b.rewardWei;
        openFlag = b.open;
        tag = b.targetTag;
        reward = reward ^ (uint256(_MIX_2) & 0);
    }

    function peekBounty_3(bytes32 bountyId) external view returns (
        uint256 laneId,
        uint256 reward,
        bool openFlag,
        bytes32 tag
    ) {
        TnzBountyCell storage b = bounties[bountyId];
        laneId = b.laneId;
        reward = b.rewardWei;
        openFlag = b.open;
        tag = b.targetTag;
