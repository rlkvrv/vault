//SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IStrategy.sol";

import "hardhat/console.sol";

contract Vault is IVault, ERC20, ReentrancyGuard {
    using SafeERC20 for ERC20;

    ERC20 public immutable asset;
    uint256 public maxStrategies = 10;
    uint256 public managementFee = 100; // 1% per year
    uint256 MAX_BPS = 10000; // min fee 0,01%
    uint256 SECS_PER_YEAR = 31556952;

    address public management;
    uint256 public totalDebt;
    address[] public withdrawalQueue;

    struct StrategyParams {
        uint256 performanceFee;
        uint256 activation;
        uint256 lastReport;
        uint256 totalDebt;
        uint256 totalGain;
        uint256 totalLoss;
    }

    mapping(address => StrategyParams) public strategies;

    constructor(ERC20 _asset) ERC20("ShareToken", "SHT") {
        asset = _asset;
        management = msg.sender;
    }

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 requestedAssets,
        uint256 receivedAssets,
        uint256 shares
    );

    event StrategyAdded(address strategy, uint256 performanceFee);

    event StrategyReported(
        address strategy,
        uint256 gain,
        uint256 loss,
        uint256 totalGain,
        uint256 totalLoss,
        uint256 totalDebt,
        uint256 credit
    );

    event UpdateManagement(address management);

    event StrategyMigrated(
        address oldVersion,
        uint256 gainOldVersion,
        uint256 lossOldVersion,
        address newVersion,
        uint256 totalDebtNewVersion
    );

    event UpdateMaxStrategies(uint256 amount);

    modifier onlyAuthorized() {
        require(msg.sender == management, "Vault: ONLY_AUTHORIZED");
        _;
    }

    function token() external view returns (address wantToken) {
        return address(asset);
    }

    function updateManagement(address _management) external onlyAuthorized {
        management = _management;

        emit UpdateManagement(management);
    }

    function updateMaxStrategies(uint256 _newAmount) external onlyAuthorized {
        maxStrategies = _newAmount;

        emit UpdateMaxStrategies(_newAmount);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256 assets) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) external view returns (uint256 shares) {
        return balanceOf(owner);
    }

    function addStrategy(address _strategy, uint256 _perfomanceFee)
        external
        onlyAuthorized
    {
        require(_strategy != address(0), "Vault: ZERO_STRATEGY");
        require(
            withdrawalQueue.length < maxStrategies,
            "Vault: ADDED_MAX_STRATEGIES"
        );

        strategies[_strategy].performanceFee = _perfomanceFee;
        strategies[_strategy].activation = block.timestamp;

        withdrawalQueue.push(_strategy);

        emit StrategyAdded(_strategy, _perfomanceFee);
    }

    function deposit(uint256 assets, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        require((shares = convertToShares(assets)) != 0, "Vault: ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver)
        external
        nonReentrant
        returns (uint256 assets)
    {
        require((assets = convertToAssets(shares)) != 0, "Vault: ZERO_ASSETS");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 requestedAssets,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 shares) {
        shares = convertToShares(requestedAssets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 userProfit;
        uint256 userLoss;

        // If there are not funds in the Vault - send request to Strategy
        if (asset.balanceOf(address(this)) < requestedAssets) {
            (userProfit, userLoss) = _withdrawFromStrategies(requestedAssets);
        }

        _burn(owner, shares);

        // If there are funds, then userProfit and userLoss will be 0
        uint256 receivedAssets = requestedAssets + userProfit - userLoss;
        asset.safeTransfer(receiver, receivedAssets);

        emit Withdraw(
            msg.sender,
            receiver,
            owner,
            requestedAssets,
            receivedAssets,
            shares
        );
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 assets) {
        require((assets = convertToAssets(shares)) != 0, "Vault: ZERO_ASSETS");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 userProfit;
        uint256 userLoss;

        if (asset.balanceOf(address(this)) < assets) {
            (userProfit, userLoss) = _withdrawFromStrategies(assets);
        }

        _burn(owner, shares);

        uint256 receivedAssets = assets + userProfit - userLoss;
        asset.safeTransfer(receiver, receivedAssets);

        emit Withdraw(
            msg.sender,
            receiver,
            owner,
            assets,
            receivedAssets,
            shares
        );
    }

    function report(
        uint256 gain,
        uint256 loss,
        uint256 debtPayment
    ) external nonReentrant returns (uint256 debt) {
        require(
            strategies[msg.sender].activation > 0,
            "Vault: ONLY_APPROVED_STRATEGY"
        );

        if (loss > 0) {
            strategies[msg.sender].totalLoss += loss;
            strategies[msg.sender].totalDebt -= loss;
            totalDebt -= loss;
        }

        if (gain > 0) {
            strategies[msg.sender].totalGain += gain;
            strategies[msg.sender].totalDebt += gain;
            totalDebt += gain;
            _assessFees(msg.sender, gain);
        }

        uint256 credit = asset.balanceOf(address(this));

        if (credit > 0 && debtPayment == 0) {
            asset.safeTransfer(msg.sender, credit);
            strategies[msg.sender].totalDebt += credit;
            totalDebt += credit;
        } else if (debtPayment > 0) {
            asset.safeTransferFrom(msg.sender, address(this), debtPayment);
            strategies[msg.sender].totalDebt -= debtPayment;
            totalDebt -= debtPayment;
        }

        debt = debtOutstanding(msg.sender);

        strategies[msg.sender].lastReport = block.timestamp;

        emit StrategyReported(
            msg.sender,
            gain,
            loss,
            strategies[msg.sender].totalGain,
            strategies[msg.sender].totalLoss,
            strategies[msg.sender].totalDebt,
            credit
        );
    }

    function migrateStrategy(
        address oldVersion,
        address newVersion,
        uint256 _performanceFee
    ) external onlyAuthorized {
        require(newVersion != address(0));
        require(
            strategies[oldVersion].activation > 0 &&
                strategies[newVersion].activation == 0
        );

        uint256 strategyBalance = IStrategy(oldVersion).migrate(newVersion);
        uint256 debtOldVersion = strategies[oldVersion].totalDebt;
        uint256 gainOldVersion;
        uint256 lossOldVersion;

        if (strategyBalance > debtOldVersion) {
            gainOldVersion = strategyBalance - debtOldVersion;
            strategies[oldVersion].totalGain += gainOldVersion;
        } else if (debtOldVersion > strategyBalance) {
            lossOldVersion = debtOldVersion - strategyBalance;
            strategies[oldVersion].totalLoss += lossOldVersion;
        }

        strategies[oldVersion].totalDebt = 0;

        strategies[newVersion] = StrategyParams({
            performanceFee: _performanceFee,
            activation: block.timestamp,
            lastReport: block.timestamp,
            totalDebt: strategyBalance,
            totalGain: 0,
            totalLoss: 0
        });

        emit StrategyMigrated(
            oldVersion,
            gainOldVersion,
            lossOldVersion,
            newVersion,
            strategyBalance
        );

        for (uint256 i; i < withdrawalQueue.length; i++) {
            if (withdrawalQueue[i] == oldVersion) {
                withdrawalQueue[i] = newVersion;
                break;
            }
        }
    }

    function debtOutstanding(address _strategy) public view returns (uint256) {
        return strategies[_strategy].totalDebt;
    }

    function totalAssets() public view returns (uint256 totalManagedAssets) {
        return asset.balanceOf(address(this)) + totalDebt;
    }

    function convertToShares(uint256 assets)
        public
        view
        returns (uint256 shares)
    {
        uint256 totalSupply = totalSupply();

        return
            totalSupply == 0 ? assets : (assets * totalSupply) / totalAssets();
    }

    function convertToAssets(uint256 shares)
        public
        view
        returns (uint256 assets)
    {
        uint256 totalSupply = totalSupply();

        return
            totalSupply == 0 ? shares : (shares * totalAssets()) / totalSupply;
    }

    function _withdrawFromStrategies(uint256 assets)
        private
        returns (uint256 userProfit, uint256 userLoss)
    {
        address strategy;
        uint256 userAssets;
        uint256 _profit;
        uint256 _loss;

        for (uint256 i; i < withdrawalQueue.length; i++) {
            strategy = withdrawalQueue[i];

            uint256 vaultBalance = asset.balanceOf(address(this));

            if (vaultBalance >= assets) break;

            uint256 withdrawAmount = assets - vaultBalance;

            withdrawAmount = Math.min(
                withdrawAmount,
                strategies[strategy].totalDebt
            );

            // userAssets includes profit/loss
            (userAssets, _profit, _loss) = IStrategy(strategy).withdraw(
                withdrawAmount
            );
            strategies[strategy].totalDebt -= withdrawAmount;
            totalDebt -= withdrawAmount;

            userProfit += _profit;
            userLoss += _loss;
        }
    }

    function _assessFees(address _strategy, uint256 gain) private {
        if (strategies[_strategy].lastReport == 0) return;
        uint256 duration = block.timestamp - strategies[_strategy].lastReport;
        assert(duration != 0);

        uint256 _currentDebt = strategies[_strategy].totalDebt;

        uint256 _managementFee = (_currentDebt * managementFee * duration) /
            (MAX_BPS * SECS_PER_YEAR);

        uint256 perfomanceFee = (gain * strategies[_strategy].performanceFee) /
            MAX_BPS;

        uint256 totalFee = perfomanceFee + _managementFee;

        if (totalFee > gain) {
            totalFee = gain;
        }

        _mint(management, convertToShares(totalFee));
    }
}
