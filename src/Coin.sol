// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TickMath} from "./TickMath.sol";
import {ICoin} from "./interfaces/ICoin.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IProtocolRewards} from "./interfaces/IProtocolRewards.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/* 
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    

    WOW         WOW         WOW    
*/
contract Coin is ICoin, ERC20Upgradeable, ReentrancyGuardUpgradeable, IERC721Receiver {
    uint256 public constant MAX_TOTAL_SUPPLY = 1_000_000_000e18; // 1B coins
    uint256 internal constant POOL_LAUNCH_SUPPLY = 980_000_000e18; // 980M coins
    uint256 internal constant CREATOR_LAUNCH_REWARD = 10_000_000e18; // 10M coins
    uint256 internal constant PLATFORM_REFERRER_LAUNCH_REWARD = 5_000_000e18; // 5M coins
    uint256 internal constant PROTOCOL_LAUNCH_REWARD = 5_000_000e18; // 5M coins

    uint256 public constant MIN_ORDER_SIZE = 0.0000001 ether;
    uint256 public constant TOTAL_FEE_BPS = 100; // 1%
    uint256 public constant TOKEN_CREATOR_FEE_BPS = 5000; // 50% (of TOTAL_FEE_BPS)
    uint256 public constant PROTOCOL_FEE_BPS = 2000; // 20% (of TOTAL_FEE_BPS)
    uint256 public constant PLATFORM_REFERRER_FEE_BPS = 1500; // 15% (of TOTAL_FEE_BPS)
    uint256 public constant ORDER_REFERRER_FEE_BPS = 1500; // 15% (of TOTAL_FEE_BPS)
    uint256 internal constant TOKEN_CREATOR_SECONDARY_REWARDS_BPS = 5000; // 50% (of LP_FEE)
    uint256 internal constant PLATFORM_REFERRER_SECONDARY_REWARDS_BPS = 2500; // 25% (of LP_FEE)

    uint24 internal constant LP_FEE = 10000;
    int24 internal constant LP_TICK_LOWER = -219200;
    int24 internal constant LP_TICK_UPPER = 887200;

    address public immutable WETH;
    address public immutable nonfungiblePositionManager;
    address public immutable swapRouter;
    address public immutable protocolFeeRecipient;
    address public immutable protocolRewards;

    MarketType public marketType;
    address public platformReferrer;
    address public poolAddress;
    address public tokenCreator;
    string public tokenURI;
    uint256 public lpTokenId;

    constructor(
        address _protocolFeeRecipient,
        address _protocolRewards,
        address _weth,
        address _nonfungiblePositionManager,
        address _swapRouter
    ) initializer {
        if (_protocolFeeRecipient == address(0)) {
            revert AddressZero();
        }
        if (_protocolRewards == address(0)) {
            revert AddressZero();
        }
        if (_weth == address(0)) {
            revert AddressZero();
        }
        if (_nonfungiblePositionManager == address(0)) {
            revert AddressZero();
        }
        if (_swapRouter == address(0)) {
            revert AddressZero();
        }

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolRewards = _protocolRewards;
        WETH = _weth;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
    }

    /// @notice Initializes a new coin
    /// @param _creator The address of the coin creator
    /// @param _platformReferrer The address of the platform referrer
    /// @param _tokenURI The ERC20z token URI
    /// @param _name The coin name
    /// @param _symbol The coin symbol
    function initialize(
        address _creator,
        address _platformReferrer,
        string memory _tokenURI,
        string memory _name,
        string memory _symbol
    ) public payable initializer {
        // Validate the creation parameters
        if (_creator == address(0)) {
            revert AddressZero();
        }
        if (_platformReferrer == address(0)) {
            _platformReferrer = protocolFeeRecipient;
        }

        // Initialize base contract state
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();

        // Initialize coin and market state
        marketType = MarketType.UNISWAP_POOL;
        platformReferrer = _platformReferrer;
        tokenCreator = _creator;
        tokenURI = _tokenURI;

        // Mint the total supply
        _mint(address(this), MAX_TOTAL_SUPPLY);

        // Distribute launch rewards
        _transfer(address(this), _creator, CREATOR_LAUNCH_REWARD);
        _transfer(address(this), platformReferrer, PLATFORM_REFERRER_LAUNCH_REWARD);
        _transfer(address(this), protocolFeeRecipient, PROTOCOL_LAUNCH_REWARD);

        // Approve the transfer of the remaining supply to the pool
        SafeERC20.safeIncreaseAllowance(this, address(nonfungiblePositionManager), POOL_LAUNCH_SUPPLY);

        // Deploy the pool
        _deployPool();

        // Execute the initial buy order if any ETH was sent
        if (msg.value > 0) {
            buy(_creator, _creator, address(0), "", MarketType.UNISWAP_POOL, 0, 0);
        }
    }

    /// @notice Executes an order to buy coins with ETH
    /// @param recipient The recipient address of the coins
    /// @param orderReferrer The address of the order referrer
    /// @param comment A comment associated with the buy order
    /// @param minOrderSize The minimum coins to prevent slippage
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function buy(
        address recipient,
        address, /* refundRecipient - deprecated */
        address orderReferrer,
        string memory comment,
        MarketType, /* expectedMarketType - deprecated */
        uint256 minOrderSize,
        uint160 sqrtPriceLimitX96
    ) public payable nonReentrant returns (uint256) {
        // Ensure the order size is greater than the minimum order size
        if (msg.value < MIN_ORDER_SIZE) {
            revert EthAmountTooSmall();
        }

        // Ensure the recipient is not the zero address
        if (recipient == address(0)) {
            revert AddressZero();
        }

        // Calculate the fee
        uint256 fee = _calculateFee(msg.value, TOTAL_FEE_BPS);

        // Calculate the remaining ETH
        uint256 totalCost = msg.value - fee;

        // Handle the fees
        _disperseFees(fee, orderReferrer);

        // Convert the ETH to WETH and approve the swap router
        IWETH(WETH).deposit{value: totalCost}();
        IWETH(WETH).approve(swapRouter, totalCost);

        // Set up the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(this),
            fee: LP_FEE,
            recipient: recipient,
            amountIn: totalCost,
            amountOutMinimum: minOrderSize,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        uint256 trueOrderSize = ISwapRouter(swapRouter).exactInputSingle(params);

        // Handle any secondary rewards
        _handleSecondaryRewards();

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

    /// @notice Executes an order to sell coins for ETH
    /// @param amount The number of coins to sell
    /// @param recipient The address to receive the ETH
    /// @param orderReferrer The address of the order referrer
    /// @param comment A comment associated with the sell order
    /// @param minPayoutSize The minimum ETH payout to prevent slippage
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function sell(
        uint256 amount,
        address recipient,
        address orderReferrer,
        string memory comment,
        MarketType, /* expectedMarketType - deprecated */
        uint256 minPayoutSize,
        uint160 sqrtPriceLimitX96
    ) external nonReentrant returns (uint256) {
        // Ensure the sender has enough liquidity to sell
        if (amount > balanceOf(msg.sender)) {
            revert InsufficientLiquidity();
        }

        // Ensure the recipient is not the zero address
        if (recipient == address(0)) {
            revert AddressZero();
        }

        // Initialize the true payout size
        uint256 truePayoutSize = _handleUniswapSell(amount, minPayoutSize, sqrtPriceLimitX96);

        // Calculate the fee
        uint256 fee = _calculateFee(truePayoutSize, TOTAL_FEE_BPS);

        // Calculate the payout after the fee
        uint256 payoutAfterFee = truePayoutSize - fee;

        // Handle the fees
        _disperseFees(fee, orderReferrer);

        // Send the payout to the recipient
        (bool success, ) = recipient.call{value: payoutAfterFee}("");
        if (!success) revert EthTransferFailed();

        // Handle any secondary rewards
        _handleSecondaryRewards();

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

    /// @notice Enables a user to burn their tokens
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Force claim any accrued secondary rewards from the market's liquidity position.
    /// @dev This function is a fallback, secondary rewards will be claimed automatically on each buy and sell.
    /// @param pushEthRewards Whether to push the ETH directly to the recipients.
    function claimSecondaryRewards(bool pushEthRewards) external {
        MarketRewards memory rewards = _handleSecondaryRewards();

        if (rewards.totalAmountCurrency > 0 && pushEthRewards) {
            IProtocolRewards(protocolRewards).withdrawFor(tokenCreator, rewards.creatorPayoutAmountCurrency);
            IProtocolRewards(protocolRewards).withdrawFor(platformReferrer, rewards.platformReferrerAmountCurrency);
            IProtocolRewards(protocolRewards).withdrawFor(protocolFeeRecipient, rewards.protocolAmountCurrency);
        }
    }

    /// @notice Returns current market type and address
    function state() external view returns (MarketState memory) {
        return MarketState({marketType: marketType, marketAddress: poolAddress});
    }

    /// @notice Receives ETH and executes a buy order.
    receive() external payable {
        if (msg.sender == WETH) {
            return;
        }

        buy(msg.sender, msg.sender, address(0), "", marketType, 0, 0);
    }

    /// @dev For receiving the Uniswap V3 LP NFT on market graduation.
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != poolAddress) revert OnlyPool();

        return this.onERC721Received.selector;
    }

    /// @dev No-op to allow a swap on the pool to set the correct initial price, if needed
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {}

    /// @dev Overrides ERC20's _update function to
    ///      - Prevent transfers to the pool if the market has not graduated.
    ///      - Emit the superset `WowTokenTransfer` event with each ERC20 transfer.
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        emit WowTokenTransfer(from, to, value, balanceOf(from), balanceOf(to), totalSupply());

        emit CoinTransfer(from, to, value, balanceOf(from), balanceOf(to));
    }

    /// @dev Deploy the pool
    function _deployPool() internal {
        // Sort the token addresses
        address token0 = address(this) < WETH ? address(this) : WETH;
        address token1 = address(this) < WETH ? WETH : address(this);

        // If the coin is token0
        bool isCoinToken0 = token0 == address(this);

        // Determine the tick values
        int24 tickLower = isCoinToken0 ? LP_TICK_LOWER : -LP_TICK_UPPER;
        int24 tickUpper = isCoinToken0 ? LP_TICK_UPPER : -LP_TICK_LOWER;

        // Calculate the starting price for the pool
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(isCoinToken0 ? tickLower : tickUpper);

        // Determine the initial liquidity amounts
        uint256 amount0 = isCoinToken0 ? POOL_LAUNCH_SUPPLY : 0;
        uint256 amount1 = isCoinToken0 ? 0 : POOL_LAUNCH_SUPPLY;

        // Create and initialize the pool
        poolAddress = INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
            token0, token1, LP_FEE, sqrtPriceX96
        );

        // Construct the LP data
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

        // Mint the LP
        (lpTokenId,,,) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);

        emit WowMarketGraduated(address(this), poolAddress, 0, POOL_LAUNCH_SUPPLY, lpTokenId, MarketType.UNISWAP_POOL);
    }

    /// @dev Handles a Uniswap V3 sell order
    function _handleUniswapSell(uint256 tokensToSell, uint256 minPayoutSize, uint160 sqrtPriceLimitX96) private returns (uint256) {
        // Transfer the tokens from the seller to this contract
        transfer(address(this), tokensToSell);

        // Approve the swap router to spend the tokens
        this.approve(swapRouter, tokensToSell);

        // Set up the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: WETH,
            fee: LP_FEE,
            recipient: address(this),
            amountIn: tokensToSell,
            amountOutMinimum: minPayoutSize,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        uint256 payout = ISwapRouter(swapRouter).exactInputSingle(params);

        // Withdraw the ETH from the contract
        IWETH(WETH).withdraw(payout);

        return payout;
    }

    /// @dev Handles calculating and depositing fees to an escrow protocol rewards contract
    function _disperseFees(uint256 _fee, address _orderReferrer) internal {
        if (_orderReferrer == address(0)) {
            _orderReferrer = protocolFeeRecipient;
        }

        uint256 tokenCreatorFee = _calculateFee(_fee, TOKEN_CREATOR_FEE_BPS);
        uint256 platformReferrerFee = _calculateFee(_fee, PLATFORM_REFERRER_FEE_BPS);
        uint256 orderReferrerFee = _calculateFee(_fee, ORDER_REFERRER_FEE_BPS);
        uint256 protocolFee = _calculateFee(_fee, PROTOCOL_FEE_BPS);
        uint256 totalFee = tokenCreatorFee + platformReferrerFee + orderReferrerFee + protocolFee;

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

        IProtocolRewards(protocolRewards).depositBatch{value: totalFee}(recipients, amounts, reasons, "");

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

    function _handleSecondaryRewards() internal returns (MarketRewards memory) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: lpTokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (uint256 totalAmountToken0, uint256 totalAmountToken1) = INonfungiblePositionManager(nonfungiblePositionManager).collect(params);

        address token0 = WETH < address(this) ? WETH : address(this);
        address token1 = WETH < address(this) ? address(this) : WETH;

        MarketRewards memory rewards;

        rewards = _transferRewards(token0, totalAmountToken0, rewards);
        rewards = _transferRewards(token1, totalAmountToken1, rewards);

        emit CoinMarketRewards(
            tokenCreator,
            platformReferrer,
            protocolFeeRecipient,
            address(0),
            rewards
        );

        return rewards;
    }

    function _transferRewards(address token, uint256 totalAmount, MarketRewards memory rewards) internal returns (MarketRewards memory) {
        if (totalAmount > 0) {
            if (token == WETH) {
                IWETH(WETH).withdraw(totalAmount);

                rewards.totalAmountCurrency = totalAmount;
                rewards.creatorPayoutAmountCurrency = _calculateFee(totalAmount, TOKEN_CREATOR_SECONDARY_REWARDS_BPS);
                rewards.platformReferrerAmountCurrency = _calculateFee(totalAmount, PLATFORM_REFERRER_SECONDARY_REWARDS_BPS);
                rewards.protocolAmountCurrency = rewards.totalAmountCurrency - rewards.creatorPayoutAmountCurrency - rewards.platformReferrerAmountCurrency;

                address[] memory recipients = new address[](3);
                recipients[0] = tokenCreator;
                recipients[1] = platformReferrer;
                recipients[2] = protocolFeeRecipient;

                uint256[] memory amounts = new uint256[](3);
                amounts[0] = rewards.creatorPayoutAmountCurrency;
                amounts[1] = rewards.platformReferrerAmountCurrency;
                amounts[2] = rewards.protocolAmountCurrency;

                bytes4[] memory reasons = new bytes4[](3);
                reasons[0] = bytes4(keccak256("WOW_CREATOR_SECONDARY_REWARD"));
                reasons[1] = bytes4(keccak256("WOW_PLATFORM_REFERRER_SECONDARY_REWARD"));
                reasons[2] = bytes4(keccak256("WOW_PROTOCOL_SECONDARY_REWARD"));

                IProtocolRewards(protocolRewards).depositBatch{value: totalAmount}(recipients, amounts, reasons, "");
            } else {
                rewards.totalAmountCoin = totalAmount;
                rewards.creatorPayoutAmountCoin = _calculateFee(totalAmount, TOKEN_CREATOR_SECONDARY_REWARDS_BPS);
                rewards.platformReferrerAmountCoin = _calculateFee(totalAmount, PLATFORM_REFERRER_SECONDARY_REWARDS_BPS);
                rewards.protocolAmountCoin = rewards.totalAmountCoin - rewards.creatorPayoutAmountCoin - rewards.platformReferrerAmountCoin;

                _transfer(address(this), tokenCreator, rewards.creatorPayoutAmountCoin);
                _transfer(address(this), platformReferrer, rewards.platformReferrerAmountCoin);
                _transfer(address(this), protocolFeeRecipient, rewards.protocolAmountCoin);
            }
        }

        return rewards;
    }

    /// @dev Calculates the fee for a given amount and basis points.
    function _calculateFee(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }
}
