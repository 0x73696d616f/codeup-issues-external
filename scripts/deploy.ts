import { ethers } from "hardhat";
import { Codeup } from "../typechain-types";
import { verifyContract } from "./verify";

const COINS_PRICE = ethers.utils.parseEther("0.0000001"); // new price;
const startTimeUnix = "1";
const deployer = process.env.DEPLOYER_ADDRESS
  ? process.env.DEPLOYER_ADDRESS
  : ethers.constants.AddressZero;
const ROUTER = "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24";
const name = "codeUP.app (CUP)";
const symbol = "CUP";

async function main() {
  if (deployer === ethers.constants.AddressZero) {
    throw new Error("DEPLOYER env variable is required");
  }
  const GAME_FACTORY = await ethers.getContractFactory("Codeup");
  const GAME_TOKEN_FACTORY = await ethers.getContractFactory("CodeupERC20");
  console.log("Deploying contracts with the account:", deployer);
  const gameToken = await GAME_TOKEN_FACTORY.deploy(deployer, name, symbol);
  await gameToken.deployTransaction.wait(5);
  console.log("GameToken deployed to:", gameToken.address);

  const game: Codeup = await GAME_FACTORY.deploy(
    startTimeUnix,
    COINS_PRICE,
    ROUTER,
    gameToken.address
  );
  await game.deployTransaction.wait(5);
  console.log("Game deployed to:", game.address);

  await gameToken.transfer(game.address, await gameToken.balanceOf(deployer));

  try {
    await verifyContract(gameToken.address, [deployer, name, symbol]);
  } catch (error) {
    console.error("Error verifying contract:", error);
  }

  try {
    await verifyContract(game.address, [
      startTimeUnix,
      COINS_PRICE,
      ROUTER,
      gameToken.address,
    ]);
  } catch (error) {
    console.error("Error verifying contract:", error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
