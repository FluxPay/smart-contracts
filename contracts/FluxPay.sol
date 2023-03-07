// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

contract FluxPay {
    struct Dao {
        address owner;
        string title;
        string description;
        string image;
        address poolAddress;
        address currency;
    }

    mapping(uint256 => Dao) public daos;

    uint256 public numberOfDaos = 0;

    function createDao(
        address _owner,
        string memory _title,
        string memory _description,
        string memory _image,
        address _currency
    ) public returns (uint256) {
        Dao storage dao = daos[numberOfDaos];

        dao.owner = _owner;
        dao.title = _title;
        dao.description = _description;
        dao.image = _image;
        dao.currency = _currency;

        numberOfDaos++;

        return numberOfDaos - 1;
    }

    function setPoolAddress(uint256 _id, address _poolAddress) public {
        require(
            daos[_id].owner == msg.sender,
            "Only DAO owner can set the pool address"
        );
        daos[_id].poolAddress = _poolAddress;
    }

    function getDaos() public view returns (Dao[] memory) {
        Dao[] memory allDaos = new Dao[](numberOfDaos);

        for (uint256 i = 0; i < numberOfDaos; i++) {
            Dao storage item = daos[i];

            allDaos[i] = item;
        }

        return allDaos;
    }
}
