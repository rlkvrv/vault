// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

// EIP-4626: Tokenized Vault Standard - https://eips.ethereum.org/EIPS/eip-4626

interface IVault {
    function token() external view returns (address wantToken);

    function maxDeposit(address) external pure returns (uint256);

    function maxMint(address) external pure returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256 assets);

    function maxRedeem(address owner) external view returns (uint256 shares);

    function deposit(uint256 assets, address receiver)
        external
        returns (uint256 shares);

    function mint(uint256 shares, address receiver)
        external
        returns (uint256 assets);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    function totalAssets() external view returns (uint256 totalManagedAssets);

    function report(
        uint256 gain,
        uint256 loss,
        uint256 debtPayment
    ) external returns (uint256);

    function debtOutstanding(address _strategy) external view returns (uint256);

    function convertToShares(uint256 assets)
        external
        view
        returns (uint256 shares);

    function convertToAssets(uint256 shares)
        external
        view
        returns (uint256 assets);
}
