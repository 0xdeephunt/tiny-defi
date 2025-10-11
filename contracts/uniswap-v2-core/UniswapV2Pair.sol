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

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {initializer} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './interfaces/IUniswapV2Callee.sol';

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

    // Notes on reserves:
    // reserve0 and reserve1 are the pair's recorded liquidity values used by the AMM.
    // They may differ from the ERC20 token balances held by the contract because balances
    // can include transient or external transfers (for example: direct token transfers,
    // in-flight swap callbacks, or flash-loan style interactions). Relying on recorded
    // reserves (instead of raw balances) prevents manipulation of pricing and preserves
    // the invariant k = reserve0 * reserve1. Reserves are updated only via the contract's
    // internal update logic (e.g. _update) after completed operations.
    uint private reserve0;              // current reserve of token0 for this pair
    uint private reserve1;              // current reserve of token1 for this pair
    uint32  private blockTimestampLast; // last block timestamp

    uint public price0CumulativeLast;   // cumulative price for token0
    uint public price1CumulativeLast;   // cumulative price for token1

    // Automated Market Maker (AMM) pool: k = reserve0 * reserve1
    uint public kLast; // as of immediately after the most recent liquidity event

    // compatibility with Uniswap V2
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = uint112(reserve0);
        _reserve1 = uint112(reserve1);
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
    function initialize(address _token0, address _token1) external initializer {
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
        uint _reserve0 = reserve0;
        uint _reserve1 = reserve1;
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
        uint _reserve0 = reserve0;
        uint _reserve1 = reserve1;
        // Get current balances after user transfers liquidity tokens to the pair
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // must be defined here since totalSupply can update
        // Calculate amounts of token0 and token1 to withdraw based on the share of liquidity tokens being burned
        amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED'); // Ensure amounts are positive

        _burn(address(this), liquidity); // burn the liquidity tokens
        // Transfer the underlying tokens to the user
        IERC20(token0).safeTransfer(to, amount0); 
        IERC20(token1).safeTransfer(to, amount1);

        // update balances after the transfers
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        // update reserves and cumulative prices
        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) {
            // Update kLast by multiplying the updated reserves
            kLast = uint(reserve0) * reserve1;
        }
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        uint _reserve0 = reserve0;
        uint
         _reserve1 = reserve1;
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');
        require(to != token0 && to != token1, 'UniswapV2: INVALID_TO');

        // transfer the output tokens to the recipient first
        if (amount0Out > 0) {
            IERC20(token0).safeTransfer(to, amount0Out);
        }
        if (amount1Out > 0) {
            IERC20(token1).safeTransfer(to, amount1Out);
        }

        // If data is provided, call the recipient contract for flash swap functionality
        if (data.length > 0) {
            IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        }

        // Get updated balances after the transfers and potential flash swap callback
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        // Calculate amounts of token0 and token1 that were sent in by the user
        uint amount0In = balance0 > (_reserve0 - amount0Out) ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > (_reserve1 - amount1Out) ? balance1 - (_reserve1 - amount1Out) : 0;
        // Ensure that at least one of the input amounts is positive
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');

        // Adjusted balances to account for the 0.3% fee on input amounts
        uint balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        // Ensure the invariant k is maintained after accounting for fees
        require(balance0Adjusted * balance1Adjusted >= uint(_reserve0) * _reserve1 * (1000**2), 'UniswapV2: K');

        // Update reserves and cumulative prices
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // Anyone can call this function to withdraw any excess tokens that may have been sent to the pair contract
    // directly (not through mint or swap).
    // It forces balances to match reserves.
    function skim(address to) external nonReentrant {
        require(to != token0 && to != token1, 'UniswapV2: INVALID_TO');

        uint _balance0 = IERC20(token0).balanceOf(address(this));
        uint _balance1 = IERC20(token1).balanceOf(address(this));

        IERC20(token0).safeTransfer(to, _balance0 - reserve0);
        IERC20(token1).safeTransfer(to, _balance1 - reserve1);
    }

    // Anyone can call this function to force the reserves to match the actual token balances
    function sync() external nonReentrant {
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1, reserve0, reserve1);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // If fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint _reserve0, uint _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0) * _reserve1);
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply * (rootK - rootKLast);
                    uint denominator = (rootK * 5) + rootKLast;
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) {
                        _mint(feeTo, liquidity);
                    }
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }    
    }

    // Update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint _reserve0, uint _reserve1) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // Update price accumulators with the time-weighted average price
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }

        // Update reserves to the new balances
        reserve0 = balance0;
        reserve1 = balance1;

        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }
}
