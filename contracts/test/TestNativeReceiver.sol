// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

contract TestNativeReceiver {
    constructor() {}

    receive() external payable {
        revert();
    }
}
