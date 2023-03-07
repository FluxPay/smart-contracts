// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ISuperfluid, ISuperApp, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/Definitions.sol";
import {IcfaV1Forwarder} from "./interfaces/IcfaV1Forwarder.sol";
import {IERC20Mod} from "./interfaces/IERC20Mod.sol";
import {IPoolMaster} from "./interfaces/IPoolMaster.sol";
import {IPool} from "./interfaces/IPool.sol";

contract PoolMaster is Ownable, IPoolMaster {
    IcfaV1Forwarder public immutable CFA_V1_FORWARDER;
    ISuperfluid public immutable HOST;
    address public implementation;

    uint256 private constant CONFIG_WORD =
        SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.APP_LEVEL_FINAL;

    mapping(string => address) public Pools;

    constructor(
        IcfaV1Forwarder _cfaV1Forwarder,
        ISuperfluid _host,
        address _implementation
    ) {
        if (
            address(_cfaV1Forwarder) == address(0) ||
            address(_host) == address(0) ||
            address(_implementation) == address(0)
        ) revert ZeroAddress();

        CFA_V1_FORWARDER = _cfaV1Forwarder;
        HOST = _host;
        implementation = _implementation;
    }

    function setImplementation(address _newImplementation) external onlyOwner {
        if (_newImplementation == address(0)) revert ZeroAddress();

        address oldImplementation = implementation;

        if (oldImplementation == _newImplementation)
            revert SameImplementationAddress();

        implementation = _newImplementation;

        emit ImplementationChanged(oldImplementation, _newImplementation);
    }

    function createPool(
        string memory _name,
        uint96 _ratePerNFT,
        IERC721 _nft,
        ISuperToken _streamToken
    ) external returns (address _newPool) {
        if (address(_nft) == address(0) || address(_streamToken) == address(0))
            revert ZeroAddress();

        if (Pools[_name] != address(0)) revert PoolExists(_name);

        _newPool = Clones.clone(implementation);
        Pools[_name] = _newPool;

        IPool(_newPool).initialize(
            _name,
            address(HOST),
            msg.sender,
            _ratePerNFT,
            CFA_V1_FORWARDER,
            _nft,
            _streamToken
        );

        HOST.registerAppByFactory(ISuperApp(_newPool), CONFIG_WORD);

        emit PoolCreated(
            _name,
            msg.sender,
            _newPool,
            address(_nft),
            address(_streamToken)
        );
    }
}
