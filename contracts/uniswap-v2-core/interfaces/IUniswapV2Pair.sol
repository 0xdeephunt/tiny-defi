// SPDX-License-Identifier: MIT
// tiny-defi Contracts

pragma solidity ^0.8.20;

import './IUniswapV2ERC20.sol';

/**
 * @title IUniswapV2Pair
 * @notice The core interface for a Uniswap V2 Pair contract, representing an LP token.
 * It defines the functions necessary for all Automated Market Maker (AMM) interactions.
 * @dev This interface is a **copy** from the official Uniswap V2 Core repository 
 * for local use and compatibility. The implementation must follow the exact Uniswap V2 specifications.
 * @source Original code sourced from: https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol
 * @author Uniswap Labs (Original), 0xdeephunt (tiny-defi)
 * @license MIT
 */
interface IUniswapV2Pair is IUniswapV2ERC20 {
    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}