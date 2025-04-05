// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TickMath} from "./TickMath.sol";
import {ICoin} from "./interfaces/ICoin.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IProtocolRewards} from "./interfaces/IProtocolRewards.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/**
 * @title Coin Contract
 * @notice 这是一个可升级的ERC20代币合约，实现了与Uniswap V3的集成和奖励分发功能
 * @dev 继承自ERC20Upgradeable、ReentrancyGuardUpgradeable和IERC721Receiver
 */
contract Coin is ICoin, ERC20Upgradeable, ReentrancyGuardUpgradeable, IERC721Receiver {
    // ============ 常量定义 ============

    /// @notice 代币的最大总供应量：10亿
    uint256 public constant MAX_TOTAL_SUPPLY = 1_000_000_000e18;

    /// @notice 流动性池初始供应量：9.8亿
    uint256 internal constant POOL_LAUNCH_SUPPLY = 980_000_000e18;

    /// @notice 创建者初始奖励：1000万
    uint256 internal constant CREATOR_LAUNCH_REWARD = 10_000_000e18;

    /// @notice 平台推荐人初始奖励：500万
    uint256 internal constant PLATFORM_REFERRER_LAUNCH_REWARD = 5_000_000e18;

    /// @notice 协议初始奖励：500万
    uint256 internal constant PROTOCOL_LAUNCH_REWARD = 5_000_000e18;

    /// @notice 最小订单大小：0.0000001 ETH
    uint256 public constant MIN_ORDER_SIZE = 0.0000001 ether;

    /// @notice 总费用基点：1%
    uint256 public constant TOTAL_FEE_BPS = 100;

    /// @notice 代币创建者费用占比：50%
    uint256 public constant TOKEN_CREATOR_FEE_BPS = 5000;

    /// @notice 协议费用占比：20%
    uint256 public constant PROTOCOL_FEE_BPS = 2000;

    /// @notice 平台推荐人费用占比：15%
    uint256 public constant PLATFORM_REFERRER_FEE_BPS = 1500;

    /// @notice 订单推荐人费用占比：15%
    uint256 public constant ORDER_REFERRER_FEE_BPS = 1500;

    /// @notice 代币创建者二级奖励占比：50%
    uint256 internal constant TOKEN_CREATOR_SECONDARY_REWARDS_BPS = 5000;

    /// @notice 平台推荐人二级奖励占比：25%
    uint256 internal constant PLATFORM_REFERRER_SECONDARY_REWARDS_BPS = 2500;

    /// @notice Uniswap V3池子费用：1%
    uint24 internal constant LP_FEE = 10000;

    /// @notice 流动性下限刻度
    int24 internal constant LP_TICK_LOWER = -219200;

    /// @notice 流动性上限刻度
    int24 internal constant LP_TICK_UPPER = 887200;

    // ============ 不可变状态变量 ============

    /// @notice WETH合约地址
    address public immutable WETH;

    /// @notice Uniswap V3位置管理器地址
    address public immutable nonfungiblePositionManager;

    /// @notice Uniswap V3交换路由器地址
    address public immutable swapRouter;

    /// @notice 协议费用接收地址
    address public immutable protocolFeeRecipient;

    /// @notice 协议奖励合约地址
    address public immutable protocolRewards;

    // ============ 可变状态变量 ============

    /// @notice 市场类型
    MarketType public marketType;

    /// @notice 平台推荐人地址
    address public platformReferrer;

    /// @notice Uniswap V3池子地址
    address public poolAddress;

    /// @notice 代币创建者地址
    address public tokenCreator;

    /// @notice 代币URI
    string public tokenURI;

    /// @notice LP代币ID
    uint256 public lpTokenId;

    /**
     * @notice 构造函数
     * @param _protocolFeeRecipient 协议费用接收地址
     * @param _protocolRewards 协议奖励合约地址
     * @param _weth WETH合约地址
     * @param _nonfungiblePositionManager Uniswap V3位置管理器地址
     * @param _swapRouter Uniswap V3交换路由器地址
     */
    constructor(
        address _protocolFeeRecipient,
        address _protocolRewards,
        address _weth,
        address _nonfungiblePositionManager,
        address _swapRouter
    ) initializer {
        // 验证地址不为零
        if (_protocolFeeRecipient == address(0)) revert AddressZero();
        if (_protocolRewards == address(0)) revert AddressZero();
        if (_weth == address(0)) revert AddressZero();
        if (_nonfungiblePositionManager == address(0)) revert AddressZero();
        if (_swapRouter == address(0)) revert AddressZero();

        // 初始化不可变状态变量
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolRewards = _protocolRewards;
        WETH = _weth;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
    }

    /**
     * @notice 初始化新代币
     * @param _creator 代币创建者地址
     * @param _platformReferrer 平台推荐人地址
     * @param _tokenURI 代币URI
     * @param _name 代币名称
     * @param _symbol 代币符号
     */
    function initialize(
        address _creator,
        address _platformReferrer,
        string memory _tokenURI,
        string memory _name,
        string memory _symbol
    ) public payable initializer {
        // 验证创建参数
        if (_creator == address(0)) revert AddressZero();
        if (_platformReferrer == address(0)) {
            _platformReferrer = protocolFeeRecipient;
        }

        // 初始化基础合约状态
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();

        // 初始化代币和市场状态
        marketType = MarketType.UNISWAP_POOL;
        platformReferrer = _platformReferrer;
        tokenCreator = _creator;
        tokenURI = _tokenURI;

        // 铸造总供应量
        _mint(address(this), MAX_TOTAL_SUPPLY);

        // 分发初始奖励
        _transfer(address(this), _creator, CREATOR_LAUNCH_REWARD);
        _transfer(address(this), platformReferrer, PLATFORM_REFERRER_LAUNCH_REWARD);
        _transfer(address(this), protocolFeeRecipient, PROTOCOL_LAUNCH_REWARD);

        // 批准向池子转移剩余供应量
        SafeERC20.safeIncreaseAllowance(this, address(nonfungiblePositionManager), POOL_LAUNCH_SUPPLY);

        // 部署池子
        _deployPool();

        // 如果发送了ETH，执行初始购买订单
        if (msg.value > 0) {
            buy(_creator, _creator, address(0), "", MarketType.UNISWAP_POOL, 0, 0);
        }
    }

    /**
     * @notice 使用ETH购买代币
     * @param recipient 代币接收地址
     * @param orderReferrer 订单推荐人地址
     * @param comment 订单备注
     * @param minOrderSize 最小订单大小（防滑点）
     * @param sqrtPriceLimitX96 Uniswap V3价格限制
     * @return 购买的代币数量
     */
    function buy(
        address recipient,
        address, /* refundRecipient - deprecated */
        address orderReferrer,
        string memory comment,
        MarketType, /* expectedMarketType - deprecated */
        uint256 minOrderSize,
        uint160 sqrtPriceLimitX96
    ) public payable nonReentrant returns (uint256) {
        // 验证订单大小
        if (msg.value < MIN_ORDER_SIZE) revert EthAmountTooSmall();
        if (recipient == address(0)) revert AddressZero();

        // 计算费用
        uint256 fee = _calculateFee(msg.value, TOTAL_FEE_BPS);
        uint256 totalCost = msg.value - fee;

        // 处理费用
        _disperseFees(fee, orderReferrer);

        // 将ETH转换为WETH并批准交换路由器
        IWETH(WETH).deposit{value: totalCost}();
        IWETH(WETH).approve(swapRouter, totalCost);

        // 设置交换参数
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(this),
            fee: LP_FEE,
            recipient: recipient,
            amountIn: totalCost,
            amountOutMinimum: minOrderSize,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // 执行交换
        uint256 trueOrderSize = ISwapRouter(swapRouter).exactInputSingle(params);

        // 处理二级奖励
        _handleSecondaryRewards();

        // 发出事件
        emit WowTokenBuy(
            msg.sender,
            recipient,
            orderReferrer,
            msg.value,
            fee,
            totalCost,
            trueOrderSize,
            balanceOf(recipient),
            comment,
            totalSupply(),
            marketType
        );

        emit CoinBuy(
            msg.sender,
            recipient,
            orderReferrer,
            trueOrderSize,
            address(0),
            fee,
            totalCost,
            comment
        );

        return trueOrderSize;
    }

    /**
     * @notice 卖出代币换取ETH
     * @param amount 卖出的代币数量
     * @param recipient ETH接收地址
     * @param orderReferrer 订单推荐人地址
     * @param comment 订单备注
     * @param minPayoutSize 最小支付大小（防滑点）
     * @param sqrtPriceLimitX96 Uniswap V3价格限制
     * @return 获得的ETH数量
     */
    function sell(
        uint256 amount,
        address recipient,
        address orderReferrer,
        string memory comment,
        MarketType, /* expectedMarketType - deprecated */
        uint256 minPayoutSize,
        uint160 sqrtPriceLimitX96
    ) external nonReentrant returns (uint256) {
        // 验证余额
        if (amount > balanceOf(msg.sender)) revert InsufficientLiquidity();
        if (recipient == address(0)) revert AddressZero();

        // 处理Uniswap卖出
        uint256 truePayoutSize = _handleUniswapSell(amount, minPayoutSize, sqrtPriceLimitX96);

        // 计算费用
        uint256 fee = _calculateFee(truePayoutSize, TOTAL_FEE_BPS);
        uint256 payoutAfterFee = truePayoutSize - fee;

        // 处理费用
        _disperseFees(fee, orderReferrer);

        // 发送ETH到接收地址
        (bool success,) = recipient.call{value: payoutAfterFee}("");
        if (!success) revert EthTransferFailed();

        // 处理二级奖励
        _handleSecondaryRewards();

        // 发出事件
        emit WowTokenSell(
            msg.sender,
            recipient,
            orderReferrer,
            truePayoutSize,
            fee,
            payoutAfterFee,
            amount,
            balanceOf(recipient),
            comment,
            totalSupply(),
            marketType
        );

        emit CoinSell(
            msg.sender,
            recipient,
            orderReferrer,
            amount,
            address(0),
            fee,
            payoutAfterFee,
            comment
        );

        return truePayoutSize;
    }

    /**
     * @notice 销毁代币
     * @param amount 要销毁的代币数量
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice 强制领取市场流动性位置的累积二级奖励
     * @dev 这是一个后备函数，二级奖励通常在每次买卖时自动领取
     * @param pushEthRewards 是否直接将ETH推送给接收者
     */
    function claimSecondaryRewards(bool pushEthRewards) external {
        MarketRewards memory rewards = _handleSecondaryRewards();

        if (rewards.totalAmountCurrency > 0 && pushEthRewards) {
            IProtocolRewards(protocolRewards).withdrawFor(tokenCreator, rewards.creatorPayoutAmountCurrency);
            IProtocolRewards(protocolRewards).withdrawFor(platformReferrer, rewards.platformReferrerAmountCurrency);
            IProtocolRewards(protocolRewards).withdrawFor(protocolFeeRecipient, rewards.protocolAmountCurrency);
        }
    }

    /**
     * @notice 返回当前市场类型和地址
     * @return 市场状态结构体
     */
    function state() external view returns (MarketState memory) {
        return MarketState({marketType: marketType, marketAddress: poolAddress});
    }

    /**
     * @notice 接收ETH并执行购买订单的回退函数
     */
    receive() external payable {
        if (msg.sender == WETH) {
            return;
        }
        buy(msg.sender, msg.sender, address(0), "", marketType, 0, 0);
    }

    /**
     * @notice 接收Uniswap V3 LP NFT的回调函数
     */
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != poolAddress) revert OnlyPool();
        return this.onERC721Received.selector;
    }

    /**
     * @notice Uniswap V3回调函数（用于设置初始价格）
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {}

    /**
     * @dev 重写ERC20的_update函数
     * - 防止在市场未就绪时向池子转移代币
     * - 发出带有额外信息的WowTokenTransfer事件
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        emit WowTokenTransfer(from, to, value, balanceOf(from), balanceOf(to), totalSupply());
        emit CoinTransfer(from, to, value, balanceOf(from), balanceOf(to));
    }

    /**
     * @dev 部署Uniswap V3池子
     */
    function _deployPool() internal {
        // 排序代币地址
        address token0 = address(this) < WETH ? address(this) : WETH;
        address token1 = address(this) < WETH ? WETH : address(this);

        // 确定代币顺序
        bool isCoinToken0 = token0 == address(this);

        // 确定刻度值
        int24 tickLower = isCoinToken0 ? LP_TICK_LOWER : -LP_TICK_UPPER;
        int24 tickUpper = isCoinToken0 ? LP_TICK_UPPER : -LP_TICK_LOWER;

        // 计算起始价格
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(isCoinToken0 ? tickLower : tickUpper);

        // 确定初始流动性数量
        uint256 amount0 = isCoinToken0 ? POOL_LAUNCH_SUPPLY : 0;
        uint256 amount1 = isCoinToken0 ? 0 : POOL_LAUNCH_SUPPLY;

        // 创建并初始化池子
        poolAddress = INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
            token0, token1, LP_FEE, sqrtPriceX96
        );

        // 构造LP参数
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: LP_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // 铸造LP
        (lpTokenId,,,) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);

        emit WowMarketGraduated(address(this), poolAddress, 0, POOL_LAUNCH_SUPPLY, lpTokenId, MarketType.UNISWAP_POOL);
    }

    /**
     * @dev 处理Uniswap V3卖出操作
     */
    function _handleUniswapSell(uint256 tokensToSell, uint256 minPayoutSize, uint160 sqrtPriceLimitX96) private returns (uint256) {
        // 将代币转移到合约
        transfer(address(this), tokensToSell);

        // 批准交换路由器
        this.approve(swapRouter, tokensToSell);

        // 设置交换参数
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: WETH,
            fee: LP_FEE,
            recipient: address(this),
            amountIn: tokensToSell,
            amountOutMinimum: minPayoutSize,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // 执行交换
        uint256 payout = ISwapRouter(swapRouter).exactInputSingle(params);

        // 将WETH提取为ETH
        IWETH(WETH).withdraw(payout);

        return payout;
    }

    /**
     * @dev 处理费用计算和存入协议奖励合约
     */
    function _disperseFees(uint256 _fee, address _orderReferrer) internal {
        if (_orderReferrer == address(0)) {
            _orderReferrer = protocolFeeRecipient;
        }

        // 计算各种费用
        uint256 tokenCreatorFee = _calculateFee(_fee, TOKEN_CREATOR_FEE_BPS);
        uint256 platformReferrerFee = _calculateFee(_fee, PLATFORM_REFERRER_FEE_BPS);
        uint256 orderReferrerFee = _calculateFee(_fee, ORDER_REFERRER_FEE_BPS);
        uint256 protocolFee = _calculateFee(_fee, PROTOCOL_FEE_BPS);
        uint256 totalFee = tokenCreatorFee + platformReferrerFee + orderReferrerFee + protocolFee;

        // 准备批量存入数据
        address[] memory recipients = new address[](4);
        uint256[] memory amounts = new uint256[](4);
        bytes4[] memory reasons = new bytes4[](4);

        recipients[0] = tokenCreator;
        amounts[0] = tokenCreatorFee;
        reasons[0] = bytes4(keccak256("WOW_CREATOR_FEE"));

        recipients[1] = platformReferrer;
        amounts[1] = platformReferrerFee;
        reasons[1] = bytes4(keccak256("WOW_PLATFORM_REFERRER_FEE"));

        recipients[2] = _orderReferrer;
        amounts[2] = orderReferrerFee;
        reasons[2] = bytes4(keccak256("WOW_ORDER_REFERRER_FEE"));

        recipients[3] = protocolFeeRecipient;
        amounts[3] = protocolFee;
        reasons[3] = bytes4(keccak256("WOW_PROTOCOL_FEE"));

        // 批量存入费用
        IProtocolRewards(protocolRewards).depositBatch{value: totalFee}(recipients, amounts, reasons, "");

        // 发出事件
        emit WowTokenFees(
            tokenCreator,
            platformReferrer,
            _orderReferrer,
            protocolFeeRecipient,
            tokenCreatorFee,
            platformReferrerFee,
            orderReferrerFee,
            protocolFee
        );

        emit CoinTradeRewards(
            tokenCreator,
            platformReferrer,
            _orderReferrer,
            protocolFeeRecipient,
            tokenCreatorFee,
            platformReferrerFee,
            orderReferrerFee,
            protocolFee,
            address(0)
        );
    }

    /**
     * @dev 处理二级奖励的收集和分发
     */
    function _handleSecondaryRewards() internal returns (MarketRewards memory) {
        // 准备收集参数
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: lpTokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        // 收集奖励
        (uint256 totalAmountToken0, uint256 totalAmountToken1) = INonfungiblePositionManager(nonfungiblePositionManager).collect(params);

        // 确定代币顺序
        address token0 = WETH < address(this) ? WETH : address(this);
        address token1 = WETH < address(this) ? address(this) : WETH;

        MarketRewards memory rewards;

        // 处理两种代币的奖励
        rewards = _transferRewards(token0, totalAmountToken0, rewards);
        rewards = _transferRewards(token1, totalAmountToken1, rewards);

        // 发出事件
        emit CoinMarketRewards(
            tokenCreator,
            platformReferrer,
            protocolFeeRecipient,
            address(0),
            rewards
        );

        return rewards;
    }

    /**
    * @dev 处理奖励的转移，用于处理 Uniswap V3 流动性池产生的奖励分发。
     * @param token 奖励代币地址
     * @param totalAmount 总奖励数量
     * @param rewards 奖励结构体
     * @return 更新后的奖励结构体
     */
    function _transferRewards(address token, uint256 totalAmount, MarketRewards memory rewards) internal returns (MarketRewards memory) {
        if (totalAmount > 0) {
            if (token == WETH) {
                // 1. 首先检查合约的 WETH 余额
                uint256 wethBalance = IERC20(WETH).balanceOf(address(this));

                // 2. 使用合约中实际可用的金额
                uint256 amountToWithdraw = wethBalance < totalAmount ? wethBalance : totalAmount;

                if (amountToWithdraw > 0) {
                    // 3. 计算各种奖励金额（基于实际可提取金额）
                    rewards.totalAmountCurrency = amountToWithdraw;
                    rewards.creatorPayoutAmountCurrency = _calculateFee(amountToWithdraw, TOKEN_CREATOR_SECONDARY_REWARDS_BPS);
                    rewards.platformReferrerAmountCurrency = _calculateFee(amountToWithdraw, PLATFORM_REFERRER_SECONDARY_REWARDS_BPS);
                    rewards.protocolAmountCurrency = rewards.totalAmountCurrency - rewards.creatorPayoutAmountCurrency - rewards.platformReferrerAmountCurrency;

                    // 4. 将 WETH 转换为 ETH
                    IWETH(WETH).withdraw(amountToWithdraw);

                    // 5. 准备批量存入数据
                    address[] memory recipients = new address[](3);
                    uint256[] memory amounts = new uint256[](3);
                    bytes4[] memory reasons = new bytes4[](3);

                    // 设置接收者
                    recipients[0] = tokenCreator;
                    recipients[1] = platformReferrer;
                    recipients[2] = protocolFeeRecipient;

                    // 设置金额
                    amounts[0] = rewards.creatorPayoutAmountCurrency;
                    amounts[1] = rewards.platformReferrerAmountCurrency;
                    amounts[2] = rewards.protocolAmountCurrency;

                    // 设置原因代码
                    reasons[0] = bytes4(keccak256("WOW_CREATOR_SECONDARY_REWARD"));
                    reasons[1] = bytes4(keccak256("WOW_PLATFORM_REFERRER_SECONDARY_REWARD"));
                    reasons[2] = bytes4(keccak256("WOW_PROTOCOL_SECONDARY_REWARD"));

                    // 6. 批量存入 ETH 奖励
                    IProtocolRewards(protocolRewards).depositBatch{value: amountToWithdraw}(
                        recipients,
                        amounts,
                        reasons,
                        ""
                    );
                }
            } else {
                // 处理代币奖励（非 WETH）
                // 1. 计算代币奖励金额
                rewards.totalAmountCoin = totalAmount;
                rewards.creatorPayoutAmountCoin = _calculateFee(totalAmount, TOKEN_CREATOR_SECONDARY_REWARDS_BPS);
                rewards.platformReferrerAmountCoin = _calculateFee(totalAmount, PLATFORM_REFERRER_SECONDARY_REWARDS_BPS);
                rewards.protocolAmountCoin = rewards.totalAmountCoin - rewards.creatorPayoutAmountCoin - rewards.platformReferrerAmountCoin;

                // 2. 转移代币奖励
                // 使用 try-catch 来处理可能的转账失败
                try this.transfer(tokenCreator, rewards.creatorPayoutAmountCoin) {
                    try this.transfer(platformReferrer, rewards.platformReferrerAmountCoin) {
                        try this.transfer(protocolFeeRecipient, rewards.protocolAmountCoin) {
                            // 所有转账成功
                        } catch {
                            // 处理协议费用转账失败
                            rewards.protocolAmountCoin = 0;
                        }
                    } catch {
                        // 处理平台推荐人转账失败
                        rewards.platformReferrerAmountCoin = 0;
                        try this.transfer(protocolFeeRecipient, rewards.protocolAmountCoin) {
                            // 协议费用转账成功
                        } catch {
                            rewards.protocolAmountCoin = 0;
                        }
                    }
                } catch {
                    // 处理创建者转账失败
                    rewards.creatorPayoutAmountCoin = 0;
                    try this.transfer(platformReferrer, rewards.platformReferrerAmountCoin) {
                        try this.transfer(protocolFeeRecipient, rewards.protocolAmountCoin) {
                            // 其余转账成功
                        } catch {
                            rewards.protocolAmountCoin = 0;
                        }
                    } catch {
                        rewards.platformReferrerAmountCoin = 0;
                        try this.transfer(protocolFeeRecipient, rewards.protocolAmountCoin) {
                            // 尝试最后的协议费用转账
                        } catch {
                            rewards.protocolAmountCoin = 0;
                        }
                    }
                }
            }
        }

        return rewards;
    }

    /**
     * @dev 计算基于基点的费用
     * @param amount 基础金额
     * @param bps 基点数（1 bps = 0.01%）
     * @return 计算得到的费用
     */
    function _calculateFee(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }
}