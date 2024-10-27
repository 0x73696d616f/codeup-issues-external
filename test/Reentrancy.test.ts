import { BigNumber } from "ethers";
import { expect } from "chai";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  CodeupERC20,
  Codeup,
  WithdrawReentrance,
  ReinvestReentrancy,
  ClaimCodeupERC20Reentrancy,
} from "../typechain-types";
import {
  COINS_PRICE,
  convertCoinToETH,
  MAX_COINS_AMOUNT,
  UniswapV2Router,
} from "./utills";

describe("Codeup reentrancy tests", function () {
  let gameContract: Codeup;
  let gameToken: CodeupERC20;
  let deployer: SignerWithAddress;

  let withdrawReentrancyContract: WithdrawReentrance;
  let reinvestReentrancyContract: ReinvestReentrancy;
  let claimCodeupERC20ReentrancyContract: ClaimCodeupERC20Reentrancy;
  before(async () => {
    const [acc1] = await ethers.getSigners();
    deployer = acc1;

    const GAME_FACTORY = await ethers.getContractFactory("Codeup");
    const GAME_TOKEN_FACTORY = await ethers.getContractFactory("CodeupERC20");
    const WITHDRAW_REENTRANCY = await ethers.getContractFactory(
      "WithdrawReentrance"
    );
    const REINVEST_REENTRANCY = await ethers.getContractFactory(
      "ReinvestReentrancy"
    );
    const CLAIM_CODEUP_ERC20_REENTRANCY = await ethers.getContractFactory(
      "ClaimCodeupERC20Reentrancy"
    );

    gameToken = await GAME_TOKEN_FACTORY.deploy(deployer.address, "GT", "GT");
    await gameToken.deployed();

    gameContract = await GAME_FACTORY.deploy(
      1,
      COINS_PRICE,
      UniswapV2Router,
      gameToken.address
    );
    await gameContract.deployed();

    withdrawReentrancyContract = await WITHDRAW_REENTRANCY.deploy(
      gameContract.address
    );
    await withdrawReentrancyContract.deployed();

    reinvestReentrancyContract = await REINVEST_REENTRANCY.deploy();
    await reinvestReentrancyContract.deployed();

    claimCodeupERC20ReentrancyContract =
      await CLAIM_CODEUP_ERC20_REENTRANCY.deploy();
    await claimCodeupERC20ReentrancyContract.deployed();

    const deployerBalance = await gameToken.balanceOf(deployer.address);
    await gameToken.transfer(gameContract.address, deployerBalance);
  });
  describe("Withdraw Reeentrancy Attack", () => {
    it("should not allow reentrancy attack on withdraw", async () => {
      const ethAmount = convertCoinToETH(MAX_COINS_AMOUNT);

      await withdrawReentrancyContract.addTokens({ value: ethAmount });
      for (let i = 0; i < 5; i++) {
        await withdrawReentrancyContract.upgrade(0);
      }
      for (let i = 0; i < 5; i++) {
        await withdrawReentrancyContract.upgrade(1);
      }

      await ethers.provider.send("evm_increaseTime", [3600]);
      await withdrawReentrancyContract.collect();

      await expect(withdrawReentrancyContract.withdraw()).to.be.reverted;
    });
  });
  describe("Reinvest Reeentrancy Attack", () => {
    it("should not allow reentrancy attack on reinvest", async () => {
      const TEST_CODEUP = await ethers.getContractFactory("Codeup");
      const REINVEST_REENTRANCY = await ethers.getContractFactory(
        "ReinvestReentrancy"
      );
      const TEST_ROUTER = await ethers.getContractFactory("TestRouter");
      const TEST_FACTORY = await ethers.getContractFactory("TestFactory");

      const reinvestReentrancy = await REINVEST_REENTRANCY.deploy();
      await reinvestReentrancy.deployed();
      const testFactory = await TEST_FACTORY.deploy();
      await testFactory.deployed();
      const testRouter = await TEST_ROUTER.deploy(
        reinvestReentrancy.address,
        testFactory.address
      );
      await testRouter.deployed();

      const testCodeup = await TEST_CODEUP.deploy(
        1,
        COINS_PRICE,
        testRouter.address,
        gameToken.address
      );
      await testCodeup.deployed();
      await testFactory.setCodeup(testCodeup.address);
      await reinvestReentrancy.updateCodeUp(testCodeup.address);

      const ethAmount = convertCoinToETH(MAX_COINS_AMOUNT);
      await testCodeup.addGameETH({
        value: ethAmount.div(BigNumber.from("2")),
      });

      for (let i = 0; i < 5; i++) {
        for (let j = 0; j < 5; j++) {
          await testCodeup.upgradeTower(i);
        }
      }
      await ethers.provider.send("evm_increaseTime", [3600]);

      await testCodeup.collect();

      await expect(testCodeup.reinvest()).to.be.revertedWith(
        "ReentrancyGuardReentrantCall()"
      );
    });
  });
});
