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
    uint256 constant gamePrice = 0.0000001 ether;
    uint256 constant gameETHForWithdrawRate = gamePrice / 1000;
    uint256 private constant WITHDRAW_COMMISSION = 66;
    uint256 private constant TOKEN_AMOUNT_FOR_WINNER = 1 ether;
    uint256 private constant MAX_GAMEETH_FOR_BUYING = 78650;
    uint256 private constant MAX_ETH_FOR_BUYING = MAX_GAMEETH_FOR_BUYING * gamePrice;
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public user4 = makeAddr("user4");
    address[4] public users = [user1, user2, user3, user4];

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
        uint256 depositValue_ = MAX_ETH_FOR_BUYING;
        vm.expectRevert(Codeup.NotStarted.selector);
        codeup.addGameETH{value: depositValue_}();
    }

    function test_AddGameEth_RevertDueToMaxGameETHReached() public {
        skip(101);
        deal(user1, MAX_ETH_FOR_BUYING + 1);
        _changePrank(user1);
        _addGameEthAndAssert(user1, MAX_ETH_FOR_BUYING + 1);

        deal(user2, MAX_ETH_FOR_BUYING + gamePrice);
        _changePrank(user2);
        uint256 firstDepositValue_ = MAX_ETH_FOR_BUYING / 2;
        uint256 secondDepositValue_ = MAX_ETH_FOR_BUYING - firstDepositValue_ + gamePrice;
        _addGameEthAndAssert(user2, firstDepositValue_);
        _addGameEthAndAssert(user2, secondDepositValue_);
    }

    function test_AddGameEth_Success() public {
        uint256 depositValue_ = MAX_ETH_FOR_BUYING / 2;
        deal(user1, 2 * depositValue_);
        _changePrank(user1);
        skip(101);
        _addGameEthAndAssert(user1, depositValue_);
        _addGameEthAndAssert(user1, depositValue_);
    }
    
    function test_withdraw_Success() public {
        uint256 depositValue_ = MAX_ETH_FOR_BUYING;
        deal(user1, depositValue_);
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
        uint256 depositValue_ = MAX_ETH_FOR_BUYING / 2;
        deal(user1, depositValue_);
        _changePrank(user1);
        _skip(101);
        _addGameEthAndAssert(user1, depositValue_);
        _upgradeTowerAndAssert(user1, 0);
        _skip(24 * 60);
        _collectAndAssert(user1);
        _reinvestAndAssert(user1);
        assertEq(0, _withdrawAndAssert(user1));
    }

    function test_forceAddLiquidityToPool() public {
        deal(user1, 2 ether);
        _changePrank(user1);
        skip(101);
        uint256 depositValue_ = MAX_ETH_FOR_BUYING;
        _addGameEthAndAssert(user1, depositValue_);
        _maxUpgradeAndAssert(user1);
        _claimCodeupERC20AndAssert(user1);

        deal(user2, 2 ether);
        _changePrank(user2);
        _addGameEthAndAssert(user2, depositValue_);
        _maxUpgradeAndAssert(user2);

        skip(1 weeks + 1);
        codeup.forceAddLiquidityToPool(0, 0, 0);
    }

    function testFuzz_withdraw_capped(uint256 collectTime_, uint256 contractBalance_) public {
        _skip(101);
        deal(user1, MAX_ETH_FOR_BUYING);
        _changePrank(user1);
        _addGameEthAndAssert(user1, MAX_ETH_FOR_BUYING);
        _upgradeTowerAndAssert(user1, 0);
        _skip(collectTime_ % 24 minutes);
        _collectAndAssert(user1);
        Codeup.Tower memory tower = _getTower(user1);
        deal(address(codeup), contractBalance_ % (tower.gameETHForWithdraw * gameETHForWithdrawRate + 1));
        _withdrawAndAssert(user1);
    }

    function testFuzz_reinvest_capped(uint256 deposit, uint256 collectTime_, uint248 contractBalanceUint248_) public {
        deposit = deposit % (MAX_ETH_FOR_BUYING);
        collectTime_ = collectTime_ % (24 minutes + 1);
        uint256 contractBalance_ = (contractBalanceUint248_ + (MAX_ETH_FOR_BUYING / 2)) % (MAX_ETH_FOR_BUYING + 1);
        vm.assume(collectTime_ >= 1 minutes);
        vm.assume(deposit >= gamePrice * 4340);
        vm.assume(contractBalance_ >= gamePrice);
        _skip(101);
        deal(user1, MAX_ETH_FOR_BUYING);
        _changePrank(user1);
        _addGameEthAndAssert(user1, deposit);
        _maxUpgradeAndAssert(user1);
        for (uint i = 0; i < 10; i++) {
            _skip(24 minutes);
            _collectAndAssert(user1);
        }
        Codeup.Tower memory tower = _getTower(user1);
        uint256 ethReinvested = tower.gameETHForWithdraw * gameETHForWithdrawRate;
        uint256 maxEthForBuying = codeup.getMaxGameEthForBuying(user1) * gamePrice;
        if (ethReinvested > maxEthForBuying) ethReinvested = maxEthForBuying;
        deal(address(codeup), contractBalance_);
        _reinvestAndAssert(user1);
    }

    function test_reinvest_capped() public {
        uint256 deposit = 58305058960432297476810392199415083331739938700;
        uint256 collectTime_ = 414058577057335;
        uint256 contractBalance_ = 18844130445163882458845258742946847;
        deposit = deposit % (MAX_ETH_FOR_BUYING + 1);
        collectTime_ = collectTime_ % (24 minutes + 1);
        vm.assume(collectTime_ > 1 minutes);
        vm.assume(deposit > gamePrice * 4340);
        vm.assume(deposit < MAX_ETH_FOR_BUYING);
        _skip(101);
        deal(user1, MAX_ETH_FOR_BUYING);
        _changePrank(user1);
        _addGameEthAndAssert(user1, deposit);
        _upgradeTowerAndAssert(user1, 0);
        _skip(collectTime_);
        _collectAndAssert(user1);
        Codeup.Tower memory tower = _getTower(user1);
        uint256 ethReinvested = tower.gameETHForWithdraw * gameETHForWithdrawRate;
        uint256 maxEthForBuying = codeup.getMaxGameEthForBuying(user1) * gamePrice;
        if (ethReinvested > maxEthForBuying) ethReinvested = maxEthForBuying;
        deal(address(codeup), contractBalance_);
        _reinvestAndAssert(user1);
    }

    struct Params_testFuzz_claimCodeupERC20_Success {
        address user;
        uint256 amount;
        bool claim;
    }

    function testFuzz_claimCodeupERC20_Success(Params_testFuzz_claimCodeupERC20_Success[20] memory params) public {
        _skip(101);
        for (uint i = 0; i < params.length; i++) {
            address user_ = params[i].user;
            uint256 amount_ = params[i].amount;
            bool claim_ = params[i].claim;
            if (user_ == address(codeup) || uint160(user_) < 10) continue;
            uint256 depositValue_ = claim_ ? MAX_ETH_FOR_BUYING : amount_ % (MAX_ETH_FOR_BUYING + 1);
            uint256 maxEthForBuying = codeup.getMaxGameEthForBuying(user_);
            if (depositValue_ > maxEthForBuying) depositValue_ = maxEthForBuying;
            if (depositValue_ == 0) continue;
            deal(user_, depositValue_);
            _changePrank(user_);
            _addGameEthAndAssert(user_, depositValue_);
            if (!claim_) continue;
            _maxUpgradeAndAssert(user_);
            _claimCodeupERC20AndAssert(user_);
        }
    }

    function test_POC_DepositIsWorthMoreJustAfter16Hours() public {
        _skip(101);
        for (uint256 i = 1; i < users.length; i++) {
            deal(users[i], MAX_ETH_FOR_BUYING);
            _changePrank(users[i]);
            _addGameEthAndAssert(users[i], MAX_ETH_FOR_BUYING);
        }
        uint256 depositValue_ = 78650 * gamePrice; // 7865 is the game eth needed to buy all towers
        assertEq(depositValue_, 0.007865 ether);
        deal(user1, depositValue_);
        _changePrank(user1);
        _addGameEthAndAssert(user1, depositValue_);
        _maxUpgradeAndAssert(user1);
        _claimCodeupERC20AndAssert(user1);

        for (uint i = 0; i < 40; i++) {
            _skip(24 minutes);
            _collectAndAssert(user1);            
        }
        uint256 withdrawnValue_ = _withdrawAndAssert(user1);
        assertEq(withdrawnValue_, 0.0081019008 ether);
        assertGt(withdrawnValue_, depositValue_);
    }

    function test_POC_INSUFFICIENT_LIQUIDITY_MINTED_DoesNotRevert() public {
        _skip(101);
        uint256 depositValue_ = 78650 * gamePrice; // 7865 is the game eth needed to buy all towers
        assertEq(depositValue_, 0.007865 ether);
        deal(user1, depositValue_);
        _changePrank(user1);
        _addGameEthAndAssert(user1, depositValue_);
        _maxUpgradeAndAssert(user1);
        _claimCodeupERC20AndAssert(user1);

        assertEq(depositValue_, 0.007865 ether);
        deal(user2, depositValue_);
        _changePrank(user2);
        _addGameEthAndAssert(user2, depositValue_);
        _maxUpgradeAndAssert(user2);
        deal(address(weth), address(codeup), 2);
        codeup.claimCodeupERC20(user2, 0, 0, 0);
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
        if (depositValue_ / gamePrice > codeup.getMaxGameEthForBuying(user_) ) {
            vm.expectRevert(Codeup.MaxGameETHReached.selector);
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
        assertEq(codeup.totalInvested(), depositValue_ + initialTotalInvested, "totalInvested");
        assertEq(codeup.totalTowers(), initialTower.timestamp == 0 ? initialTotalTowers + 1 : initialTotalTowers, "totalTowers");
        assertEq(finalTower.timestamp, initialTower.timestamp == 0 ? block.timestamp : initialTower.timestamp, "timestamp");
        assertEq(weth.balanceOf(address(codeup)), depositValue_ / 10 + initialWethBalance, "wethBalance");
        assertEq(address(codeup).balance, initialETHValue + depositValue_ - depositValue_ / 10, "ethValue");
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
        assertEq(finalTower.gameETHForWithdraw, initialTower.gameETHForWithdraw - (withdrawValue + gameETHForWithdrawRate - 1) / gameETHForWithdrawRate);
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
        assertEq(finalTower.totalGameETHSpent, initialTower.totalGameETHSpent + expectedPrice, "totalGameETHSpent");
        assertEq(finalTower.gameETH, initialTower.gameETH - expectedPrice, "gameETH");
        assertEq(finalTower.yields, initialTower.yields + _getYield(floorId_, finalTower.builders[floorId_]), "yields");
    }

    function _reinvestAndAssert(address user_) internal {
        console.log("REINVEST", user_);
        Codeup.Tower memory initialTower = _getTower(user_);
        uint256 initialTotalInvested = codeup.totalInvested();
        uint256 initialWethBalance = weth.balanceOf(address(codeup));
        uint256 initialETHValue = address(codeup).balance;
        uint256 maxEthForBuying = codeup.getMaxGameEthForBuying(user_) * gamePrice;
        codeup.reinvest();
        Codeup.Tower memory finalTower = _getTower(user_);
        uint256 ethReinvested = initialTower.gameETHForWithdraw * gameETHForWithdrawRate;
        if (ethReinvested > maxEthForBuying) ethReinvested = maxEthForBuying;
        if (ethReinvested > initialETHValue) ethReinvested = initialETHValue;
        uint256 gameETHReceived = ethReinvested / gamePrice;
        uint256 wethDeposit = ethReinvested * 10 / 100;
        assertEq(finalTower.gameETHForWithdraw, initialTower.gameETHForWithdraw - (ethReinvested + gameETHForWithdrawRate - 1) / gameETHForWithdrawRate, "gameETHForWithdraw");
        assertEq(finalTower.gameETH, initialTower.gameETH + gameETHReceived, "gameETH");
        assertEq(codeup.totalInvested(), initialTotalInvested + ethReinvested, "totalInvested");
        assertEq(weth.balanceOf(address(codeup)), initialWethBalance + wethDeposit, "wethBalance");
        assertEq(address(codeup).balance, initialETHValue - wethDeposit, "ethValue");
    }

    function _claimCodeupERC20AndAssert(address user_) internal {
        if (codeup.isClaimed(user_)) {
            vm.expectRevert(Codeup.AlreadyClaimed.selector);
            codeup.claimCodeupERC20(user_, 0, 0, 0);
            return;
        }
        if (!codeup.isClaimAllowed(user_)) {
            vm.expectRevert(Codeup.ClaimForbidden.selector);
            codeup.claimCodeupERC20(user_, 0, 0, 0);
            return;
        }

        uint256 initialCodeupERC20Balance = codeupERC20.balanceOf(user_);
        codeup.claimCodeupERC20(user_, 0, 0, 0);
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
    }

    function _expectedMinIncrease(Codeup.Tower memory tower) internal view returns (uint256 min) {
        min = tower.yields > 0 ? (block.timestamp - tower.timestamp) / 60 : 0;
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
            return [4340, 210, 420, 770, 1680, 2800, 5040, 6300][_floorId];
        if (_builderId == 2)
            return [70, 110, 210, 350, 630, 1120, 2800, 3500][_floorId];
        if (_builderId == 3)
            return [90, 140, 280, 490, 840, 1680, 3360, 5600][_floorId];
        if (_builderId == 4)
            return [110, 210, 350, 630, 1120, 2100, 3640, 6300][_floorId];
        if (_builderId == 5)
            return [150, 280, 490, 840, 1400, 2520, 4480, 11200][_floorId];
    }

    function _getYield(
        uint256 _floorId,
        uint256 _builderId
    ) internal pure returns (uint256) {
        if (_builderId == 1)
            return
                [4670, 2260, 2940, 6060, 11630, 16170, 22670, 17600][_floorId];
        if (_builderId == 2)
            return [410, 370, 1210, 2150, 3050, 4150, 8900, 3890][_floorId];
        if (_builderId == 3)
            return [1700, 510, 2180, 3170, 4320, 3510, 3570, 10300][_floorId];
        if (_builderId == 4)
            return [2180, 920, 2700, 4100, 5960, 8580, 9720, 10450][_floorId];
        if (_builderId == 5)
            return [2390, 980, 3810, 5510, 7420, 10070, 11880, 24160][_floorId];
    }

    function _getTower(address user_) internal view returns (Codeup.Tower memory tower) {
        (
            tower.gameETH,
            tower.gameETHForWithdraw,
            tower.gameETHCollected,
            tower.yields,
            tower.timestamp,
            tower.min,
            tower.totalGameETHSpent,
            tower.totalGameETHReceived
        ) = codeup.towers(user_);
        tower.builders = codeup.getBuilders(user_);
        console.log(string.concat("TOWER:, gameETH: ", vm.toString(tower.gameETH), ", gameETHForWithdraw: ", vm.toString(tower.gameETHForWithdraw), ", gameETHCollected: ", vm.toString(tower.gameETHCollected), ", yields: ", vm.toString(tower.yields), ", timestamp: ", vm.toString(tower.timestamp), ", min: ", vm.toString(tower.min), ", totalGameETHSpent: ", vm.toString(tower.totalGameETHSpent), ", totalGameETHReceived: ", vm.toString(tower.totalGameETHReceived)));
    }

    function _skip(uint256 seconds_) internal {
        skip(seconds_);
        console.log("skipped: ", seconds_);
    }
}
