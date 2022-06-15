// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IStrategy {
    function withdraw(uint256 _amountNeeded)
        external
        returns (
            uint256 _userAssets,
            uint256 _userProfit,
            uint256 _userLoss
        );

    function harvest() external;

    function getLastReport()
        external
        view
        returns (uint256 _lastReport, uint256 _delay);

    function getVaultAddr() external view returns (address);

    function pauseWork() external;
}
