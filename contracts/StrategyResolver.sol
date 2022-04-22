// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {OpsReady} from "./interfaces/OpsReady.sol";

import "./interfaces/IOps.sol";
import "./interfaces/IStrategy.sol";

import "hardhat/console.sol";

contract StrategyResolver is OpsReady {
    address public immutable STRATEGY;

    constructor(address _strategy, address payable _ops) OpsReady(_ops) {
        STRATEGY = _strategy;
    }

    function startTask() external {
        IOps(ops).createTask(
            STRATEGY,
            IStrategy.harvest.selector,
            address(this),
            abi.encodeWithSelector(this.checker.selector)
        );
    }

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        uint256 lastReport;
        uint256 reportDelay;
        (lastReport, reportDelay) = IStrategy(STRATEGY).getLastReport();

        canExec = (block.timestamp - lastReport) > reportDelay;

        execPayload = abi.encodeWithSelector(IStrategy.harvest.selector);
    }
}
