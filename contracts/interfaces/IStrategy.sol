// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IStrategy {
    function withdraw(uint256 _amountNeeded)
        external
        returns (
            uint256 _userAssets,
            uint256 _userProfit,
            uint256 _userLoss
        );

    function harvest() external;

    function getLastReport() external view returns (uint _lastReport, uint _delay);
}
