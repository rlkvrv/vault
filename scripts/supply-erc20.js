const hre = require("hardhat");

const main = async function () {
    const [owner] = await hre.ethers.getSigners();

    // `myContractAddress` is logged when running the deploy script.
    // Run the deploy script prior to running this one.
    const myContractAddress = '0xefAB0Beb0A557E452b398035eA964948c750b2Fd';
    const myAbi = require('../artifacts/contracts/MyContract.sol/MyContract.json').abi;
    const myContract = new ethers.Contract(myContractAddress, myAbi, owner);

    // Mainnet Contract for the underlying token https://etherscan.io/address/0x6b175474e89094c44da98b954eedeac495271d0f
    const underlyingAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
    const erc20AbiJson = [
        'function balanceOf(address) external view returns (uint)',
        'function transfer(address dst, uint wad) external returns(bool)'
    ];
    const underlying = new ethers.Contract(underlyingAddress, erc20AbiJson, owner);

    // Mainnet Contract for cDAI (https://compound.finance/docs#networks)
    const cTokenAddress = '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643';
    const cTokenAbi = [
        'function balanceOfUnderlying(address owner) external returns (uint)',
        'function balanceOf(address owner) external view returns(uint)'
    ];
    const cToken = new ethers.Contract(cTokenAddress, cTokenAbi, owner);

    const assetName = 'DAI'; // for the log output lines
    const underlyingDecimals = 18; // Number of decimals defined in this ERC20 token's contract

    await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ["0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7"],
    });
    const signer = await ethers.getSigner("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7");

    const provider = new ethers.providers.JsonRpcProvider('http://localhost:8545');
    const contractIsDeployed = (await provider.getCode(myContractAddress)) !== '0x';

    if (!contractIsDeployed) {
        throw Error('MyContract is not deployed! Deploy it by running the deploy script.');
    }

    console.log(`Now transferring ${assetName} from my wallet to MyContract...`);

    console.log((10000n * 10n ** 18n).toString())

    console.log('underlying balance: ', (await underlying.balanceOf(signer.address)) / Math.pow(10, underlyingDecimals))

    let tx = await underlying.connect(signer).transfer(
        myContractAddress,
        (1000n * 10n ** 18n).toString() // 10 tokens to send to MyContract
    );
    await tx.wait(1); // wait until the transaction has 1 confirmation on the blockchain

    console.log(`MyContract now has ${assetName} to supply to the Compound Protocol.`);

    // Mint some cDAI by sending DAI to the Compound Protocol
    console.log(`MyContract is now minting c${assetName}...`);
    tx = await myContract.supplyErc20ToCompound(
        underlyingAddress,
        cTokenAddress,
        (1000n * 10n ** 18n).toString() // 10 tokens to supply
    );
    let supplyResult = await tx.wait(1);

    console.log(`Supplied ${assetName} to Compound via MyContract`);
    // Uncomment this to see the solidity logs
    // console.log(supplyResult.events);

    await hre.network.provider.send("hardhat_mine", ["0x10000000"]);

    let balanceOfUnderlying = await cToken.callStatic
        .balanceOfUnderlying(myContractAddress) / Math.pow(10, underlyingDecimals);
    console.log(`${assetName} supplied to the Compound Protocol:`, balanceOfUnderlying);

    let cTokenBalance = await cToken.balanceOf(myContractAddress);
    console.log(`MyContract's c${assetName} Token Balance:`, +cTokenBalance / 1e8);

    await network.provider.send("evm_increaseTime", [3600])
    await network.provider.send("evm_mine")

    // Call redeem based on a cToken amount
    const amount = cTokenBalance;
    const redeemType = true; // true for `redeem`

    // Call redeemUnderlying based on an underlying amount
    // const amount = balanceOfUnderlying;
    // const redeemType = false; //false for `redeemUnderlying`

    // Retrieve your asset by exchanging cTokens
    console.log(`Redeeming the c${assetName} for ${assetName}...`);
    tx = await myContract.redeemCErc20Tokens(
        amount,
        redeemType,
        cTokenAddress
    );
    let redeemResult = await tx.wait(1);

    if (redeemResult.events[5].args[1] != 0) {
        throw Error('Redeem Error Code: ' + redeemResult.events[5].args[1]);
    }

    cTokenBalance = await cToken.balanceOf(myContractAddress);
    cTokenBalance = +cTokenBalance / 1e8;
    console.log(`MyContract's c${assetName} Token Balance:`, cTokenBalance);

    const balance3 = await underlying.balanceOf(myContractAddress) / Math.pow(10, underlyingDecimals);
    console.log(`DAI on MYContract ${balance3}`);
}

main().catch((err) => {
    console.error(err);
});