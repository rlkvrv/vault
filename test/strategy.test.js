const { expect } = require("chai");
const { ethers, network } = require("hardhat");

const daiAddr = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const userAddr = "0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7";  // адрес, на котором есть DAI
const cTokenAddr = '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643';
const compTokenAddr = '0xc00e94Cb662C3520282E6f5717214004A7f26888';

const erc20AbiJson = [
    'function balanceOf(address) external view returns (uint)',
    'function transfer(address dst, uint wad) external returns(bool)',
    'function approve(address usr, uint wad) external returns(bool)'
];
const cTokenAbi = [
    'function balanceOfUnderlying(address owner) external returns (uint)',
    'function balanceOf(address owner) external view returns(uint)'
];
const compTokenAbi = [
    'function balanceOf(address owner) external view returns(uint)',
    'function getCurrentVotes(address account) returns(uint96)',
    'function approve(address spender, uint rawAmount) external returns (bool)'
]

describe("Strategy", function () {
    let strategy;
    let vault;
    let daiToken;
    let cToken;
    let compToken;
    let owner;
    let signer;
    let mockAcc1;
    let decimals = Math.pow(10, 18);
    let decimalsBigInt = 10n ** 18n;

    beforeEach(async function () {
        [owner, mockAcc1] = await ethers.getSigners();

        await network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [userAddr],
        });
        signer = await ethers.getSigner(userAddr);

        daiToken = new ethers.Contract(daiAddr, erc20AbiJson, owner);
        cToken = new ethers.Contract(cTokenAddr, cTokenAbi, owner);
        compToken = new ethers.Contract(compTokenAddr, compTokenAbi, owner);

        const Vault = await ethers.getContractFactory("Vault", owner);
        vault = await (await Vault.deploy(daiToken.address)).deployed();

        await daiToken.connect(signer).approve(vault.address, 1000n * decimalsBigInt);

        const Strategy = await ethers.getContractFactory("Strategy", owner);
        strategy = await (await Strategy.deploy(vault.address, cToken.address)).deployed();

        await vault.addStrategy(strategy.address, 100);
        await vault.connect(signer).deposit(1000n * decimalsBigInt, signer.address);

        await strategy.harvest();
    })

    it("added liquidity in DAI to Compound protocol", async function () {
        expect(Math.round(await cToken.balanceOf(strategy.address) / Math.pow(10, 8))).eq(45550);
        expect(Math.round(await cToken.callStatic.balanceOfUnderlying(strategy.address) / decimals)).eq(1000);
    });

    it("claim and swap rewards", async function () {
        await network.provider.send("hardhat_mine", ["0x10000000"]);

        await expect(strategy.harvest()).emit(strategy, 'Harvested').withArgs(2970891989119906144222n, 211799707638308526773n, 0, 4182691696758214670995n, 0)
        expect(await compToken.balanceOf(strategy.address) / decimals).eq(0);
    });

    it("withdraw and redeem should be worked", async function () {
        await vault.connect(signer).withdraw(100n * decimalsBigInt, signer.address, signer.address);
        await vault.connect(signer).redeem(100n * decimalsBigInt, signer.address, signer.address);
    });

    it("should be written off total fee", async function () {
        await network.provider.send("hardhat_mine", ["0x10000000"]);
        await strategy.harvest();

        expect(Math.round(await vault.balanceOf(owner.address) / decimals)).eq(95);
    });

    it("should withdraw funds to vault during an emergency stop", async function () {
        await strategy.setEmergencyExit();
        await network.provider.send("evm_increaseTime", [86400])
        await strategy.harvest();

        expect(Math.round(await daiToken.balanceOf(strategy.address) / decimals)).eq(0);
    });

    it("should be migrate to the new strategy", async function () {
        const mockStrategy = await (await (await ethers.getContractFactory("Strategy", owner)).deploy(vault.address, cToken.address)).deployed();
        await vault.migrateStrategy(strategy.address, mockStrategy.address);

        expect(Math.round(await daiToken.balanceOf(mockStrategy.address) / decimals)).eq(1000);
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
