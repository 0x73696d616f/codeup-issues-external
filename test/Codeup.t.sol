// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV2Factory} from "../contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router} from "../contracts/interfaces/IUniswapV2Router.sol";
import {IWETH} from "../contracts/interfaces/IWETH.sol";
import {Codeup} from "../contracts/Codeup.sol";
import {CodeupERC20} from "../contracts/CodeupERC20.sol";

contract SomeTest is Test {
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router public uniswapV2Router;
    IWETH public weth;
    Codeup public codeup;
    CodeupERC20 public codeupERC20;
    address public owner = makeAddr("owner");
    uint256 constant gamePrice = 0.000001 ether;
    uint256 constant gameETHForWithdrawRate = gamePrice / 1000;
    uint256 private constant WITHDRAW_COMMISSION = 66;
    uint256 private constant TOKEN_AMOUNT_FOR_WINNER = 1 ether;
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    uint256 public constant MAX_PK = 115792089237316195423570985008687907852837564279074904382605163141518161494337;

    function setUp() public {
        weth = IWETH(vm.deployCode("WETH9"));
        uniswapV2Factory = IUniswapV2Factory(deployCode("UniswapV2Factory", abi.encode(address(weth))));
        uniswapV2Router = IUniswapV2Router(deployCode("UniswapV2Router02", abi.encode(address(uniswapV2Factory), address(weth))));
        codeupERC20 = new CodeupERC20(owner, "CodeupERC20", "CODEUP");
        codeup = new Codeup(block.timestamp + 100, gamePrice, address(uniswapV2Router), address(codeupERC20));
        vm.startPrank(owner);
        codeupERC20.transfer(address(codeup), codeupERC20.balanceOf(owner));
    }

    function test_AddGameEth_RevertDueToNotStarted() public {
        deal(user1, 2 ether);
        _changePrank(user1);
        skip(100);
        uint256 depositValue_ = 1 ether;
        vm.expectRevert(Codeup.NotStarted.selector);
        codeup.addGameETH{value: depositValue_}();
    }

    function test_AddGameEth_Success() public {
        uint256 depositValue_ = 1 ether;
        deal(user1, 2 * depositValue_);
        _changePrank(user1);
        skip(101);
        _addGameEthAndAssert(user1, depositValue_);
        _addGameEthAndAssert(user1, depositValue_);
    }
    
    function test_withdraw_Success() public {
        uint256 depositValue_ = 1 ether;
        deal(user1, 1 ether);
        _changePrank(user1);
        _skip(101);
        _addGameEthAndAssert(user1, depositValue_);

        assertEq(0, _withdrawAndAssert(user1));

        _skip(24 * 60);

        assertEq(0, _withdrawAndAssert(user1));

        _upgradeTowerAndAssert(user1, 0);

        _skip(12 * 60);
        uint256 collected = _collectAndAssert(user1);
        assertEq(0, _collectAndAssert(user1));

        _skip(6 * 60);
        collected += _upgradeTowerAndAssert(user1, 0);

        _skip(6 * 60);
        collected += _collectAndAssert(user1);

        _skip(100 * 60);
        collected += _collectAndAssert(user1);

        _skip(24 * 60);
        collected += _collectAndAssert(user1);

        uint256 grossWithdrawn = collected * gameETHForWithdrawRate;
        assertEq((grossWithdrawn - grossWithdrawn * WITHDRAW_COMMISSION / 100), _withdrawAndAssert(user1));
        assertEq(0, _withdrawAndAssert(user1));
    }

    function test_reinvest_Success() public {
        uint256 depositValue_ = 1 ether;
        deal(user1, 1 ether);
        _changePrank(user1);
        _skip(101);
        _addGameEthAndAssert(user1, depositValue_);
        _upgradeTowerAndAssert(user1, 0);
        _skip(24 * 60);
        _collectAndAssert(user1);
        _reinvestAndAssert(user1);
        assertEq(0, _withdrawAndAssert(user1));
    }

    struct User {
        address user;
        uint256 amount;
    }

    function test_claimCodeupERC20_Success(User[20] calldata users) public {
        _skip(101);
        for (uint i = 0; i < users.length; i++) {
            address user_ = users[i].user;
            uint256 depositValue_ = users[i].amount % 100_000 ether;
            deal(user_, depositValue_);
            _changePrank(user_);
            _addGameEthAndAssert(user_, depositValue_);
            _maxUpgradeAndAssert(user_);
            _claimCodeupERC20AndAssert(user_);
            _claimCodeupERC20AndAssert(user_);
        }
    }

    function test_POC_DepositIsWorthMoreJustAfter16Hours() public {
        _skip(101);
        deal(user2, 1 ether);
        _changePrank(user2);
        _addGameEthAndAssert(user2, 1 ether);

        uint256 depositValue_ = 7865 * gamePrice; // 7865 is the game eth needed to buy all towers
        assertEq(depositValue_, 0.007865 ether);
        deal(user1, depositValue_);
        _changePrank(user1);
        _addGameEthAndAssert(user1, depositValue_);
        _maxUpgradeAndAssert(user1);

        for (uint i = 0; i < 40; i++) {
            _skip(24 minutes);
            _collectAndAssert(user1);            
        }
        uint256 withdrawnValue_ = _withdrawAndAssert(user1);
        assertEq(withdrawnValue_, 0.0081019008 ether);
        assertGt(withdrawnValue_, depositValue_);
    }

    function _changePrank(address user_) internal {
        vm.stopPrank();
        vm.startPrank(user_);
    }

    function _addGameEthAndAssert(address user_, uint256 depositValue_) internal returns (uint256 addedGameETH) {
        console.log("ADD", user_, depositValue_);
        if (depositValue_ < gamePrice) {
            vm.expectRevert(Codeup.ZeroValue.selector);
            codeup.addGameETH{value: depositValue_}();
            return 0;
        }
        Codeup.Tower memory initialTower = _getTower(user_);
        uint256 initialTotalInvested = codeup.totalInvested();
        uint256 initialTotalTowers = codeup.totalTowers();
        uint256 initialWethBalance = weth.balanceOf(address(codeup));
        uint256 initialETHValue = address(codeup).balance;
        addedGameETH = depositValue_ / gamePrice;
        codeup.addGameETH{value: depositValue_}();
        Codeup.Tower memory finalTower = _getTower(user_);
        assertEq(finalTower.gameETH, addedGameETH + initialTower.gameETH);
        assertEq(codeup.totalInvested(), depositValue_ + initialTotalInvested);
        assertEq(codeup.totalTowers(), initialTower.timestamp == 0 ? initialTotalTowers + 1 : initialTotalTowers);
        assertEq(finalTower.timestamp, initialTower.timestamp == 0 ? block.timestamp : initialTower.timestamp);
        assertEq(weth.balanceOf(address(codeup)), depositValue_ / 10 + initialWethBalance);
        assertEq(address(codeup).balance, initialETHValue + depositValue_ - depositValue_ / 10);
    }

    function _withdrawAndAssert(address user_) internal returns (uint256 netWithdrawnValue) {
        console.log("WITHDRAW", user_);
        Codeup.Tower memory initialTower = _getTower(user_);
        uint256 initialWethBalance = weth.balanceOf(address(codeup));
        uint256 initialETHValue = address(codeup).balance;
        uint256 initialUserETHBalance = address(user_).balance;
        codeup.withdraw();
        Codeup.Tower memory finalTower = _getTower(user_);
        uint256 withdrawValue = initialTower.gameETHForWithdraw * gameETHForWithdrawRate;
        if (withdrawValue > initialETHValue) withdrawValue = initialETHValue;
        uint256 commission = (withdrawValue * WITHDRAW_COMMISSION) / 100;
        uint256 wethCommission = commission / 2;
        uint256 ethCommission = commission - wethCommission;
        netWithdrawnValue = withdrawValue - commission;
        assertEq(weth.balanceOf(address(codeup)), initialWethBalance + wethCommission);
        assertEq(address(codeup).balance, initialETHValue + ethCommission - withdrawValue);
        assertEq(address(user_).balance, initialUserETHBalance + netWithdrawnValue);
        assertEq(finalTower.gameETHForWithdraw, 0);
    }

    function _collectAndAssert(address user_) internal returns (uint256 collected) {
        console.log("COLLECT", user_);
        Codeup.Tower memory initialTower = _getTower(user_);
        uint256 initialGameETHForWithdraw = initialTower.gameETHForWithdraw;
        collected = _expectedYield(initialTower);

        codeup.collect();
        Codeup.Tower memory finalTower = _getTower(user_);
        uint256 collectedNowPlusPrev = collected + initialTower.gameETHCollected;
        assertEq(finalTower.gameETHForWithdraw, initialGameETHForWithdraw + collectedNowPlusPrev, "gameETHForWithdraw");
        assertEq(finalTower.gameETHCollected, 0, "gameETHCollected");
        assertEq(finalTower.totalGameETHReceived, initialTower.totalGameETHReceived + collected, "totalGameETHReceived");
        assertEq(finalTower.min, 0, "min");
    }

    function _upgradeTowerAndAssert(address user_, uint256 floorId_) internal returns (uint256 collected) {
        console.log("UPGRADE", user_, floorId_);
        Codeup.Tower memory initialTower = _getTower(user_);
        if (floorId_ > 7) {
            vm.expectRevert(Codeup.MaxFloorsReached.selector);
            codeup.upgradeTower(floorId_);
            return 0;
        }
        if (floorId_ > 0 && initialTower.builders[floorId_ - 1] != 5) {
            vm.expectRevert(Codeup.NeedToBuyPreviousBuilder.selector);
            codeup.upgradeTower(floorId_);
            return 0;
        }
        if (initialTower.builders[floorId_] == 5) {
            vm.expectRevert(Codeup.IncorrectBuilderId.selector);
            codeup.upgradeTower(floorId_);
            return 0;
        }
        if (initialTower.timestamp == 0) {
            vm.expectRevert(Codeup.ZeroValue.selector);
            codeup.upgradeTower(floorId_);
            return 0;
        }
        if (initialTower.gameETH < _getUpgradePrice(floorId_, initialTower.builders[floorId_] + 1)) {
            vm.expectRevert();
            codeup.upgradeTower(floorId_);
            return 0;
        }

        collected = _expectedYield(initialTower);
        uint256 expectedMinIncrease = _expectedMinIncrease(initialTower);
        uint256 initialTotalBuilders = codeup.totalBuilders();
        codeup.upgradeTower(floorId_);
        Codeup.Tower memory finalTower = _getTower(user_);
        assertEq(finalTower.gameETHCollected, initialTower.gameETHCollected + collected, "gameETHCollected");
        assertEq(finalTower.totalGameETHReceived, initialTower.totalGameETHReceived + collected, "totalGameETHReceived");
        assertEq(finalTower.min, initialTower.min + expectedMinIncrease, "min");
        assertEq(finalTower.timestamp, block.timestamp, "timestamp");
        assertEq(codeup.totalBuilders(), initialTotalBuilders + 1, "totalBuilders");
        assertEq(finalTower.builders[floorId_], initialTower.builders[floorId_] + 1, "builders");
        uint256 expectedPrice = _getUpgradePrice(floorId_, finalTower.builders[floorId_]);
        assertEq(finalTower.totalGameETHSpend, initialTower.totalGameETHSpend + expectedPrice, "totalGameETHSpend");
        assertEq(finalTower.gameETH, initialTower.gameETH - expectedPrice, "gameETH");
        assertEq(finalTower.yields, initialTower.yields + _getYield(floorId_, finalTower.builders[floorId_]), "yields");
    }

    function _reinvestAndAssert(address user_) internal {
        console.log("REINVEST", user_);
        Codeup.Tower memory initialTower = _getTower(user_);
        uint256 initialTotalInvested = codeup.totalInvested();
        uint256 initialWethBalance = weth.balanceOf(address(codeup));
        uint256 initialETHValue = address(codeup).balance;
        codeup.reinvest();
        Codeup.Tower memory finalTower = _getTower(user_);
        uint256 ethReinvested = initialTower.gameETHForWithdraw * gameETHForWithdrawRate;
        uint256 gameETHReceived = ethReinvested / gamePrice;
        uint256 wethDeposit = ethReinvested * 10 / 100;
        assertEq(finalTower.gameETHForWithdraw, 0, "gameETHForWithdraw");
        assertEq(finalTower.gameETH, initialTower.gameETH + gameETHReceived, "gameETH");
        assertEq(codeup.totalInvested(), initialTotalInvested + ethReinvested, "totalInvested");
        assertEq(weth.balanceOf(address(codeup)), initialWethBalance + wethDeposit, "wethBalance");
        assertEq(address(codeup).balance, initialETHValue - wethDeposit, "ethValue");
    }

    function _claimCodeupERC20AndAssert(address user_) internal {
        if (codeup.isClaimed(user_)) {
            vm.expectRevert(Codeup.AlreadyClaimed.selector);
            codeup.claimCodeupERC20(user_);
            return;
        }
        if (!codeup.isClaimAllowed(user_)) {
            vm.expectRevert(Codeup.ClaimForbidden.selector);
            codeup.claimCodeupERC20(user_);
            return;
        }

        uint256 initialCodeupERC20Balance = codeupERC20.balanceOf(user_);
        codeup.claimCodeupERC20(user_);
        assertEq(codeupERC20.balanceOf(user_), initialCodeupERC20Balance + TOKEN_AMOUNT_FOR_WINNER);
        assertTrue(codeup.isClaimed(user_));
    }

    function _maxUpgradeAndAssert(address user_) internal {
        for (uint i = 0; i < 8; i++) {
            for (uint j = 0; j < 5; j++) {
                _upgradeTowerAndAssert(user_, i);
            }
            _upgradeTowerAndAssert(user_, i); // asserting that it reverts for 6th builder
        }
        _upgradeTowerAndAssert(user_, 8); // asserting that it reverts for 8th floor
        _claimCodeupERC20AndAssert(user_);
        _claimCodeupERC20AndAssert(user_); // asserting claiming again reverts
    }

    function _expectedMinIncrease(Codeup.Tower memory tower) internal view returns (uint256 min) {
        min = tower.yields > 0 ? (block.timestamp / 60) - (tower.timestamp / 60) : 0;
        min = min + tower.min > 24 ? 24 - tower.min : min;
    }

    function _expectedYield(Codeup.Tower memory tower) internal view returns (uint256 yield) {
        uint256 min = _expectedMinIncrease(tower);
        yield = min * tower.yields;
        console.log("MIN", min);
        console.log("EXPECTED YIELD: ", yield);
    }

    function _getUpgradePrice(
        uint256 _floorId,
        uint256 _builderId
    ) internal pure returns (uint256) {
        if (_builderId == 1)
            return [434, 21, 42, 77, 168, 280, 504, 630][_floorId];
        if (_builderId == 2)
            return [7, 11, 21, 35, 63, 112, 280, 350][_floorId];
        if (_builderId == 3)
            return [9, 14, 28, 49, 84, 168, 336, 560][_floorId];
        if (_builderId == 4)
            return [11, 21, 35, 63, 112, 210, 364, 630][_floorId];
        if (_builderId == 5)
            return [15, 28, 49, 84, 140, 252, 448, 1120][_floorId];
    }

    function _getYield(
        uint256 _floorId,
        uint256 _builderId
    ) internal pure returns (uint256) {
        if (_builderId == 1)
            return [467, 226, 294, 606, 1163, 1617, 2267, 1760][_floorId];
        if (_builderId == 2)
            return [41, 37, 121, 215, 305, 415, 890, 389][_floorId];
        if (_builderId == 3)
            return [170, 51, 218, 317, 432, 351, 357, 1030][_floorId];
        if (_builderId == 4)
            return [218, 92, 270, 410, 596, 858, 972, 1045][_floorId];
        if (_builderId == 5)
            return [239, 98, 381, 551, 742, 1007, 1188, 2416][_floorId];
    }

    function _getTower(address user_) internal view returns (Codeup.Tower memory tower) {
        (
            tower.gameETH,
            tower.gameETHForWithdraw,
            tower.gameETHCollected,
            tower.yields,
            tower.timestamp,
            tower.min,
            tower.totalGameETHSpend,
            tower.totalGameETHReceived
        ) = codeup.towers(user_);
        tower.builders = codeup.getBuilders(user_);
        console.log(string.concat("TOWER:, gameETH: ", vm.toString(tower.gameETH), ", gameETHForWithdraw: ", vm.toString(tower.gameETHForWithdraw), ", gameETHCollected: ", vm.toString(tower.gameETHCollected), ", yields: ", vm.toString(tower.yields), ", timestamp: ", vm.toString(tower.timestamp), ", min: ", vm.toString(tower.min), ", totalGameETHSpend: ", vm.toString(tower.totalGameETHSpend), ", totalGameETHReceived: ", vm.toString(tower.totalGameETHReceived)));
    }

    function _skip(uint256 seconds_) internal {
        skip(seconds_);
        console.log("skipped: ", seconds_);
    }
}
