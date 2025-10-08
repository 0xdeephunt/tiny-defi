// SPDX-License-Identifier: MIT

/*//////////////////////////////////////////////////////////////////////////////
                        TinyDeFi Contracts
////////////////////////////////////////////////////////////////////////////////
TinyDeFi is a copy of Uniswap V2 contract adapted to use OpenZeppelin's
libraries for better security and standard compliance.
Original code sourced from: https://github.com/Uniswap/v2-core
Authors: Uniswap Labs (Original), 0xdeephunt (TinyDeFi)
License: MIT
//////////////////////////////////////////////////////////////////////////////*/

pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';

// This contract implements a Uniswap V2 Pair, which is a liquidity pool for two ERC20 tokens.
// It inherits from UniswapV2ERC20 for the LP token functionality and ReentrancyGuard for security against reentrant calls.
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
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

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint public constant MINIMUM_LIQUIDITY = 10**3;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/
    address public factory;     // The factory contract that deployed this pair contract
    address public token0;      // Address of the first token in the pair
    address public token1;      // Address of the second token in the pair

    // use a single storage slot for reserves to save gas
    // accessible via getReserves
    uint112 private reserve0;           // current reserve of token0 for this pair
    uint112 private reserve1;           // current reserve of token1 for this pair
    uint32  private blockTimestampLast; // last block timestamp

    uint public price0CumulativeLast;   // cumulative price for token0
    uint public price1CumulativeLast;   // cumulative price for token1

    // Automated Market Maker (AMM) pool: k = reserve0 * reserve1
    uint public kLast; // as of immediately after the most recent liquidity event

    // save gas by useing a single storage slot
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        // The factory is the deployer of the pair contract
        factory = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external nonReentrant returns (uint liquidity) {
        // Get current reserves before user transfers tokens
        uint112 _reserve0 = reserve0;
        uint112 _reserve1 = reserve1;
        // Get current balances after user transfers tokens to the pair
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        // To calculate amounts of token0 and token1 that were added to the pool
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);

        // totalsupply: the current total supply of liquidity tokens
        // amount0 and amount1: the amounts of the two tokens being added to the pool
        // _reserve0 and _reserve1: the current reserves of each token in the pool
        uint _totalSupply = totalSupply; // must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            // First liquidity provision
            // Initial liquidity is the geometric mean of the amounts provided
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            // Subsequent liquidity provision
            // Mint liquidity proportional to the smallest ratio of added amounts to reserves.
            // It will keep a balanced ratio of token0 and token1 in the pool.
            // The excess amount0 or amount1 will not be minted as liquidity tokens.
            // The excess will remain in the pool and can be withdrawn by any liquidity provider using skim().
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED'); // Ensure liquidity is positive
        _mint(to, liquidity); // transfer liquidity to the provider, and totalSupply is updated

        _update(balance0, balance1, _reserve0, _reserve1); // Update reserves and cumulative prices
        if (feeOn) kLast = uint(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);           
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external nonReentrant returns (uint amount0, uint amount1) {
        uint112 _reserve0 = reserve0;
        uint112 _reserve1 = reserve1;
        // Get current balances after user transfers liquidity tokens to the pair
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // must be defined here since totalSupply can update
        amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED'); // Ensure amounts are positive

        _burn(address(this), liquidity); // burn the liquidity tokens sent to the pair
        IERC20(token0).safeTransfer(to, amount0); // send token0 to the user
        IERC20(token1).safeTransfer(to, amount1); // send token1 to the user
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1); // Update reserves and cumulative prices
        if (feeOn) kLast = uint(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
    }

    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
    }
}