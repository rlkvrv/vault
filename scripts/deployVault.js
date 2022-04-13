const hre = require("hardhat");

async function main() {
    const [owner] = await hre.ethers.getSigners();

    await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ["0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7"],
    });
    const signer = await ethers.getSigner("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7"); // адрес, на котором есть DAI

    const underlyingAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
    const erc20AbiJson = [
        {
            "inputs": [
                {
                    "internalType": "address",
                    "name": "",
                    "type": "address"
                }
            ],
            "name": "balanceOf",
            "outputs": [
                {
                    "internalType": "uint256",
                    "name": "",
                    "type": "uint256"
                }
            ],
            "stateMutability": "view",
            "type": "function"
        },
        'function transfer(address dst, uint wad) external returns(bool)',
        'function approve(address usr, uint wad) external returns(bool)'
    ];
    const underlying = new ethers.Contract(underlyingAddress, erc20AbiJson, owner);

    const Vault = await ethers.getContractFactory("Vault", owner);
    const vault = await (await Vault.deploy(underlying.address)).deployed();
    await underlying.connect(signer).approve(vault.address, 10000n * 10n ** 18n);

    const Strategy = await ethers.getContractFactory("Strategy", owner);
    const strategy = await (await Strategy.deploy(vault.address)).deployed();

    await vault.addStrategy(strategy.address, 0);

    console.log('signer balance: ', (await underlying.balanceOf(signer.address))/ Math.pow(10, 18));

    await vault.connect(signer).deposit(10000n * 10n ** 18n, signer.address);

    console.log('signer balance: ', (await underlying.balanceOf(signer.address)) / Math.pow(10, 18));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });