//SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IStrategy.sol";

import "hardhat/console.sol";

contract Vault is IVault, ERC20 {
    using SafeERC20 for ERC20;

    ERC20 public immutable asset;
    uint256 managementFee = 100; // 1% per year
    uint256 SECS_PER_YEAR = 31556952;
    uint256 MAX_BPS = 10000; // min fee 0,01%

    address public management;
    address public strategy;
    uint256 public totalDebt;

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
        uint256 assets,
        uint256 shares,
        uint256 currentProfit,
        uint256 currentLoss
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

    event StrategyMigrated(address oldVersion, address newVersion);

    modifier onlyAuthorized() {
        require(msg.sender == management, "Vault: ONLY_AUTHORIZED");
        _;
    }

    function token() external view returns (address wantToken) {
        return address(asset);
    }

    function addStrategy(address _strategy, uint256 _perfomanceFee)
        external
        onlyAuthorized
    {
        require(_strategy != address(0), "Vault: ZERO_STRATEGY");
        strategy = _strategy;
        strategies[_strategy].performanceFee = _perfomanceFee;
        strategies[_strategy].activation = block.timestamp;

        emit StrategyAdded(_strategy, _perfomanceFee);
    }

    function updateManagement(address _management) external onlyAuthorized {
        management = _management;

        emit UpdateManagement(management);
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

    function deposit(uint256 assets, address receiver)
        external
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets)) != 0, "Vault: ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver)
        external
        returns (uint256 assets)
    {
        require((assets = previewMint(shares)) != 0, "Vault: ZERO_ASSETS");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        shares = previewWithdraw(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, receiver, assets);
        }

        uint256 userProfit;
        uint256 userLoss;
        uint256 balance = asset.balanceOf(address(this));

        // Если в волте недостаточно средств, запрашиваем у стратегии
        if (balance < assets) {
            uint256 userAssets;
            uint256 strategyDebt = assets - balance;

            // userAssets уже учитывают profit/loss
            (userAssets, userProfit, userLoss) = IStrategy(strategy).withdraw(
                strategyDebt
            );
            strategies[strategy].totalDebt -= userAssets;
            totalDebt -= userAssets;
        }

        _burn(owner, shares);

        // елсли на волте достаточно средств, то userProfit и userLoss будут 0
        asset.safeTransfer(receiver, assets + userProfit - userLoss);

        emit Withdraw(
            msg.sender,
            receiver,
            owner,
            assets,
            shares,
            userProfit,
            userLoss
        );
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        require((assets = previewRedeem(shares)) != 0, "Vault: ZERO_ASSETS");

        if (msg.sender != owner) {
            _spendAllowance(owner, receiver, assets);
        }

        uint256 userProfit;
        uint256 userLoss;
        uint256 balance = asset.balanceOf(address(this));

        if (balance < assets) {
            uint256 userAssets;
            uint256 strategyDebt = assets - balance;

            (userAssets, userProfit, userLoss) = IStrategy(strategy).withdraw(
                strategyDebt
            );
            strategies[strategy].totalDebt -= userAssets;
            totalDebt -= userAssets;
        }

        _burn(owner, shares);

        asset.safeTransfer(receiver, assets + userProfit - userLoss);

        emit Withdraw(
            msg.sender,
            receiver,
            owner,
            assets,
            shares,
            userProfit,
            userLoss
        );
    }

    function report(
        uint256 gain,
        uint256 loss,
        uint256 debtPayment
    ) external returns (uint256 debt) {
        require(
            strategies[msg.sender].activation > 0,
            "Vault: ONLY_APPROVED_STRATEGY"
        );
        uint256 credit = asset.balanceOf(address(this));

        if (credit > 0 && debtPayment == 0) {
            asset.safeTransfer(msg.sender, credit);
            strategies[msg.sender].totalDebt += credit;
            totalDebt += credit;
        } else if (debtPayment > 0) {
            asset.safeTransferFrom(msg.sender, address(this), debtPayment + gain);
            strategies[msg.sender].totalDebt -= debtPayment;
            totalDebt -= debtPayment;
        }

        if (gain > 0) {
            strategies[msg.sender].totalGain += gain;
            strategies[msg.sender].totalDebt += gain;
            totalDebt += gain;
            _assessFees(msg.sender, gain);
        }

        if (loss > 0) {
            strategies[msg.sender].totalLoss += loss;
            strategies[msg.sender].totalDebt -= loss;
            totalDebt -= loss;
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

    function migrateStrategy(address oldVersion, address newVersion)
        external
        onlyAuthorized
    {
        require(newVersion != address(0));
        require(
            strategies[oldVersion].activation > 0 &&
                strategies[newVersion].activation == 0
        );

        StrategyParams memory oldStrategy = strategies[oldVersion];

        strategies[newVersion] = StrategyParams({
            performanceFee: oldStrategy.performanceFee,
            activation: block.timestamp,
            lastReport: oldStrategy.lastReport,
            totalDebt: oldStrategy.totalDebt,
            totalGain: 0,
            totalLoss: 0
        });

        strategy = newVersion;
        IStrategy(oldVersion).migrate(newVersion);

        emit StrategyMigrated(oldVersion, newVersion);
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

    function previewDeposit(uint256 assets)
        public
        view
        returns (uint256 shares)
    {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256 assets) {
        uint256 totalSupply = totalSupply();
        uint256 numerator = shares * totalAssets();
        uint256 isZero = (numerator) == 0 ? 0 : 1;

        return
            totalSupply == 0
                ? shares
                : (((numerator - 1) / totalSupply) + 1) * isZero;
    }

    function previewRedeem(uint256 shares)
        public
        view
        returns (uint256 assets)
    {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        uint256 numerator = assets * totalSupply;
        uint256 isZero = (numerator) == 0 ? 0 : 1;

        return
            totalSupply == 0
                ? assets
                : (((numerator - 1) / totalAssets()) + 1) * isZero;
    }

    function _assessFees(address _strategy, uint256 gain) private {
        uint256 duration = block.timestamp - strategies[_strategy].lastReport;
        assert(duration != 0);

        uint256 _currentDebt = strategies[_strategy].totalDebt;

        uint256 totalManagementFee = ((_currentDebt *
            (MAX_BPS - managementFee)) / MAX_BPS);
        uint256 _managementFee = (((_currentDebt - totalManagementFee)) *
            duration) / SECS_PER_YEAR;

        uint256 gainWithPerfomanceFee = (gain *
            (MAX_BPS - strategies[_strategy].performanceFee)) / MAX_BPS;
        uint256 perfomanceFee = gain - gainWithPerfomanceFee;

        uint256 totalFee = perfomanceFee + _managementFee;

        if (totalFee > gain) {
            totalFee = gain;
        }

        _mint(management, convertToShares(totalFee));
    }
}
