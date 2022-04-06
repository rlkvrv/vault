const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Vault", function () {
  let token;
  let vault;

  beforeEach(async function () {
    [acc1, acc2] = await ethers.getSigners();
    token = await (await (await ethers.getContractFactory('ERC20Token', acc1))
      .deploy("LampTokenA", "LTA", 10000))
      .deployed();

    const Vault = await ethers.getContractFactory("Vault", acc1);
    vault = await (await Vault.deploy(token.address)).deployed();
  })

  it("should be", async function () {
    await token.approve(vault.address, 10000);
    expect(await token.allowance(acc1.address, vault.address)).to.eq(10000);
    await vault.deposit(1000, acc1.address);
    // await vault.approve(acc2.address, 100);
    await vault.connect(acc2).withdraw(1000, acc2.address, acc1.address);
    console.log('balance', await token.balanceOf(acc2.address));
    // await vault.connect(acc2).withdraw(100, acc2.address, acc1.address);
    // await vault.connect(acc2).withdraw(100, acc2.address, acc1.address);
    // await vault.connect(acc2).withdraw(100, acc2.address, acc1.address);
    // await vault.connect(acc2).withdraw(100, acc2.address, acc1.address);
    console.log(await vault.allowance(acc1.address, acc2.address));
    console.log(await vault.allowance(acc2.address, acc2.address));
  });
});
