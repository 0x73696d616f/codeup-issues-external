// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import {Codeup} from "../Codeup.sol";

contract TestFactory {
    Codeup private codeup;

    constructor() {}

    function setCodeup(address _codeup) external {
        codeup = Codeup(_codeup);
    }
}
