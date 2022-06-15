// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./interfaces/IOps.sol";
import "./interfaces/IStrategy.sol";

import "hardhat/console.sol";

contract StrategyResolver {
    address public immutable STRATEGY;
    address public immutable ops;

    constructor(address _strategy, address _ops) {
        ops = _ops;
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
