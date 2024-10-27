// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IWETH, IERC20} from "./interfaces/IWETH.sol";
import {IUniswapV2Router} from "./interfaces/IUniswapV2Router.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

///░█████╗░░█████╗░██████╗░███████╗██╗░░░██╗██████╗░░░░███████╗████████╗██╗░░██╗
///██╔══██╗██╔══██╗██╔══██╗██╔════╝██║░░░██║██╔══██╗░░░██╔════╝╚══██╔══╝██║░░██║
///██║░░╚═╝██║░░██║██║░░██║█████╗░░██║░░░██║██████╔╝░░░█████╗░░░░░██║░░░███████║
///██║░░██╗██║░░██║██║░░██║██╔══╝░░██║░░░██║██╔═══╝░░░░██╔══╝░░░░░██║░░░██╔══██║
///╚█████╔╝╚█████╔╝██████╔╝███████╗╚██████╔╝██║░░░░░██╗███████╗░░░██║░░░██║░░██║
///░╚════╝░░╚════╝░╚═════╝░╚══════╝░╚═════╝░╚═╝░░░░░╚═╝╚══════╝░░░╚═╝░░░╚═╝░░╚═╝

/// @title Codeup contract
/// @notice This contract is used for the Codeup game
contract Codeup is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Tower {
        uint256 gameETH; /// @notice User's gameETH balance
        uint256 gameETHForWithdraw; /// @notice User's available for withdraw balance
        uint256 gameETHCollected; /// @notice User's earned gameETH balance
        uint256 yields; /// @notice User's yields
        uint256 timestamp; /// @notice User's registration timestamp
        uint256 min; /// @notice User's time in the tower
        uint256 totalGameETHSpent; /// @notice User's total gameETH spent
        uint256 totalGameETHReceived; /// @notice User's total gameETH received
        uint8[8] builders; /// @notice User's builders count on each floor
    }
    /// @notice Max amount of gameETH available for buying
    uint256 public constant MAX_GAMEETH_FOR_BUYING = 78650;
    /// @notice Precision for math operations
    uint256 private constant PRECISION = 100;
    /// @notice CodeupERC20 token amount for winner
    uint256 private constant TOKEN_AMOUNT_FOR_WINNER = 1 ether;
    /// @notice Token amount in ETH needed for first liquidity
    uint256 private constant MAX_FIRST_LIQUIDITY_AMOUNT = 0.001 ether;
    /// @notice Amount of game token for first liquidity
    uint256 private constant FIRST_LIQUIDITY_GAME_TOKEN = 10 ether;
    /// @notice Withdraw commission 33% for rewards pool, 33% for liquidity pool
    uint256 private constant WITHDRAW_COMMISSION = 66;
    /// @notice Deposit commission 10% for liquidity pool
    uint256 private constant DEPOSIT_COMMISSION = 10;
    /// @notice Min amount for adding liquidity
    uint256 private constant MIN_AMOUNT_FOR_ADDING_LIQUIDITY = 0.0001 ether;
    /// @notice Minutes in hour
    uint256 private constant MINUTES_IN_HOUR = 60;
    /// @notice Max minutes for sync tower
    uint256 private constant MAX_MINUTES_FOR_SYNC = 24;

    /// @notice UniswapV2Router address
    address public immutable uniswapV2Router;
    /// @notice UniswapV2Factory address
    address public immutable uniswapV2Factory;
    /// @notice CodeupERC20 token address
    address public immutable codeupERC20;
    /// @notice WETH address
    address public immutable weth;
    /// @notice gameETH price
    uint256 public immutable gameETHPrice;
    /// @notice gameETH for withdraw rate
    uint256 public immutable gameETHForWithdrawRate;
    /// @notice Start date
    uint256 public immutable startUNIX;
    /// @notice Total builders count
    uint256 public totalBuilders;
    /// @notice Total towers count
    uint256 public totalTowers;
    /// @notice Total invested amount
    uint256 public totalInvested;
    /// @notice UniswapV2 pool address WETH/CodeupERC20
    address public uniswapV2Pool;
    /// @notice Last liquidity added timestamp
    uint256 public lastLiquidityAdded;

    /// @notice account claim status
    mapping(address => bool) public isClaimed;
    /// @notice User's tower info
    mapping(address => Tower) public towers;

    /// @notice Error messages
    error ZeroValue();
    error IncorrectBuilderId();
    error NotStarted();
    error TransferFailed();
    error MaxFloorsReached();
    error MaxGameETHReached();
    error NeedToBuyPreviousBuilder();
    error ClaimForbidden();
    error AlreadyClaimed();
    error OwnerIsNotAllowed();
    error LiquidityAddedRecently();
    error PoolNotCreated();

    /// @notice Emitted when user created tower
    /// @param user User's address
    event TowerCreated(address indexed user);
    /// @notice  Emitted when user added gameETH to the tower
    /// @param user User's address
    /// @param gameETHAmount gameETH amount
    /// @param ethAmount Spent ETH amount
    event AddGameETH(
        address indexed user,
        uint256 gameETHAmount,
        uint256 ethAmount,
        uint256 ethForPool
    );
    /// @notice Emitted when user withdraw gameETH
    /// @param user User's address
    /// @param amount gameETH amount
    event Withdraw(address indexed user, uint256 amount);
    /// @notice Emitted when user collect earned gameETH
    /// @param user User's address
    /// @param amount gameETH amount
    event Collect(address indexed user, uint256 amount);
    /// @notice Emitted when user upgrade tower
    /// @param user User's address
    /// @param floorId Floor id
    /// @param gameETH gameETH amount
    /// @param yields Yield amount
    event UpgradeTower(
        address indexed user,
        uint256 floorId,
        uint256 gameETH,
        uint256 yields
    );
    /// @notice Emitted when user sync tower
    /// @param user User's address
    /// @param yields Yield amount
    /// @param mins  number of minutes
    event SyncTower(address indexed user, uint256 yields, uint256 mins);
    /// @notice Emitted when uniswapV2 pool created
    /// @param pool Pool address
    event PoolCreated(address indexed pool);
    /// @notice Emitted when game token claimed
    /// @param account Account address
    /// @param amount Token amount
    event TokenClaimed(address indexed account, uint256 amount);
    /// @notice Emitted when liquidity locked
    event LiquidityLocked(uint256 indexed amount);
    /// @notice Emitted when liquidity added
    event LiquidityAdded(uint256 indexed amountA, uint256 indexed amountB);
    /// @notice Emitted when buy CodeupERC20
    event BuyCodeupERC20(uint256 indexed amount);

    /// @notice Contract constructor
    /// @param _startDate Start date
    /// @param _gameETHPrice gameETH price
    /// @param _uniswapV2Router Weighted pool factory address
    /// @param _codeupERC20 CodeupERC20 address
    constructor(
        uint256 _startDate,
        uint256 _gameETHPrice,
        address _uniswapV2Router,
        address _codeupERC20
    ) payable {
        _checkValue(_gameETHPrice);
        _checkValue(_startDate);
        _checkValue(_gameETHPrice / 1000);
        startUNIX = _startDate;
        gameETHPrice = _gameETHPrice;
        gameETHForWithdrawRate = _gameETHPrice / 1000;
        codeupERC20 = _codeupERC20;
        uniswapV2Router = _uniswapV2Router;
        weth = IUniswapV2Router(_uniswapV2Router).WETH();
        uniswapV2Factory = IUniswapV2Router(_uniswapV2Router).factory();
        lastLiquidityAdded = block.timestamp;
    }

    /// @notice Modifier for checking that game already started
    modifier onlyIfStarted() {
        require(block.timestamp > startUNIX, NotStarted());
        _;
    }

    /// @notice Add gameETH to the tower
    function addGameETH() external payable onlyIfStarted {
        uint256 tokenAmount = msg.value;
        uint256 gameETH = tokenAmount / gameETHPrice;
        _checkValue(gameETH);
        _checkMaxGameETH(msg.sender, gameETH);
        address user = msg.sender;
        uint256 totalInvestedBefore = totalInvested;
        totalInvested = totalInvestedBefore + tokenAmount;

        Tower storage tower = towers[user];
        if (tower.timestamp == 0) {
            totalTowers++;
            tower.timestamp = block.timestamp;
            emit TowerCreated(user);
        }
        tower.gameETH += gameETH;

        uint256 ethAmount = (tokenAmount * DEPOSIT_COMMISSION) / PRECISION;
        IWETH(weth).deposit{value: ethAmount}();
        emit AddGameETH(user, gameETH, tokenAmount, ethAmount);
    }

    /// @notice Withdraw earned gameETH from the tower
    function withdraw() external onlyIfStarted {
        address user = msg.sender;
        Tower storage tower = towers[user];
        uint256 contractBalance = _selfBalance();
        uint256 gameETH = tower.gameETHForWithdraw * gameETHForWithdrawRate;
        uint256 amount = contractBalance < gameETH ? contractBalance : gameETH;

        tower.gameETHForWithdraw -=
            (amount / gameETHForWithdrawRate) +
            (amount % gameETHForWithdrawRate == 0 ? 0 : 1);

        if (amount >= 1) {
            uint256 commission = (amount * WITHDRAW_COMMISSION) / PRECISION;
            amount -= commission;
            uint256 amountForPool = commission >> 1;
            IWETH(weth).deposit{value: amountForPool}();
        }

        (bool success, ) = user.call{value: amount}("");
        require(success, TransferFailed());
        emit Withdraw(user, amount);
    }

    /// @notice Collect earned gameETH from the tower to game balance
    function collect() external onlyIfStarted {
        address user = msg.sender;
        Tower storage tower = towers[user];
        _syncTower(user);
        tower.min = 0;
        uint256 gameETHCollected = tower.gameETHCollected;
        tower.gameETHForWithdraw += gameETHCollected;
        tower.gameETHCollected = 0;
        emit Collect(user, gameETHCollected);
    }

    /// @notice Reinvest earned gameETH to the tower
    function reinvest() external nonReentrant onlyIfStarted {
        address user = msg.sender;
        uint256 contractBalance = _selfBalance();
        Tower storage tower = towers[user];
        uint256 gameETHForWithdrawCached = tower.gameETHForWithdraw;
        _checkValue(gameETHForWithdrawCached);
        uint256 maxGameEthForBuy = getMaxGameEthForBuying(user);
        uint256 withdrawRate = gameETHForWithdrawRate;
        uint256 predictedGameETH = (gameETHForWithdrawCached * withdrawRate) /
            gameETHPrice;
        uint256 availableGameETHForReinvest = predictedGameETH <=
            maxGameEthForBuy
            ? gameETHForWithdrawCached
            : maxGameEthForBuy * (gameETHPrice / withdrawRate);
        uint256 gameETHForWithdraw = availableGameETHForReinvest * withdrawRate;
        uint256 amount = contractBalance < gameETHForWithdraw
            ? contractBalance
            : gameETHForWithdraw;

        tower.gameETHForWithdraw -=
            (amount / gameETHForWithdrawRate) +
            (amount % gameETHForWithdrawRate == 0 ? 0 : 1);

        emit Withdraw(user, amount);

        uint256 gameETH = amount / gameETHPrice;
        _checkValue(gameETH);
        uint256 totalInvestedBefore = totalInvested;
        totalInvested = totalInvestedBefore + amount;
        tower.gameETH += gameETH;

        uint256 ethAmount = (amount * DEPOSIT_COMMISSION) / PRECISION;
        IWETH(weth).deposit{value: ethAmount}();
        emit AddGameETH(user, gameETH, amount, ethAmount);
    }

    /// @notice Upgrade tower
    /// @param _floorId Floor id
    function upgradeTower(uint256 _floorId) external onlyIfStarted {
        require(_floorId < 8, MaxFloorsReached());
        address user = msg.sender;
        Tower storage tower = towers[user];
        if (_floorId != 0) {
            require(
                tower.builders[_floorId - 1] == 5,
                NeedToBuyPreviousBuilder()
            );
        }
        _syncTower(user);

        tower.builders[_floorId]++;
        totalBuilders++;
        uint256 buildersCount = tower.builders[_floorId];
        uint256 gameETHSpent = _getUpgradePrice(_floorId, buildersCount);
        tower.gameETH -= gameETHSpent;
        tower.totalGameETHSpent += gameETHSpent;
        uint256 yield = _getYield(_floorId, buildersCount);
        tower.yields += yield;
        emit UpgradeTower(msg.sender, _floorId, gameETHSpent, yield);
    }

    /// @notice Function perform claiming of game token
    /// Only users with 40 builders can claim game token
    /// Claiming possible only once.
    /// @param _account Account address
    /// @param _amountAMin Min amount of WETH for adding liquidity
    /// @param _amountBMin Min amount of CodeupERC20 for adding liquidity
    /// @param _amountOutMin Min amount of CodeupERC20 for buying
    function claimCodeupERC20(
        address _account,
        uint256 _amountAMin,
        uint256 _amountBMin,
        uint256 _amountOutMin
    ) external onlyIfStarted {
        require(isClaimAllowed(_account), ClaimForbidden());
        require(!isClaimed[_account], AlreadyClaimed());
        address currentContract = address(this);
        address wethMemory = weth;
        address codeupERC20Memory = codeupERC20;
        address routerMemory = uniswapV2Router;
        uint256 wethBalance = IERC20(wethMemory).balanceOf(currentContract);

        /// if pool not created, create pool
        if (uniswapV2Pool == address(0)) {
            uint256 maxFirstLiquidity = MAX_FIRST_LIQUIDITY_AMOUNT;
            uint256 firstLiquidity = wethBalance > maxFirstLiquidity
                ? maxFirstLiquidity
                : wethBalance;

            _addLiquidity(
                routerMemory,
                wethMemory,
                codeupERC20Memory,
                firstLiquidity,
                FIRST_LIQUIDITY_GAME_TOKEN,
                _amountAMin,
                _amountBMin,
                currentContract
            );

            uniswapV2Pool = IUniswapV2Factory(uniswapV2Factory).getPair(
                wethMemory,
                codeupERC20Memory
            );

            lastLiquidityAdded = block.timestamp;

            emit PoolCreated(uniswapV2Pool);
        } else {
            // buy codeupERC20 for WETH
            if (wethBalance >= MIN_AMOUNT_FOR_ADDING_LIQUIDITY) {
                uint256[] memory swapResult = _buyCodeupERC20(
                    routerMemory,
                    wethMemory,
                    codeupERC20Memory,
                    wethBalance >> 1,
                    _amountOutMin,
                    currentContract
                );

                _addLiquidity(
                    routerMemory,
                    wethMemory,
                    codeupERC20Memory,
                    swapResult[0],
                    swapResult[1],
                    _amountAMin,
                    _amountBMin,
                    currentContract
                );

                lastLiquidityAdded = block.timestamp;
            }
        }
        /// Set claim status to true, user can't claim token again.
        /// Claiming possible only once.
        isClaimed[_account] = true;
        /// Lock LP tokens
        _lockLP(currentContract);
        /// Transfer CodeupERC20 amount to the user
        uint256 tokenAmountForWinner = TOKEN_AMOUNT_FOR_WINNER;
        IERC20(codeupERC20Memory).safeTransfer(_account, tokenAmountForWinner);
        emit TokenClaimed(_account, tokenAmountForWinner);
    }

    /// @notice Function for force adding liquidity to pool. Can be called only once per week.
    /// @param _amountAMin Min amount of WETH for adding liquidity
    /// @param _amountBMin Min amount of CodeupERC20 for adding liquidity
    /// @param _amountOutMin Min amount of CodeupERC20 for buying
    function forceAddLiquidityToPool(
        uint256 _amountAMin,
        uint256 _amountBMin,
        uint256 _amountOutMin
    ) external {
        require(uniswapV2Pool != address(0), PoolNotCreated());
        address currentContract = address(this);
        address wethMemory = weth;
        address codeupERC20Memory = codeupERC20;
        address routerMemory = uniswapV2Router;
        uint256 wethBalance = IERC20(wethMemory).balanceOf(currentContract);
        _checkValue(wethBalance);
        require(
            block.timestamp - lastLiquidityAdded > 1 weeks,
            LiquidityAddedRecently()
        );

        uint256[] memory swapResult = _buyCodeupERC20(
            routerMemory,
            wethMemory,
            codeupERC20Memory,
            wethBalance >> 1,
            _amountOutMin,
            currentContract
        );

        _addLiquidity(
            routerMemory,
            wethMemory,
            codeupERC20Memory,
            swapResult[0],
            swapResult[1],
            _amountAMin,
            _amountBMin,
            currentContract
        );
        lastLiquidityAdded = block.timestamp;
    }

    /// @notice View function for checking if user can claim CodeupERC20
    /// @param _account Account address
    function isClaimAllowed(address _account) public view returns (bool) {
        uint8[8] memory builders = getBuilders(_account);
        uint8 count;
        for (uint8 i = 0; i < 8; i++) {
            count += builders[i];
        }

        if (count == 40) {
            return true;
        } else {
            return false;
        }
    }

    /// @notice Get user tower builders info
    /// @param _user User's address
    function getBuilders(address _user) public view returns (uint8[8] memory) {
        return towers[_user].builders;
    }

    /// @notice Calc user max available gameETH for buying
    /// @param _account User's address
    /// @return Max available gameETH for buying
    function getMaxGameEthForBuying(
        address _account
    ) public view returns (uint256) {
        Tower memory tower = towers[_account];
        uint256 totalGameETH = tower.gameETH + tower.totalGameETHSpent;
        return MAX_GAMEETH_FOR_BUYING - totalGameETH;
    }

    /// @notice Sync user tower info
    /// @param _user User's address
    function _syncTower(address _user) internal {
        Tower storage tower = towers[_user];
        _checkValue(tower.timestamp);
        if (tower.yields >= 1) {
            uint256 min = (block.timestamp - tower.timestamp) / MINUTES_IN_HOUR;
            if (min + tower.min > MAX_MINUTES_FOR_SYNC) {
                min = MAX_MINUTES_FOR_SYNC - tower.min;
            }
            uint256 yield = min * tower.yields;

            tower.gameETHCollected += yield;
            tower.totalGameETHReceived += yield;
            tower.min += min;
            emit SyncTower(_user, yield, min);
        }
        tower.timestamp = block.timestamp;
    }

    /// @notice Helper function for getting upgrade price for the floor and builder
    /// @param _floorId Floor id
    /// @param _builderId Builder id
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
        revert IncorrectBuilderId();
    }

    /// @notice Helper function for getting yield for the floor and builder
    /// @param _floorId Floor id
    /// @param _builderId Builder id
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
        revert IncorrectBuilderId();
    }

    /// @notice Function performs buying CodeupERC20 from V2 pool
    function _buyCodeupERC20(
        address _router,
        address _weth,
        address _codeupERC20,
        uint256 _wethAmount,
        uint256 _amountOutMin,
        address _currentContract
    ) private returns (uint256[] memory swapResult) {
        address[] memory path = new address[](2);
        path[0] = _weth;
        path[1] = _codeupERC20;
        uint256[] memory amounts = IUniswapV2Router(_router).getAmountsOut(
            _wethAmount,
            path
        );
        IERC20(_weth).safeIncreaseAllowance(_router, _wethAmount);
        swapResult = IUniswapV2Router(_router).swapExactTokensForTokens(
            amounts[0],
            _amountOutMin,
            path,
            _currentContract,
            block.timestamp
        );
        emit BuyCodeupERC20(swapResult[1]);
    }

    /// @notice Function perfoms adding liquidity to uniswapV2Pool
    function _addLiquidity(
        address _router,
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _currentContract
    ) private {
        IERC20(_tokenA).safeIncreaseAllowance(_router, _amountADesired);
        IERC20(_tokenB).safeIncreaseAllowance(_router, _amountBDesired);
        IUniswapV2Router(_router).addLiquidity(
            _tokenA,
            _tokenB,
            _amountADesired,
            _amountBDesired,
            _amountAMin,
            _amountBMin,
            _currentContract,
            block.timestamp
        );
        emit LiquidityAdded(_amountADesired, _amountBDesired);
    }

    /// @notice Function for locking LP tokens.
    /// If contract has LP tokens, it will send them to address(0)
    function _lockLP(address _currentContract) private {
        address uniswapV2PoolCached = uniswapV2Pool;
        uint256 lpBalance = IERC20(uniswapV2PoolCached).balanceOf(
            _currentContract
        );
        if (lpBalance >= 1) {
            IERC20(uniswapV2PoolCached).safeTransfer(address(0), lpBalance);
        }
        emit LiquidityLocked(lpBalance);
    }

    /// @notice Function for getting contract balance
    function _selfBalance() private view returns (uint256 self) {
        assembly {
            self := selfbalance()
        }
    }

    /// @notice Function for checking max gameETH for buying
    function _checkMaxGameETH(address _account, uint256 _gameETH) private view {
        Tower memory tower = towers[_account];
        uint256 totalGameETH = tower.gameETH +
            _gameETH +
            tower.totalGameETHSpent;
        require(totalGameETH <= MAX_GAMEETH_FOR_BUYING, MaxGameETHReached());
    }

    /// @notice Function for checking value is not zero
    function _checkValue(uint256 _argument) private pure {
        require(_argument != 0, ZeroValue());
    }
}
