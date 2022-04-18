const hre = require("hardhat");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const underlyingAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const erc20AbiJson = [
    'function balanceOf(address) external view returns (uint)',
    'function transfer(address dst, uint wad) external returns(bool)',
    'function approve(address usr, uint wad) external returns(bool)'
];
const richUserAddr = "0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7";  // адрес, на котором есть DAI

describe("Compound", function () {
    let underlying;
    let vault;
    let strategy;
    let decimals = Math.pow(10, 18);
    let decimalsBigInt = 10n ** 18n;
    let cToken;
    let cTokenAddress;
    let compToken;
    let comptroller;
    let uniswap;
    let signer;

    beforeEach(async function () {
        const [owner] = await hre.ethers.getSigners();

        await hre.network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [richUserAddr],
        });
        signer = await ethers.getSigner(richUserAddr);

        underlying = new ethers.Contract(underlyingAddress, erc20AbiJson, owner);

        cTokenAddress = '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643';
        const cTokenAbi = [
            'function balanceOfUnderlying(address owner) external returns (uint)',
            'function balanceOf(address owner) external view returns(uint)'
        ];
        cToken = new ethers.Contract(cTokenAddress, cTokenAbi, owner);

        compToken = new ethers.Contract(
            '0xc00e94Cb662C3520282E6f5717214004A7f26888',
            [
                'function balanceOf(address owner) external view returns(uint)',
                'function getCurrentVotes(address account) returns(uint96)',
                'function approve(address spender, uint rawAmount) external returns (bool)'
            ],
            owner
        )

        const Vault = await ethers.getContractFactory("Vault", owner);
        vault = await (await Vault.deploy(underlying.address)).deployed();
        await underlying.connect(signer).approve(vault.address, 10000n * decimalsBigInt);

        const Strategy = await ethers.getContractFactory("Strategy", owner);
        strategy = await (await Strategy.deploy(vault.address, cToken.address)).deployed();

        await vault.addStrategy(strategy.address, 0);

        // console.log('signer balance: ', (await underlying.balanceOf(signer.address)) / decimals);
        await vault.connect(signer).deposit(10000n * decimalsBigInt, signer.address);

        // console.log('signer balance: ', (await underlying.balanceOf(signer.address)) / decimals);
        // const comptrollerAbi = require('../contracts/abi/Coumptroller.json');
        comptroller = new ethers.Contract(
            '0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B',
            ['function claimComp(address holder) public'],
            owner
        )

        uniswap = new ethers.Contract(
            '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
            [
                'function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns(uint[] memory amounts)',
                'function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts)'
            ],
            owner
        )
    })

    it("added liquidity in DAI to Compound protocol", async function () {
        await strategy.harvest();
        expect((await underlying.balanceOf(strategy.address)) / decimals).eq(10000);
        await strategy.adjustPosition();
        expect(await underlying.balanceOf(strategy.address)).eq(0);
        expect(Math.round(await cToken.balanceOf(strategy.address) / Math.pow(10, 8))).eq(455503);
        expect(Math.round(await cToken.callStatic.balanceOfUnderlying(strategy.address) / decimals)).eq(10000);
    });

    it("removed liquidity in DAI to Compound protocol", async function () {
        await strategy.harvest();
        await strategy.adjustPosition();

        await strategy.liquidatePosition(await cToken.callStatic.balanceOfUnderlying(strategy.address));
        expect(Math.round(await underlying.balanceOf(strategy.address) / decimals)).eq(10000);
    });

    it("get rewards", async function () {
        await strategy.harvest();
        await strategy.adjustPosition();
        await strategy.getRewards();

        expect(await compToken.balanceOf(strategy.address)).eq(205215929868);
    });

    it("swap rewards to want token", async function () {
        await strategy.harvest();
        await strategy.adjustPosition();

        await hre.network.provider.send("hardhat_mine", ["0x100000"]);

        await strategy.getRewards();
        await strategy.swapRewardsToWantToken();

        expect(Math.round(await underlying.balanceOf(strategy.address) / decimals)).eq(27);
    });

    it("withdraw and redeem should be worked", async function () {
        await strategy.harvest();
        await strategy.adjustPosition();

        await vault.connect(signer).withdraw(1000n * decimalsBigInt, signer.address, signer.address);
        await vault.connect(signer).redeem(1000n * decimalsBigInt, signer.address, signer.address);
    });

    it("unnamed", async function () {
        await strategy.harvest();
        await strategy.adjustPosition();

        await hre.network.provider.send("hardhat_mine", ["0x1000000"]);

        await strategy.harvest();
    });
});
