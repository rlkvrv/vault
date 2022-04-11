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

    modifier onlyKeepers() {
        require(msg.sender == keeper || msg.sender == strategist);
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
        SafeERC20.safeApprove(want, _vault, type(uint256).max);
        strategist = _strategist;
        keeper = _keeper;

        // initialize variables
        // minReportDelay = 0;
        // maxReportDelay = 86400;
        // profitFactor = 100;
        // debtThreshold = 0;
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

    function withdraw(uint256 _amountNeeded) external returns (uint256 _loss) {
        // console.log(address(vault));
        // require(msg.sender == address(vault), "Strategy: !vault");
        // Liquidate as much as possible to `want`, up to `_amountNeeded`
        uint256 amountFreed = want.balanceOf(address(this)); // TODO
        // (amountFreed, _loss) = liquidatePosition(_amountNeeded);
        // Send it directly back (NOTE: Using `msg.sender` saves some gas here)
        if (amountFreed >= _amountNeeded) {
            SafeERC20.safeTransfer(want, msg.sender, _amountNeeded);
        }
        // NOTE: Reinvest anything leftover on next `tend`/`harvest`
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {}

    function harvest() external onlyKeepers {
        uint256 profit;
        uint256 loss;
        uint256 debtOutstanding = vault.debtOutstanding(address(this));
        uint256 debtPayment;

        (profit, loss, debtPayment) = prepareReturn(debtOutstanding);

        // Allow Vault to take up to the "harvested" balance of this contract,
        // which is the amount it has earned since the last time it reported to
        // the Vault.
        debtOutstanding = vault.report(profit, loss, debtPayment);

        // Check if free returns are left, and re-invest them
        // adjustPosition(debtOutstanding);

        emit Harvested(profit, loss, debtPayment, debtOutstanding);
    }
}
