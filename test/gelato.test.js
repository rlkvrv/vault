const { expect } = require("chai");
const { ethers, network } = require("hardhat");

const daiAddr = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const userAddr = "0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7";  // адрес, на котором есть DAI
const cTokenAddr = '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643';
const opsAddr = '0xB3f5503f93d5Ef84b06993a1975B9D21B962892F';
const gelatoAddr = '0x3CACa7b48D0573D793d3b0279b5F0029180E83b6';

describe("Gelato", function () {
    let strategy;
    let vault;
    let strategyResolver;
    let ops;
    let daiToken;
    let cToken;
    let owner;
    let signer;
    let gelatoSigner;
    let decimalsBigInt = 10n ** 18n;

    beforeEach(async function () {
        [owner] = await ethers.getSigners();

        await network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [userAddr],
        });
        signer = await ethers.getSigner(userAddr);

        daiToken = new ethers.Contract(
            daiAddr,
            ['function approve(address usr, uint wad) external returns(bool)'],
            owner
        );

        cToken = new ethers.Contract(cTokenAddr, [], owner);

        const Vault = await ethers.getContractFactory("Vault", owner);
        vault = await (await Vault.deploy(daiToken.address)).deployed();

        await daiToken.connect(signer).approve(vault.address, 1000n * decimalsBigInt);

        const Strategy = await ethers.getContractFactory("Strategy", owner);
        strategy = await (await Strategy.deploy(vault.address, cToken.address)).deployed();

        await vault.addStrategy(strategy.address, 100);
        await vault.connect(signer).deposit(1000n * decimalsBigInt, signer.address);

        const StrategyResolver = await ethers.getContractFactory("StrategyResolver", owner);
        strategyResolver = await (await StrategyResolver.deploy(strategy.address, opsAddr)).deployed();

        await network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [gelatoAddr],
        });
        gelatoSigner = await ethers.getSigner(gelatoAddr);

        opsAbi = require('../contracts/interfaces/abi/ops.abi.json');
        ops = new ethers.Contract(opsAddr, opsAbi, owner);

        await strategy.setKeeper(ops.address);
    })

    it("should be created task", async function () {
        await strategyResolver.startTask();

        const [taskId] = await ops.getTaskIdsByUser(strategyResolver.address);
        const taskCreator = await ops.taskCreator(taskId);

        expect(taskCreator).eq(strategyResolver.address);
    });

    it("should be execute task", async function () {
        await strategyResolver.startTask();

        let [canExec, execPayload] = await strategyResolver.checker();

        const resolver = require('../artifacts/contracts/StrategyResolver.sol/StrategyResolver.json');
        const resolverData = new ethers.utils.Interface(resolver.abi).encodeFunctionData('checker')

        const resolverHash = await ops.getResolverHash(strategyResolver.address, resolverData);

        expect(canExec).to.be.true;

        const ETHAddr = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

        if (canExec) {
            await ops.connect(gelatoSigner).exec(
                0,
                ETHAddr,
                strategyResolver.address,
                true,
                true,
                resolverHash,
                strategy.address,
                execPayload
            );
        }

        [canExec] = await strategyResolver.checker();
        expect(canExec).to.be.false;
    });
});