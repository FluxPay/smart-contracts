// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IcfaV1Forwarder, ISuperToken, ISuperfluid} from "./interfaces/IcfaV1Forwarder.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IPool} from "./interfaces/IPool.sol";

contract Pool is Initializable, IPool, SuperAppBase {
    using SafeCast for *;

    address public HOST;
    address public CREATOR;
    ISuperToken public STREAM_TOKEN;
    IERC721 public NFT;

    string public name;

    bool public active;

    int96 public ratePerNFT;

    IcfaV1Forwarder internal CFA_V1_FORWARDER;

    mapping(uint256 => address) public tokenIdHolders;

    mapping(address => ClaimedData) private claimedStreams;

    function initialize(
        string memory _name,
        address _host,
        address _creator,
        uint96 _ratePerNFT,
        IcfaV1Forwarder _cfaV1Forwarder,
        IERC721 _nft,
        ISuperToken _streamToken
    ) external initializer {
        HOST = _host;
        CFA_V1_FORWARDER = _cfaV1Forwarder;
        STREAM_TOKEN = _streamToken;
        CREATOR = _creator;
        NFT = _nft;
        ratePerNFT = int96(_ratePerNFT);
        name = _name;

        emit PoolCreated(
            _name,
            _creator,
            address(_nft),
            address(_streamToken),
            _ratePerNFT
        );
    }

    function claimStream(uint256 _tokenId) external {
        if (!active) revert PoolInactive();

        IERC721 nft = NFT;
        if (nft.ownerOf(_tokenId) != msg.sender) revert NotOwnerOfNFT(_tokenId);

        address prevHolder = tokenIdHolders[_tokenId];

        if (prevHolder == msg.sender) revert StreamAlreadyClaimed(_tokenId);

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;
        int96 cachedRatePerNFT = ratePerNFT;

        int96 prevHolderOldStreamRate;
        int96 prevHolderNewStreamRate;

        if (prevHolder != address(0)) {
            prevHolderOldStreamRate = claimedStreams[prevHolder].claimedRate;
            prevHolderNewStreamRate = _calcPrevHolderStreams(
                prevHolder,
                prevHolderOldStreamRate,
                cachedRatePerNFT
            );

            --claimedStreams[prevHolder].numStreams;
        }

        int96 currHolderOldStreamRate = claimedStreams[msg.sender].claimedRate;

        int96 currHolderNewStreamRate = _calcCurrHolderStreams(
            msg.sender,
            currHolderOldStreamRate,
            cachedRatePerNFT
        );

        int96 deltaStreamRate = (prevHolderNewStreamRate +
            currHolderNewStreamRate) -
            (prevHolderOldStreamRate + currHolderOldStreamRate);

       if (!_canAdjustStreams(forwarder, streamToken, deltaStreamRate))
            revert StreamsAdjustmentsFailed(prevHolder, msg.sender);

        if (prevHolderOldStreamRate != int96(0)) {
            claimedStreams[prevHolder].claimedRate = cachedRatePerNFT;

            forwarder.setFlowrate(
                streamToken,
                prevHolder,
                prevHolderNewStreamRate
            );
        }

        tokenIdHolders[_tokenId] = msg.sender;

        ++claimedStreams[msg.sender].numStreams;

        if (claimedStreams[msg.sender].claimedRate != cachedRatePerNFT) {
            claimedStreams[msg.sender].claimedRate = cachedRatePerNFT;
        }

        forwarder.setFlowrate(streamToken, msg.sender, currHolderNewStreamRate);

        emit StreamClaimedById(msg.sender, _tokenId);
    }

    function reinstateStreams(address _prevHolder) external {
        if (!active) revert PoolInactive();

        if (claimedStreams[_prevHolder].claimedRate != int96(0))
            revert StreamsAlreadyReinstated(_prevHolder);

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;

        int96 cachedRatePerNFT = ratePerNFT;
        int96 numStreams = (claimedStreams[_prevHolder].numStreams)
            .toInt256()
            .toInt96();

        if (numStreams == 0) revert HolderStreamsNotFound(_prevHolder);

        int96 deltaStreamRate = numStreams * cachedRatePerNFT;

        if (!_canAdjustStreams(forwarder, streamToken, deltaStreamRate))
            revert StreamAdjustmentFailedInReinstate(_prevHolder);

        claimedStreams[_prevHolder].claimedRate = cachedRatePerNFT;

        forwarder.setFlowrate(streamToken, _prevHolder, deltaStreamRate);

        emit StreamsReinstated(
            _prevHolder,
            numStreams,
            deltaStreamRate,
            cachedRatePerNFT
        );
    }

    function topUpPool(uint256 _amount) external {
        if (CREATOR != msg.sender) revert NotPoolCreator();

        ISuperToken streamToken = STREAM_TOKEN;

        if (!streamToken.transferFrom(msg.sender, address(this), _amount))
            revert TransferFailed();

        emit PoolToppedUp(address(streamToken), _amount);
    }

    function drainPool(uint256 _amount) external {
        if (CREATOR != msg.sender) revert NotPoolCreator();

        ISuperToken streamToken = STREAM_TOKEN;
        uint256 currPoolBalance = streamToken.balanceOf(address(this));

        if (_amount == type(uint256).max) _amount = currPoolBalance;
        else if (currPoolBalance < _amount)
            revert PoolBalanceInsufficient(currPoolBalance, _amount);

        if (!streamToken.transfer(msg.sender, _amount)) revert TransferFailed();

        emit PoolDrained(address(streamToken), _amount);
    }

    function closeStream(uint256 _tokenId) external {
        address prevHolder = tokenIdHolders[_tokenId];

        if (
            prevHolder == address(0) ||
            claimedStreams[prevHolder].numStreams == 0
        ) revert StreamNotFound(_tokenId);

        ISuperToken streamToken = STREAM_TOKEN;
        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        address tokenHolder = NFT.ownerOf(_tokenId);

        if (tokenHolder == msg.sender || CREATOR == msg.sender) {
            int96 prevHolderOldStreamRate = forwarder.getFlowrate(
                streamToken,
                address(this),
                prevHolder
            );
            int96 prevHolderPerIdRate = claimedStreams[prevHolder].claimedRate;
            int96 newOutStreamRate = _calcPrevHolderStreams(
                prevHolder,
                prevHolderPerIdRate,
                ratePerNFT
            );

            delete tokenIdHolders[_tokenId];
            --claimedStreams[prevHolder].numStreams;

            if (
                claimedStreams[prevHolder].numStreams == 0 &&
                claimedStreams[prevHolder].claimedRate != 0
            ) claimedStreams[prevHolder].claimedRate = 0;

            if (
                prevHolderOldStreamRate > newOutStreamRate ||
                (prevHolderOldStreamRate < newOutStreamRate &&
                    _canAdjustStreams(
                        forwarder,
                        streamToken,
                        newOutStreamRate - prevHolderOldStreamRate
                    ))
            ) {
                forwarder.setFlowrate(
                    streamToken,
                    prevHolder,
                    newOutStreamRate
                );
            } else {
                forwarder.setFlowrate(
                    streamToken,
                    prevHolder,
                    prevHolderOldStreamRate - prevHolderPerIdRate
                );
            }
        } else {
            revert WrongStreamCloseAttempt(_tokenId, msg.sender);
        }
    }

    function emergencyCloseStreams(address _holder) external {
        if (msg.sender != CREATOR && !isCritical()) {
            revert NoEmergency(msg.sender);
        }
        if (active) active = false;
        delete claimedStreams[_holder].claimedRate;

        CFA_V1_FORWARDER.setFlowrate(STREAM_TOKEN, _holder, int96(0));

        emit EmergencyCloseInitiated(_holder);
    }

    function adjustCurrentStreams(address _holder) external {
        if (!active) revert PoolInactive();

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;
        int96 cachedRatePerNFT = ratePerNFT;
        int96 currHolderOldStreamRate = forwarder.getFlowrate(
            streamToken,
            address(this),
            _holder
        );

        if (currHolderOldStreamRate == int96(0))
            revert HolderStreamsNotFound(_holder);

        int96 oldClaimedRate = claimedStreams[_holder].claimedRate;

        if (oldClaimedRate == cachedRatePerNFT)
            revert SameClaimRate(cachedRatePerNFT);

        // Calculate number of streams going to the holder.
        int96 numStreams = currHolderOldStreamRate / oldClaimedRate;

        claimedStreams[_holder].claimedRate = cachedRatePerNFT;

        forwarder.setFlowrate(
            streamToken,
            _holder,
            numStreams * cachedRatePerNFT
        );

        emit StreamsAdjusted(_holder, oldClaimedRate, cachedRatePerNFT);
    }

    function changeRate(uint96 _newRatePerNFT) external {
       if (CREATOR != msg.sender) revert NotPoolCreator();

        int96 oldRatePerNFT = ratePerNFT;
        int96 newRatePerNFT = int96(_newRatePerNFT);

        if (oldRatePerNFT == newRatePerNFT) revert SamePoolRate(newRatePerNFT);

        ratePerNFT = int96(_newRatePerNFT);

        emit PoolRateChanged(oldRatePerNFT, newRatePerNFT);
    }

    function activatePool() external {
        if (CREATOR != msg.sender) revert NotPoolCreator();
        if (active == true) revert PoolActive();

        active = true;

        emit PoolActivated();
    }

    function deactivatePool() external {
        if (CREATOR != msg.sender) revert NotPoolCreator();
        if (active == false) revert PoolInactive();

        active = false;

        emit PoolDeactivated();
    }

    function isCritical() public view returns (bool _status) {
        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;

        int96 outStreamRate = forwarder.getAccountFlowrate(
            streamToken,
            address(this)
        );

        if (outStreamRate >= 0) return false;

        uint256 currPoolBalance = streamToken.balanceOf(address(this));

        uint256 reqPoolBalance = (-1 * outStreamRate * 1 days).toUint256();

        if (currPoolBalance >= reqPoolBalance) return false;

        return true;
    }

    function _calcCurrHolderStreams(
        address _currHolder,
        int96 _currHolderPerIdRate,
        int96 _cachedRatePerNFT
    ) internal view returns (int96 _currHolderNewStreamRate) {
        if (_currHolderPerIdRate != int96(0)) {
            _currHolderNewStreamRate =
                ((claimedStreams[_currHolder].numStreams).toInt256().toInt96() +
                    1) *
                _cachedRatePerNFT;
        } else {
            return _cachedRatePerNFT;
        }
    }

    function _calcPrevHolderStreams(
        address _prevHolder,
        int96 _prevHolderPerIdRate,
        int96 _cachedRatePerNFT
    ) internal view returns (int96 _prevHolderNewStreamRate) {
        if (_prevHolderPerIdRate != int96(0)) {
            _prevHolderNewStreamRate =
                ((claimedStreams[_prevHolder].numStreams).toInt256().toInt96() -
                    1) *
                _cachedRatePerNFT;
        } else {
            return int96(0);
        }
    }

    function _canAdjustStreams(
        IcfaV1Forwarder _forwarder,
        ISuperToken _streamToken,
        int96 _deltaStreamRate
    ) internal view returns (bool _can) {
        int96 currNetStreamRate = _forwarder.getAccountFlowrate(
            _streamToken,
            address(this)
        );

        if (currNetStreamRate < _deltaStreamRate) {
            uint256 currPoolBalance = _streamToken.balanceOf(address(this));
            uint256 deltaBufferAmount = _forwarder.getBufferAmountByFlowrate(
                _streamToken,
                _deltaStreamRate
            );
            uint256 newReqPoolBalance = ((-1 *
                (currNetStreamRate - _deltaStreamRate)) * 1 days).toUint256();

            if ((currPoolBalance - deltaBufferAmount) < newReqPoolBalance)
                return false;
        }

        return true;
    }

    function afterAgreementTerminated(
        ISuperToken, /*_streamToken*/
        address, /*_agreementClass*/
        bytes32, /*_agreementId*/
        bytes calldata _agreementData,
        bytes calldata, /*_cbdata*/
        bytes calldata _ctx
    ) external override returns (bytes memory _newCtx) {
        if (msg.sender != HOST) revert NotHost(msg.sender);

        _newCtx = _ctx;

        (, address receiver) = abi.decode(_agreementData, (address, address));

        delete claimedStreams[receiver].claimedRate;
    }
}
