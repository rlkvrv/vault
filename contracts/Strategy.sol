//SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/IVault.sol";
import "./interfaces/ICErc20.sol";
import "./interfaces/IComptroller.sol";
import "./interfaces/ICompToken.sol";
import "./interfaces/IUniswapRouter.sol";
import "./interfaces/IStrategy.sol";

import "hardhat/console.sol";

contract Strategy is Pausable {
    using SafeERC20 for ERC20;

    IComptroller compotroller =
        IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    ICompToken compToken =
        ICompToken(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    IUniswapRouter uniswapRouter =
        IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    IVault public vault;
    ERC20 public want;
    ICErc20 public cToken;
    address public strategist;
    address public keeper;
    address public vaultAddr;
    address public strategyAddr;
    uint256 public totalProtocolDebt;
    uint256 public lastReport;
    uint256 public reportDelay = 86400;
    bool public emergencyExit;

    constructor(address _vault, address _cErc20Contract) {
        _initialize(_vault, msg.sender, msg.sender, _cErc20Contract);
    }

    event UpdatedStrategist(address newStrategist);

    event UpdatedKeeper(address newKeeper);

    event UpdatedReportDelay(uint256 delay);

    event Harvested(
        uint256 profit,
        uint256 rewardsProfit,
        uint256 loss,
        uint256 debtOutstanding,
        uint256 debtPaymant
    );

    event StrategyPaused(uint256 strategyWantToken);

    event StrategyUnpaused(uint256 strategyCToken);

    event EmergencyExitEnabled();

    modifier onlyAuthorized() {
        require(msg.sender == strategist);
        _;
    }

    modifier onlyKeepers() {
        require(msg.sender == keeper || msg.sender == strategist);
        _;
    }

    modifier onlyVault() {
        require(msg.sender == vaultAddr, "Strategy: !vault");
        _;
    }

    function _initialize(
        address _vault,
        address _strategist,
        address _keeper,
        address _cErc20Contract
    ) internal {
        require(address(want) == address(0), "Strategy already initialized");

        vault = IVault(_vault);
        vaultAddr = _vault;
        want = ERC20(vault.token());
        cToken = ICErc20(_cErc20Contract);

        SafeERC20.safeApprove(want, _vault, type(uint256).max);
        strategist = _strategist;
        keeper = _keeper;

        strategyAddr = address(this);
    }

    function getVaultAddr() external view returns (address) {
        return vaultAddr;
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

    function setReportDelay(uint256 _delay) external onlyAuthorized {
        reportDelay = _delay;
        emit UpdatedReportDelay(_delay);
    }

    function getLastReport()
        external
        view
        returns (uint256 _lastReport, uint256 _delay)
    {
        _lastReport = lastReport;
        _delay = reportDelay;
    }

    function withdraw(uint256 _amount)
        external
        onlyVault
        returns (
            uint256 _userAssets,
            uint256 _userProfit,
            uint256 _userLoss
        )
    {
        uint256 amountFreed = want.balanceOf(strategyAddr);

        if (amountFreed >= _amount) {
            // If there is enough want token in the strategy, we transfer funds
            want.safeTransfer(msg.sender, _amount);
        } else {
            // Otherwise, we ask the protocol for the missing funds
            uint256 _protocolDebt = _amount - amountFreed;
            uint256 profit;
            uint256 loss;
            (profit, loss) = prepareReturn(totalProtocolDebt);

            _userProfit = (_protocolDebt * profit) / totalProtocolDebt;
            _userLoss = (_protocolDebt * loss) / totalProtocolDebt;

            uint256 _amountRequired = _userLoss > 0
                ? _protocolDebt - _userLoss
                : _protocolDebt + _userProfit;

            _liquidatePosition(_amountRequired);

            // Now the strategy has enough funds to send
            // taking into account current profit/loss
            _userAssets = _amount + _userProfit - _userLoss;
            want.safeTransfer(vaultAddr, _userAssets);
        }
    }

    function pauseWork() external onlyAuthorized {
        _pause();

        uint256 amountFreed;
        uint256 rewardsProfit;
        (amountFreed, rewardsProfit) = _liquidateAllPositions();

        emit StrategyPaused(amountFreed + rewardsProfit);
    }

    function unpauseWork() external onlyAuthorized {
        _unpause();

        uint256 mintResult = adjustPosition();

        emit StrategyUnpaused(mintResult);
    }

    function setEmergencyExit() external onlyAuthorized {
        emergencyExit = true;

        emit EmergencyExitEnabled();
    }

    function harvest() external onlyKeepers whenNotPaused {
        require(
            ((block.timestamp - lastReport) >= reportDelay),
            "Strategy: harvest: Time not elapsed"
        );

        uint256 profit;
        uint256 loss;
        uint256 debtOutstanding = vault.debtOutstanding(strategyAddr);
        uint256 compTokenAmount = _claimRewards();
        uint256 rewardsProfit;
        uint256 debtPayment = 0;

        if (emergencyExit) {
            uint256 amountFreed;
            (amountFreed, rewardsProfit) = _liquidateAllPositions();

            if (amountFreed < debtOutstanding) {
                loss = debtOutstanding - amountFreed;
            } else if (amountFreed > debtOutstanding) {
                profit = amountFreed - debtOutstanding;
            }
            debtPayment = debtOutstanding - loss;
        } else {
            (profit, loss) = prepareReturn(debtOutstanding);

            if (compTokenAmount > 1 * 10**18) {
                rewardsProfit = _swapRewardsToWantToken(compTokenAmount);
            }
        }

        debtOutstanding = vault.report(
            profit + rewardsProfit,
            loss,
            debtPayment
        );
        lastReport = block.timestamp;

        adjustPosition();

        emit Harvested(
            profit,
            rewardsProfit,
            loss,
            debtOutstanding,
            debtPayment
        );
    }

    function migrate(address _newStrategy) external onlyVault {
        require(IStrategy(_newStrategy).getVaultAddr() == vaultAddr);

        _pause();
        _liquidateAllPositions();

        SafeERC20.safeTransfer(
            want,
            _newStrategy,
            want.balanceOf(address(this))
        );
    }

    function adjustPosition() internal returns (uint256 mintResult) {
        uint256 currentBalance = want.balanceOf(strategyAddr);
        want.approve(address(cToken), currentBalance);

        totalProtocolDebt += currentBalance;
        cToken.mint(currentBalance);
        mintResult = cToken.balanceOfUnderlying(strategyAddr);
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        returns (uint256 _profit, uint256 _loss)
    {
        uint256 underlyingBal = cToken.balanceOfUnderlying(strategyAddr);

        if (underlyingBal > _debtOutstanding) {
            _profit = underlyingBal - _debtOutstanding;
        } else if (_debtOutstanding > underlyingBal) {
            _loss = _debtOutstanding - underlyingBal;
        }
    }

    function _liquidatePosition(uint256 amount) private {
        require(
            cToken.balanceOfUnderlying(strategyAddr) >= amount,
            "Strategy: insufficienty balance"
        );

        if (totalProtocolDebt < amount) {
            totalProtocolDebt = 0;
        } else {
            totalProtocolDebt -= amount;
        }

        cToken.redeemUnderlying(amount);
    }

    function _liquidateAllPositions()
        private
        returns (uint256 amountFreed, uint256 rewardsProfit)
    {
        cToken.redeem(cToken.balanceOf(strategyAddr));
        totalProtocolDebt = cToken.balanceOfUnderlying(strategyAddr);

        uint256 compTokenAmount = _claimRewards();
        amountFreed = want.balanceOf(strategyAddr);

        if (compTokenAmount > 0) {
            rewardsProfit = _swapRewardsToWantToken(compTokenAmount);
        }
    }

    function _claimRewards() private returns (uint256 rewards) {
        compotroller.claimComp(strategyAddr);
        rewards = compToken.balanceOf(strategyAddr);
    }

    function _swapRewardsToWantToken(uint256 amountIn)
        private
        returns (uint256 profit)
    {
        compToken.approve(address(uniswapRouter), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(compToken);
        path[1] = address(want);
        uint256 amountOutMin = uniswapRouter.getAmountsOut(amountIn, path)[1];

        uint256 balanceBefore = want.balanceOf(strategyAddr);

        uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            strategyAddr,
            block.timestamp + 1
        );

        uint256 balanceAfter = want.balanceOf(strategyAddr);
        profit = balanceAfter > balanceBefore
            ? balanceAfter - balanceBefore
            : 0;
    }
}
