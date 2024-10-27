import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { Codeup } from "../typechain-types";
import { ROUTER } from "./abis";

export const COINS_PRICE = ethers.utils.parseEther("0.0000001");
export const MAX_COINS_AMOUNT = BigNumber.from("78650");

export const UniswapV2Router = "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24";

export const getCurrentTimeStamp = async () => {
  const block = await ethers.provider.getBlock("latest");
  return block.timestamp;
};

export const convertETHtoCoin = (ethAmount: BigNumber) => {
  return ethAmount.div(COINS_PRICE);
};

export const convertCoinToETH = (coinAmount: BigNumber) => {
  return coinAmount.mul(COINS_PRICE);
};

export const calcManagerFee = (ethAmount: BigNumber) => {
  return ethAmount.mul(BigNumber.from(10)).div(BigNumber.from(100));
};

export const calcGTtoETHRate = async (game: Codeup) => {
  const router = await ethers.getContractAt(ROUTER, UniswapV2Router);

  const weth = await game.weth();
  const gameToken = await game.codeupERC20();

  const swapAmount = ethers.utils.parseEther("1");

  const wethToGT = await router.getAmountsOut(swapAmount, [weth, gameToken]);
  const wethToGTprice = wethToGT[1];

  const gtToWeth = await router.getAmountsOut(swapAmount, [gameToken, weth]);
  const gtToWETHprice = gtToWeth[1];

  return {
    wethToGTprice,
    gtToWETHprice,
  };
};
