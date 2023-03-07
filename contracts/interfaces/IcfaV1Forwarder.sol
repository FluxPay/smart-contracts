// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ISuperfluid, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

interface IcfaV1Forwarder {

    function setFlowrate(
        ISuperToken token,
        address receiver,
        int96 flowrate
    ) external returns (bool);

    function getFlowrate(
        ISuperToken token,
        address sender,
        address receiver
    ) external view returns (int96 flowrate);

   function getFlowInfo(
        ISuperToken token,
        address sender,
        address receiver
    )
        external
        view
        returns (
            uint256 lastUpdated,
            int96 flowrate,
            uint256 deposit,
            uint256 owedDeposit
        );

   function getBufferAmountByFlowrate(ISuperToken token, int96 flowrate)
        external
        view
        returns (uint256 bufferAmount);

   function getAccountFlowrate(ISuperToken token, address account)
        external
        view
        returns (int96 flowrate);

   function getAccountFlowInfo(ISuperToken token, address account)
        external
        view
        returns (
            uint256 lastUpdated,
            int96 flowrate,
            uint256 deposit,
            uint256 owedDeposit
        );

   function createFlow(
        ISuperToken token,
        address sender,
        address receiver,
        int96 flowrate,
        bytes memory userData
    ) external returns (bool);

   function updateFlow(
        ISuperToken token,
        address sender,
        address receiver,
        int96 flowrate,
        bytes memory userData
    ) external returns (bool);

   function deleteFlow(
        ISuperToken token,
        address sender,
        address receiver,
        bytes memory userData
    ) external returns (bool);
}
