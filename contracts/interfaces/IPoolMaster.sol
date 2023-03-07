// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ISuperfluid, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IcfaV1Forwarder} from "./IcfaV1Forwarder.sol";

interface IPoolMaster {
    event ImplementationChanged(
        address oldImplementation,
        address newImplementation
    );
    event PoolCreated(
        string name,
        address creator,
        address indexed pool,
        address indexed nft,
        address indexed superToken
    );

    error ZeroAddress();
    error SameImplementationAddress();
    error PoolExists(string name);
    error TransferFailed(address superToken, uint256 amount);

   function createPool(
        string memory name,
        uint96 ratePerNFT,
        IERC721 nft,
        ISuperToken superToken
    ) external returns (address newPool);

    function Pools(string memory name) external view returns (address pool);

    function CFA_V1_FORWARDER()
        external
        view
        returns (IcfaV1Forwarder forwarder);

    function HOST() external view returns (ISuperfluid host);

    function implementation()
        external
        view
        returns (address poolImplementation);
}
