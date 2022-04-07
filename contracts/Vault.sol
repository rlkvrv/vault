//SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IVault.sol";

import "hardhat/console.sol";

contract Vault is ERC20 {
    using SafeERC20 for ERC20;

    ERC20 public immutable asset;
    uint256 public totalDebt;

    constructor(ERC20 _asset) ERC20("ShareToken", "SHT") {
        asset = _asset;
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
        uint256 shares
    );

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
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

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        shares = convertToShares(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, receiver, assets);
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        require((assets = convertToAssets(shares)) != 0, "Vault: ZERO_ASSETS");

        if (msg.sender != owner) {
            _spendAllowance(owner, receiver, assets);
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
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

    function maxWithdraw(address owner) public view returns (uint256 assets) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view returns (uint256 shares) {
        return balanceOf(owner);
    }
}
