// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ISuperfluid, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IcfaV1Forwarder} from "./IcfaV1Forwarder.sol";

interface IPool {
    struct ClaimedData {
        int96 claimedRate;
        uint256 numStreams;
    }

    event PoolCreated(
        string name,
        address creator,
        address indexed nft,
        address indexed superToken,
        uint96 ratePerNFT
    );
    event PoolActivated();
    event PoolDeactivated();
    event PoolRateChanged(int96 oldRatePerNFT, int96 newRatePerNFT);
    event PoolToppedUp(address indexed superToken, uint256 amount);
    event StreamsClaimed(
        address indexed claimant,
        int96 oldStreamRate,
        int96 newStreamRate
    );
    event StreamClaimedById(address indexed claimant, uint256 tokenId);
    event StreamsAdjusted(
        address indexed holder,
        int96 oldRatePerNFT,
        int96 newRatePerNFT
    );
    event StreamsReinstated(
        address indexed holder,
        int96 numStreams,
        int96 newOutStreamRate,
        int96 ratePerNFT
    );
    event EmergencyCloseInitiated(address indexed holder);
    event PoolDrained(address indexed streamToken, uint256 drainAmount);

    error ZeroAddress();
    error TransferFailed();
    error BulkClaimsPaused();
    error PoolExists();
    error PoolNotFound();
    error PoolActive();
    error PoolInactive();
    error NotPoolCreator();
    error IneligibleClaim();
    error NotHost(address terminator);
    error SamePoolRate(int96 ratePerNFT);
    error SameClaimRate(int96 ratePerNFT);
    error NotOwnerOfNFT(uint256 tokenId);
    error StreamAlreadyClaimed(uint256 tokenId);
    error StreamNotFound(uint256 tokenId);
    error HolderStreamsNotFound(address holder);
    error WrongStreamCloseAttempt(uint256 tokenId, address terminator);
    error StreamsAdjustmentsFailed(address prevHolder, address currHolder);
    error StreamAdjustmentFailedInReinstate(address prevHolder);
    error StreamsAlreadyReinstated(address prevHolder);
    error NoEmergency(address terminator);
    error PoolMinAmountLimit(
        uint256 remainingAmount,
        uint256 minAmountRequried
    );
    error PoolBalanceInsufficient(
        uint256 currPoolBalance,
        uint256 reqPoolBalance
    );

    function tokenIdHolders(uint256 tokenId) external returns (address holder);

    function initialize(
        string memory name,
        address host,
        address creator,
        uint96 ratePerNFT,
        IcfaV1Forwarder cfaV1Forwarder,
        IERC721 nft,
        ISuperToken streamToken
    ) external;

    function claimStream(uint256 tokenId) external;

    function reinstateStreams(address prevHolder) external;

    function topUpPool(uint256 amount) external;

    function drainPool(uint256 amount) external;

    function closeStream(uint256 tokenId) external;

    function emergencyCloseStreams(address holder) external;

    function adjustCurrentStreams(address holder) external;

    function changeRate(uint96 newRatePerNFT) external;

    function activatePool() external;

    function deactivatePool() external;

    function isCritical() external view returns (bool status);
}
