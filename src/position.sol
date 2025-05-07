// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from "forge-std/console.sol";
import {IUniswapV3Pool} from "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter02} from "./interfaces/ISwapRouter02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockKARI} from "./mocks/MockKARI.sol";
import {MockDD} from "./mocks/MockDD.sol";
import {MockAUSD} from "./mocks/MockAUSD.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiquidityAmounts} from "@uniswapv3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import { FixedPoint96 } from '@uniswapv3-core/libraries/FixedPoint96.sol';

contract Position {
    using SafeERC20 for IERC20;
    
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    ISwapRouter02 public immutable swapRouter;

    address public token0;
    address public token1;
    address public pool;

    int24 anchorTickUpper;
    int24 anchorTickLower;

    int24 public immutable TICK_SPACING; // Uniswap V3 default tick spacing

    uint24 public immutable UNISWAP_FEE_TIER; // 0.3% // 0.01%

    event Purchase(uint256 timestamp, uint8 swap, uint256 price, uint256 amount, address buyer);

    constructor(address _swapRouter, address _nftManager, address _token0, address _token1, uint24 _feeTier, int24 _tickSpacing) {
        swapRouter = ISwapRouter02(_swapRouter);
        nonfungiblePositionManager = INonfungiblePositionManager(_nftManager);
        token0 = _token0;
        token1 = _token1;

        UNISWAP_FEE_TIER = _feeTier;
        TICK_SPACING = _tickSpacing;
    }

    function initPoolAndPosition(uint160 sqrtPriceX96, int24 floorTick, uint256 floorAmount, uint256 anchorAmount)
        external
    {
        IERC20(token1).safeTransferFrom(msg.sender, address(this), floorAmount + anchorAmount);

        // [1] create and init pool
        pool = nonfungiblePositionManager.createAndInitializePoolIfNecessary(
            token0, token1, UNISWAP_FEE_TIER, sqrtPriceX96
        );
        // [2] mint floor
        _mintPosition(floorAmount, floorTick);
        // calculate the initial discovery token per tick amount

        // [3] mint anchor
        _mintAnchor(anchorAmount);
        _mintDiscovery();

        // [3] zero approve
        IERC20(token0).approve(address(nonfungiblePositionManager), 0);
        IERC20(token1).approve(address(nonfungiblePositionManager), 0);
    }

    function swap(address _token0, address _token1, uint256 _amount) internal {
        //uint256 preSwapBalance = IERC20(token1).balanceOf(msg.sender);
        IERC20(_token0).transferFrom(msg.sender, address(this), _amount);

        ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02.ExactInputSingleParams({
            tokenIn: _token0,
            tokenOut: _token1,
            fee: 3000,
            recipient: msg.sender,
            amountIn: _amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        IERC20(_token0).approve(address(swapRouter), _amount);
        swapRouter.exactInputSingle(params);

        uint8 _swap = _token0 == token0 ? 1 : 0;

        emit Purchase(block.timestamp,  _swap, 0, _amount, msg.sender);
    }

    function _mintPosition(uint256 amount, int24 tick) internal returns (uint256 tokenId) {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: UNISWAP_FEE_TIER,
            tickLower: tick - 60 ,
            tickUpper: tick + 60,
            amount0Desired: 0,
            amount1Desired: amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        IERC20(token0).approve(address(nonfungiblePositionManager), IERC20(token0).balanceOf(address(this)));
        IERC20(token1).approve(address(nonfungiblePositionManager), amount);
        (tokenId, , , ) = nonfungiblePositionManager.mint(params);
        MockDD(token0).burn(address(this), IERC20(token0).balanceOf(address(this)));
    }

    function _mintAnchor(uint256 anchorAmount) internal returns (uint256 tokenId) {
        // console.log("currentTick", currentTick);
        // console.log("token0 total supply", IERC20(token0).totalSupply());
        uint256 maxMint = type(uint128).max - IERC20(token0).totalSupply();
        (, int24 currentTick,,,,,) = IUniswapV3Pool(pool).slot0();
        MockDD(token0).mint(address(this), maxMint);
        uint256 balance = IERC20(token0).balanceOf(address(this));

        int24 normalizedTick = currentTick / TICK_SPACING * TICK_SPACING;
        anchorTickUpper = normalizedTick + TICK_SPACING * 20;
        anchorTickLower = normalizedTick - TICK_SPACING * 20;

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(anchorTickUpper);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(anchorTickLower);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
            sqrtRatioAX96,
            sqrtRatioBX96,
            anchorAmount // only token1 is supplied
        );

        (uint256 amount0) = getAmount0ForLiquidity(
        sqrtRatioAX96,
        sqrtRatioBX96,
        liquidity
        );

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: UNISWAP_FEE_TIER,
            tickLower: anchorTickLower,
            tickUpper: anchorTickUpper,
            amount0Desired: amount0,
            amount1Desired: anchorAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        IERC20(token0).approve(address(nonfungiblePositionManager), IERC20(token0).balanceOf(address(this)));
        IERC20(token1).approve(address(nonfungiblePositionManager), anchorAmount);
        (tokenId, , , ) = nonfungiblePositionManager.mint(params);
        uint256 tokenMinted = balance - IERC20(token0).balanceOf(address(this));
        MockDD(token0).burn(address(this), IERC20(token0).balanceOf(address(this)));
        console.log("Token to Mint", tokenMinted);
    }

    function _mintDiscovery() internal returns (uint256 tokenId) {
        uint256 maxMint = type(uint128).max - IERC20(token0).totalSupply();
        MockDD(token0).mint(address(this), maxMint);
        int24 discoveryTickUpper = anchorTickUpper + TICK_SPACING * 20;
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: UNISWAP_FEE_TIER,
            tickLower: anchorTickUpper,
            tickUpper: discoveryTickUpper,
            amount0Desired: 40_000e18,
            amount1Desired: 0,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        IERC20(token0).approve(address(nonfungiblePositionManager), 40_000e18);
        (tokenId, , , ) = nonfungiblePositionManager.mint(params);
        MockDD(token0).burn(address(this), IERC20(token0).balanceOf(address(this)));
    }

    function getAmount0ForLiquidity(
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint128 liquidity
) internal pure returns (uint256 amount0) {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
    }

    uint256 numerator = Math.mulDiv(
        uint256(liquidity),
        sqrtRatioBX96 - sqrtRatioAX96,
        1 // this is just to split up the operation, result still fits
    );

    amount0 = Math.mulDiv(
        numerator,
        1 << FixedPoint96.RESOLUTION,
        uint256(sqrtRatioBX96) * sqrtRatioAX96
    );
}

//     function getAmount0ForLiquidity(
//     uint160 sqrtRatioAX96,
//     uint160 sqrtRatioBX96,
//     uint128 liquidity
// ) internal pure returns (uint256 amount0) {
//     // Ensure sqrtRatioAX96 is the smaller value
//     if (sqrtRatioAX96 > sqrtRatioBX96) {
//         (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
//     }

//     // Perform the math with the right precision
//     uint256 liquidityWithPrecision = uint256(liquidity) << FixedPoint96.RESOLUTION;
//     uint256 deltaSqrtRatio = sqrtRatioBX96 - sqrtRatioAX96;
//     uint256 denominator = uint256(sqrtRatioBX96) * uint256(sqrtRatioAX96);

//     // Using Math.mulDiv for safe multiplication and division
//     amount0 = Math.mulDiv(liquidityWithPrecision, deltaSqrtRatio, denominator);
// }

}