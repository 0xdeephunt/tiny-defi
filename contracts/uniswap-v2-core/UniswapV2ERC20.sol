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

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol"; // EIP-2612 permit
import './interfaces/IUniswapV2ERC20.sol';

// This contract combines OpenZeppelin's ERC20 and ERC20Permit to implement
// the Uniswap V2 ERC20 token with EIP-2612 permit functionality.
// The liquidity token is used in pairs to represent shares of the pool.
contract UniswapV2ERC20 is IUniswapV2ERC20, ERC20, ERC20Permit{
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    // This is kept to maintain compatibility with the official Uniswap v2 implementation interface.
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() 
        ERC20("Uniswap V2", "UNI-V2")
        ERC20Permit("Uniswap V2") {
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function PERMIT_TYPEHASH() external pure returns (bytes32) {
        return PERMIT_TYPEHASH;
    }
}