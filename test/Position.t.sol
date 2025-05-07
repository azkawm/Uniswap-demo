// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console, Test } from "forge-std/Test.sol";
import { ISwapRouter02 } from "../src/interfaces/ISwapRouter02.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockKARI } from "../src/mocks/MockKARI.sol";
import { MockDD } from "../src/mocks/MockDD.sol";
import { MockAUSD } from "../src/mocks/MockAUSD.sol";
import { INonfungiblePositionManager } from "../src/interfaces/INonfungiblePositionManager.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Position } from "../src/position.sol";
import { IUniswapV3Pool } from "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import { PriceMath } from "../src/libraries/PriceMath.sol";
import { TickMath } from "../src/libraries/TickMath.sol";
import { FixedPointMathLib} from "../src/libraries/FixedPointMathLib.sol";

contract PositionTest is Test {
    using SafeERC20 for IERC20;

    ISwapRouter02 public swapRouter;
    MockDD public token0;
    //MockAUSD public token1;
    MockKARI public token1;
    INonfungiblePositionManager public nonfungiblePositionManager;
    Position public position;
    IUniswapV3Pool public pool;

    uint24 public constant UNISWAP_FEE_TIER = 3000; // 0.3%

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.createSelectFork("https://arb-sepolia.g.alchemy.com/v2/IpWFQVx6ZTeZyG85llRd7h6qRRNMqErS");
        //token1 = new MockAUSD();
        token1 = new MockKARI();
        token0 = new MockDD();
        //token1 = new MockDD();
        swapRouter = ISwapRouter02(0x101F443B4d1b059569D643917553c771E1b9663E);
        nonfungiblePositionManager = INonfungiblePositionManager(0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65);
        position = new Position(address(swapRouter), address(nonfungiblePositionManager), address(token0), address(token1), 3000, 60);

        uint160 sqrtPriceX96 = PriceMath.priceToSqrtPriceX96(1e18, 18);
        console.log(sqrtPriceX96);

        uint160 floorSqrtPriceX96 = PriceMath.priceToSqrtPriceX96(5e17, 18);
        int24 unnormalizedFloorTick = TickMath.getTickAtSqrtRatio(floorSqrtPriceX96);
        int24 floorTick = unnormalizedFloorTick / position.TICK_SPACING() * position.TICK_SPACING();
        console.log(floorTick);

        // deal(address(token1), address(this), 1000e6);
        // IERC20(token1).approve(address(position), 1000e6);

        deal(address(token1), address(this), 1100e18);
        IERC20(token1).approve(address(position), 1100e18);
        deal(address(token0), alice, 100e6);
        

    }

    function test_swap() public {
        uint160 sqrtPriceX96 = PriceMath.priceToSqrtPriceX96(2e18, 18);
        console.log(sqrtPriceX96);

        uint160 floorSqrtPriceX96 = PriceMath.priceToSqrtPriceX96(5e17, 18);
        int24 unnormalizedFloorTick = TickMath.getTickAtSqrtRatio(floorSqrtPriceX96);
        int24 floorTick = unnormalizedFloorTick / position.TICK_SPACING() * position.TICK_SPACING();
        console.log(floorTick);
        position.initPoolAndPosition(sqrtPriceX96, floorTick, 700e18, 400e18);
    }
}