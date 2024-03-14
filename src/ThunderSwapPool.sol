// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IThunderSwapPool } from "./interfaces/IThunderSwapPool.sol";
import { LiquidityProviderToken } from "./LiquidityProviderToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ThunderSwapPool is IThunderSwapPool {
    using SafeERC20 for IERC20;

    IERC20 private immutable i_poolToken1;
    IERC20 private immutable i_poolToken2;
    LiquidityProviderToken private immutable i_liquidityProviderToken;
    uint256 constant MINIMUM_POOL_TOKEN_1_TO_DEPOSIT = 1e9;

    event LiquidityProviderTokenDeployed(address liquidityProviderToken);
    event LiquidityAdded(address liquidityProvider, uint256 poolToken1Amount, uint256 poolToken2Amount);

    error InputValueZeroNotAllowed();
    error DeadlinePassed(uint256 _deadline);
    error LiquidityProviderTokensToMintTooLow(
        uint256 liquidityProviderTokensToMint, uint256 minLiquidityProviderTokensToMint
    );
    error NotAPoolToken(IERC20 poolToken);
    error PoolTokensToDepositGreaterThanMaximumPoolTokensToDeposit(
        IERC20 poolToken, uint256 poolTokensToDeposit, uint256 maximumPoolTokensToDeposit
    );

    modifier notZero(uint256 _inputValue) {
        if (_inputValue == 0) revert InputValueZeroNotAllowed();
        _;
    }

    modifier beforeDeadline(uint256 _deadline) {
        if (_deadline < block.timestamp) revert DeadlinePassed(_deadline);
        _;
    }

    constructor(
        address _poolToken1,
        address _poolToken2,
        string memory _liquidityProviderTokenName,
        string memory _liquidityProviderTokenSymbol
    ) {
        i_liquidityProviderToken =
            new LiquidityProviderToken(_liquidityProviderTokenName, _liquidityProviderTokenSymbol);
        i_poolToken1 = IERC20(_poolToken1);
        i_poolToken2 = IERC20(_poolToken2);

        emit LiquidityProviderTokenDeployed(address(i_liquidityProviderToken));
    }

    function addLiquidity(
        uint256 _poolToken1Amount,
        uint256 _poolToken2Amount,
        uint256 _maximumPoolToken2ToDeposit,
        uint256 _minimumLiquidityProviderTokensToMint,
        uint256 _deadline
    )
        external
        notZero(_poolToken1Amount)
        notZero(_poolToken2Amount)
        notZero(_maximumPoolToken2ToDeposit)
        beforeDeadline(_deadline)
    {
        if (getTotalLiquidityProviderTokenSupply() == 0) {
            _addLiquidity(_poolToken1Amount, _poolToken2Amount, _poolToken1Amount);
        } else {
            uint256 poolToken1Reserves = i_poolToken1.balanceOf(address(this));
            uint256 poolToken2Reserves = i_poolToken2.balanceOf(address(this));

            // p1: pool token 1 reserves, dp1: pool token 1 amount to deposit
            // p2: pool token 2 reserves, dp2: pool token 2 amount to deposit
            // (p1 + dp1) / (p2 + dp2) = p1 / p2
            // (p1 * p2) + (p2 * dp1) = (p1 * p2) + (p1 * dp2)
            // dp2 = (p2 * dp1) / p1
            uint256 poolToken2ToDeposit = (poolToken2Reserves * _poolToken1Amount) / poolToken1Reserves;
            if (poolToken2ToDeposit > _maximumPoolToken2ToDeposit) {
                revert PoolTokensToDepositGreaterThanMaximumPoolTokensToDeposit(
                    i_poolToken2, poolToken2ToDeposit, _maximumPoolToken2ToDeposit
                );
            }

            // p: pool token 1 reserves, dp: pool token 1 amount to deposit
            // lp: total liquidity provider token supply
            // dlp: amount of liquidity provider token to mint to the liquidity provider
            // (p + dp) / (lp + dlp) = p / lp
            // (p * dp) + (dp * lp) = (p * lp) + (p * dlp)
            // dlp = (dp * lp) / p
            uint256 liquidityProviderTokensToMint =
                (_poolToken1Amount * getTotalLiquidityProviderTokenSupply()) / poolToken1Reserves;
            if (liquidityProviderTokensToMint < _minimumLiquidityProviderTokensToMint) {
                revert LiquidityProviderTokensToMintTooLow(
                    liquidityProviderTokensToMint, _minimumLiquidityProviderTokensToMint
                );
            }

            _addLiquidity(_poolToken1Amount, poolToken2ToDeposit, liquidityProviderTokensToMint);
        }
    }

    function getPoolToken1() external view returns (IERC20) {
        return i_poolToken1;
    }

    function getPoolToken2() external view returns (IERC20) {
        return i_poolToken2;
    }

    function getLiquidityProviderToken() external view returns (IERC20) {
        return i_liquidityProviderToken;
    }

    function getTotalLiquidityProviderTokenSupply() public view returns (uint256) {
        return i_liquidityProviderToken.totalSupply();
    }

    function _addLiquidity(
        uint256 _poolToken1Amount,
        uint256 _poolToken2Amount,
        uint256 _liquidityProviderTokensToMint
    )
        internal
    {
        i_liquidityProviderToken.mint(msg.sender, _liquidityProviderTokensToMint);

        i_poolToken1.safeTransferFrom(msg.sender, address(this), _poolToken1Amount);
        i_poolToken2.safeTransferFrom(msg.sender, address(this), _poolToken2Amount);

        emit LiquidityAdded(msg.sender, _poolToken1Amount, _poolToken2Amount);
    }
}