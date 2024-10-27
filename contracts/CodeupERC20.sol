// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CodeupERC20 is ERC20, Ownable {
    uint256 private constant _MAX_SUPPLY = 1000000000 ether;

    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol
    ) payable ERC20(_name, _symbol) Ownable(_initialOwner) {
        _mint(_initialOwner, _MAX_SUPPLY);
    }
}
