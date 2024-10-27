import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CodeupERC20, Codeup } from "../typechain-types";
import { ROUTER, WETH_ABI } from "./abis";
import {
  COINS_PRICE,
  convertCoinToETH,
  MAX_COINS_AMOUNT,
  UniswapV2Router,
} from "./utills";

const calcPoolStats = async (game: Codeup) => {
  const router = await ethers.getContractAt(ROUTER, UniswapV2Router);

  const weth = await game.weth();
  const gameToken = await game.codeupERC20();

  const swapAmount = ethers.utils.parseEther("1");

  const wethToGT = await router.getAmountsOut(swapAmount, [weth, gameToken]);
  const wethToGTprice = wethToGT[1];

  const gtToWeth = await router.getAmountsOut(swapAmount, [gameToken, weth]);
  const gtToWETHprice = gtToWeth[1];

  console.log(
    "1 WETH to GT Price ==========>",
    ethers.utils.formatUnits(wethToGTprice, "18")
  );
  console.log(
    "1 GT to WETH Price ===========>",
    ethers.utils.formatUnits(gtToWETHprice, "18")
  );
};

const sell = async (
  player: SignerWithAddress,
  game: Codeup,
  gameToken: CodeupERC20
) => {
  const router = await ethers.getContractAt(ROUTER, UniswapV2Router);
  await gameToken
    .connect(player)
    .approve(UniswapV2Router, ethers.constants.MaxUint256);

  await router
    .connect(player)
    .swapExactTokensForTokens(
      await gameToken.balanceOf(player.address),
      0,
      [gameToken.address, await game.weth()],
      player.address,
      ethers.constants.MaxUint256
    );

  await calcPoolStats(game);
};

const buy = async (
  player: SignerWithAddress,
  game: Codeup,
  gameToken: CodeupERC20
) => {
  const router = await ethers.getContractAt(ROUTER, UniswapV2Router);
  const wethAddress = await game.weth();
  const wethContract = await ethers.getContractAt(WETH_ABI, wethAddress);

  await wethContract
    .connect(player)
    .deposit({ value: ethers.utils.parseEther("0.0001") });

  await wethContract
    .connect(player)
    .approve(router.address, ethers.constants.MaxUint256);

  await router
    .connect(player)
    .swapExactTokensForTokens(
      ethers.utils.parseEther("0.0001"),
      0,
      [wethAddress, gameToken.address],
      player.address,
      ethers.constants.MaxUint256
    );

  await calcPoolStats(game);
};

const buyAllCoders = async (
  gameContract: Codeup,
  player: SignerWithAddress
) => {
  const neededETH = convertCoinToETH(MAX_COINS_AMOUNT);
  await gameContract.connect(player).addGameETH({
    value: neededETH,
  });

  for (let i = 0; i < 8; i++) {
    for (let j = 1; j <= 5; j++) {
      await gameContract.connect(player).upgradeTower(i);
    }
  }
};

describe("UniswapV2Pool tests", function () {
  let gameContract: Codeup;
  let gameToken: CodeupERC20;
  let deployer: SignerWithAddress;
  let player1: SignerWithAddress;
  let accounts: SignerWithAddress[];
  before(async () => {
    const [acc1, acc2, ...accs] = await ethers.getSigners();
    deployer = acc1;
    player1 = acc2;
    accounts = accs;

    const GAME_FACTORY = await ethers.getContractFactory("Codeup");
    const GAME_TOKEN_FACTORY = await ethers.getContractFactory("CodeupERC20");

    gameToken = await GAME_TOKEN_FACTORY.deploy(deployer.address, "GT", "GT");
    await gameToken.deployed();

    gameContract = await GAME_FACTORY.deploy(
      1,
      COINS_PRICE,
      UniswapV2Router,
      gameToken.address
    );
    await gameContract.deployed();

    const deployerBalance = await gameToken.balanceOf(deployer.address);
    await gameToken.transfer(gameContract.address, deployerBalance);
  });

  describe("Testing pool price", async function () {
    it("player 1", async function () {
      console.log(
        "====================================================================="
      );
      await buyAllCoders(gameContract, player1);
      await gameContract.claimCodeupERC20(player1.address, 0, 0, 0);
      const gameTokenBalance = await gameToken.balanceOf(player1.address);
      console.log(
        ethers.utils.formatUnits(gameTokenBalance, 18),
        `Player 1 GameToken balance`
      );

      await calcPoolStats(gameContract);
      console.log(
        "====================================================================="
      );
    });
    it("player 2", async function () {
      console.log(
        "====================================================================="
      );
      await buyAllCoders(gameContract, accounts[0]);
      await gameContract.claimCodeupERC20(accounts[0].address, 0, 0, 0);
      const gameTokenBalance = await gameToken.balanceOf(accounts[0].address);
      console.log(
        ethers.utils.formatUnits(gameTokenBalance, 18),
        `Player 2 GameToken balance`
      );

      await calcPoolStats(gameContract);
      await sell(accounts[0], gameContract, gameToken);
      console.log(
        "====================================================================="
      );
    });
    it("15 players", async function () {
      const isHold = [
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
      ];

      const isTreaders = [
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
      ];

      const isTreadersSell = [
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
      ];

      for (let i = 1; i < 16; i++) {
        console.log(
          "====================================================================="
        );

        await buyAllCoders(gameContract, accounts[i]);
        await gameContract.claimCodeupERC20(accounts[i].address, 0, 0, 0);
        const gameTokenBalance = await gameToken.balanceOf(accounts[i].address);
        console.log(
          ethers.utils.formatUnits(gameTokenBalance, 18),
          `Player ${i} GameToken balance`
        );
        await calcPoolStats(gameContract);
        if (!isHold[i]) {
          await sell(accounts[i], gameContract, gameToken);
        }
        if (isTreaders[i]) {
          console.log("+++++++++++ treader buy +++++++++++");
          await buy(deployer, gameContract, gameToken);
        }
        if (isTreadersSell[i]) {
          console.log("+++++++++++ treader sell +++++++++++");
          await sell(deployer, gameContract, gameToken);
        }
        console.log(
          "====================================================================="
        );
      }
    });
  });
});
