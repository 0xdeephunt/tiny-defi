pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC2612} from "@openzeppelin/contracts/interfaces/IERC2612.sol";

interface IUniswapV2ERC20 is IERC20, IERC2612 {
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

}
