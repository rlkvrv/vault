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

describe("Strategy", function () {
    let strategy;
    let vault;
    let underlying;
    let cToken;
    let cTokenAddress;
    let compToken;
    let signer;
    let owner;
    let mockAcc1;
    let decimals = Math.pow(10, 18);
    let decimalsBigInt = 10n**18n;

    beforeEach(async function () {
        [owner, mockAcc1] = await hre.ethers.getSigners();

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
        await underlying.connect(signer).approve(vault.address, 1000n * decimalsBigInt);

        const Strategy = await ethers.getContractFactory("Strategy", owner);
        strategy = await (await Strategy.deploy(vault.address, cToken.address)).deployed();

        await vault.addStrategy(strategy.address, 100);

        await vault.connect(signer).deposit(1000n * decimalsBigInt, signer.address);
    })

    it("added liquidity in DAI to Compound protocol", async function () {
        await strategy.harvest();

        expect(Math.round(await cToken.balanceOf(strategy.address) / Math.pow(10, 8))).eq(45550);
        expect(Math.round(await cToken.callStatic.balanceOfUnderlying(strategy.address) / decimals)).eq(1000);
    });

    it("removed liquidity in DAI to Compound protocol", async function () {
        await strategy.harvest();

        await strategy.liquidatePosition(await cToken.callStatic.balanceOfUnderlying(strategy.address));
        expect(Math.round(await underlying.balanceOf(strategy.address) / decimals)).eq(1000);
    });

    it("claim and swap rewards", async function () {
        await strategy.harvest();
        await hre.network.provider.send("hardhat_mine", ["0x10000000"]);

        await expect(strategy.harvest()).emit(strategy, 'Harvested').withArgs(2970892260819298831914n, 211799703003017743664n, 0, 4182691963822316575578n)
        expect(await compToken.balanceOf(strategy.address) / decimals).eq(0);
    });

    it("withdraw and redeem should be worked", async function () {
        await strategy.harvest();

        await vault.connect(signer).withdraw(100n * decimalsBigInt, signer.address, signer.address);
        await vault.connect(signer).redeem(100n * decimalsBigInt, signer.address, signer.address);
    });

    it("should be written off total fee", async function () {
        await strategy.harvest();
        await hre.network.provider.send("hardhat_mine", ["0x10000000"]);
        await strategy.harvest();

        expect(Math.round(await vault.balanceOf(owner.address) / decimals)).eq(95);
    });

    it("should be liquidate all position", async function () {
        await strategy.harvest();
        await strategy.liquidateAllPositions();

        expect(Math.round(await underlying.balanceOf(strategy.address) / decimals)).eq(1000);
    });

    it("should be write strategist address", async function () {
        await strategy.setStrategist(mockAcc1.address);

        expect(await strategy.strategist()).eq(mockAcc1.address);
    });

    it("should be write keeper address", async function () {
        await strategy.setKeeper(mockAcc1.address);

        expect(await strategy.keeper()).eq(mockAcc1.address);
    });
});
