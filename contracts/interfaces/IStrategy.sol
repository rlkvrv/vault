// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IStrategy {
    function withdraw(uint256 _amountNeeded) external returns (uint256 _loss);
}
