// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IComptroller {
    function claimComp(address holder) external;
}
