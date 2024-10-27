// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import {Codeup} from "../Codeup.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract TestReentrancy {
    Codeup private codeup;

    constructor(address _codeup) {
        codeup = Codeup(_codeup);
    }

    function addTokens() external payable {
        codeup.addGameETH{value: msg.value}();
    }

    function upgrade(uint256 floorID) external {
        codeup.upgradeTower(floorID);
    }

    function collect() external {
        codeup.collect();
    }
}

contract WithdrawReentrance is TestReentrancy {
    Codeup private codeup;

    constructor(address _codeup) TestReentrancy(_codeup) {
        codeup = Codeup(_codeup);
    }

    function withdraw() external {
        codeup.withdraw();
    }

    receive() external payable {
        codeup.withdraw();
    }
}

contract ReinvestReentrancy is ERC20 {
    Codeup private codeup;
    uint256 counter;

    constructor() ERC20("Weth", "WETH") {}

    function deposit() external payable {
        if (counter == 0) {
            _mint(msg.sender, msg.value);
            counter++;
        } else {
            codeup.reinvest();
        }
    }

    function updateCodeUp(address _codeup) external {
        codeup = Codeup(_codeup);
    }

    function reinvest() external {
        codeup.reinvest();
    }

    receive() external payable {}
}

contract ClaimCodeupERC20Reentrancy is ERC20 {
    Codeup private codeup;

    constructor() ERC20("Weth", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function setCodeup(address _codeup) external {
        codeup = Codeup(_codeup);
    }

    function claimCodeupERC20() external {
        codeup.claimCodeupERC20(address(this), 0, 0, 0);
    }

    receive() external payable {
        codeup.claimCodeupERC20(address(this), 0, 0, 0);
    }
}
