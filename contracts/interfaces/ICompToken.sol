// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface ICompToken {
    function balanceOf(address owner) external view returns (uint256);

    function getCurrentVotes(address account) external returns (uint96);

    function approve(address spender, uint256 rawAmount)
        external
        returns (bool);
}
