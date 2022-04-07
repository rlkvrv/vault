//SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IVault.sol";
import "hardhat/console.sol";

contract Strategy {
    using SafeERC20 for ERC20;

    IVault public vault;
    IERC20 public want;
    address public strategist;
    address public keeper;

    constructor(address _vault) {
        _initialize(_vault, msg.sender, msg.sender);
    }

    event UpdatedStrategist(address newStrategist);

    event UpdatedKeeper(address newKeeper);

    event Harvested(
        uint256 profit,
        uint256 loss,
        uint256 debtPayment,
        uint256 debtOutstanding
    );

    modifier onlyAuthorized() {
        require(msg.sender == strategist);
        _;
    }

    function _initialize(
        address _vault,
        address _strategist,
        address _keeper
    ) internal {
        require(address(want) == address(0), "Strategy already initialized");

        vault = IVault(_vault);
        want = ERC20(vault.token());
        // SafeERC20.safeApprove(want, _vault, type(uint256).max); // Give Vault unlimited access (might save gas)
        strategist = _strategist;
        keeper = _keeper;

        // initialize variables
        // minReportDelay = 0;
        // maxReportDelay = 86400;
        // profitFactor = 100;
        // debtThreshold = 0;

        // vault.approve(rewards, type(uint256).max); // Allow rewards to be pulled
    }

    function setStrategist(address _strategist) external onlyAuthorized {
        require(_strategist != address(0));
        strategist = _strategist;
        emit UpdatedStrategist(_strategist);
    }

    function setKeeper(address _keeper) external onlyAuthorized {
        require(_keeper != address(0));
        keeper = _keeper;
        emit UpdatedKeeper(_keeper);
    }
}
