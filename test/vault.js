const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Vault", function () {
  let token;
  let vault;
  let maxUint = ethers.BigNumber.from(2n ** 256n - 1n);

  beforeEach(async function () {
    [acc1, acc2] = await ethers.getSigners();
    token = await (await (await ethers.getContractFactory('ERC20Token', acc1))
      .deploy("LampTokenA", "LTA", 10000))
      .deployed();

    const Vault = await ethers.getContractFactory("Vault", acc1);
    vault = await (await Vault.deploy(token.address)).deployed();
    await token.approve(vault.address, 10000);
  })

  it("maxDeposit should be return maxUint", async function () {
    expect(await vault.maxDeposit(acc1.address)).eq(maxUint);
  });

  it("convertToShares should be return 100", async function () {
    expect(await vault.convertToShares(100)).eq(100);
  });

  it("convertToAssets should be return 100", async function () {
    expect(await vault.convertToAssets(100)).eq(100);
  });

  it("maxWithdraw should be return assets owner balanceOf", async function () {
    await vault.deposit(1000, acc1.address);
    expect(await vault.maxWithdraw(acc1.address)).eq(1000);
  });

  it("maxRedeem should be return shares owner balanceOf", async function () {
    await vault.deposit(1000, acc1.address);
    expect(await vault.maxRedeem(acc1.address)).eq(1000);
  });

  it("withdraw should be correct work", async function () {
    await vault.deposit(1000, acc1.address);
    await vault.approve(acc2.address, 100);
    await vault.connect(acc2).withdraw(50, acc2.address, acc1.address);
    expect(await token.balanceOf(acc2.address)).eq(50);
    expect(await vault.allowance(acc1.address, acc2.address)).eq(50);
    await expect(vault.connect(acc2).withdraw(100, acc2.address, acc1.address)).revertedWith('ERC20: insufficient allowance');
  });

  it("redeem should be correct work", async function () {
    await vault.deposit(1000, acc1.address);
    await vault.approve(acc2.address, 100);
    await vault.connect(acc2).redeem(50, acc2.address, acc1.address);
    expect(await token.balanceOf(acc2.address)).eq(50);
    expect(await vault.allowance(acc1.address, acc2.address)).eq(50);
    await expect(vault.connect(acc2).redeem(100, acc2.address, acc1.address)).revertedWith('ERC20: insufficient allowance');
  });
});
