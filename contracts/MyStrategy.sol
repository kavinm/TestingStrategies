// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/badger/IController.sol";

import "../interfaces/aave/ILendingPool.sol";
import "../interfaces/aave/IAaveIncentivesController.sol";

import {BaseStrategy} from "../deps/BaseStrategy.sol";

import "../interfaces/uniswap/ISwapRouter.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    address public aToken; // Token we provide liquidity with
    address public reward; // Token we farm and swap to want / aToken
    address public constant LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9; //lending pool address
    address public constant INCENTIVES_CONTROLLER = 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5; //rewards

    address public constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // aave router
    address public constant AAVE_TOKEN = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9 ;
    address public constant WETH_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;


    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _controller,
            _keeper,
            _guardian
        );

        /// @dev Add config here
        want = _wantConfig[0];
        aToken = _wantConfig[1];
        reward = _wantConfig[2];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @dev do one off approvals here
        IERC20Upgradeable(want).safeApprove(LENDING_POOL, type(uint256).max);
        // the lending pool address is approved here

        IERC20Upgradeable(reward).safeApprove(ROUTER, type(uint256).max);
        //uniswap approved here

        IERC20Upgradeable(AAVE_TOKEN).safeApprove(ROUTER, type(uint256).max);
        //aave token approved
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external pure override returns (string memory) {
        return "wBTC AAVE Rewards";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public view override returns (uint256) {
        return IERC20Upgradeable(aToken).balanceOf(address(this));
        //returns balance of Aave token of this contract's address
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public view override returns (bool) {
        return true;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens()
        public
        view
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = aToken;
        protectedTokens[2] = reward;
        return protectedTokens;
    }

    /// ===== Permissioned Actions: Governance =====
    /// @notice Delete if you don't need!
    function setKeepReward(uint256 _setKeepReward) external {
        _onlyGovernance();
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for (uint256 x = 0; x < protectedTokens.length; x++) {
            require(
                address(protectedTokens[x]) != _asset,
                "Asset is protected"
            );
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        ILendingPool(LENDING_POOL).deposit(want, _amount, address(this), 0); // (asset, amount, onBehalfOf, referralCode)

        // we are casting LendingPool address into ILendingPool interface
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        ILendingPool(LENDING_POOL).withdraw(
            want,
            balanceOfPool(),
            address(this)
        ); //(asset, amount, to)
    }

    /// @dev withdraw the specified amount of want, liquidate from aToken to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        if (_amount > balanceOfPool()) {
            _amount = balanceOfPool();
        }
        ILendingPool(LENDING_POOL).withdraw(want, _amount, address(this));
        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));

        // Write your code here
        //figure out and claim our rewards

        address[] memory assets = new address[](1);
        assets[0] = aToken;

        IAaveIncentivesController(INCENTIVES_CONTROLLER).claimRewards(assets, type(uint256).max, address(this)); //(assests, amount, to)

        uint256 rewardsAmount = IERC20Upgradeable(reward).balanceOf(address(this)); // checks how much the reward is

        if(rewardsAmount == 0){ //must return 0 if no rewards
            return 0;
        }

        //swap from stkAAVE to AAVE
        ISwapRouter.ExactInputSingleParams memory fromRewardToAAVEParams = ISwapRouter.ExactInputSingleParams(
            reward,
            AAVE_TOKEN,
            10000,
            address(this),
            now,
            rewardsAmount,      //exploitable, can use chainlink or some oracle to fix
            0,
            0
        );
        ISwapRouter(ROUTER).exactInputSingle(fromRewardToAAVEParams);

        bytes memory path = abi.encodePacked(AAVE_TOKEN, uint24(10000), WETH_TOKEN, uint24(10000), want); // the path from aave to weth
        //up to 1% cost is the 10000


        ISwapRouter.ExactInputParams memory fromAAVETowBTCParams = ISwapRouter.ExactInputParams(
            path,
            address(this),
            now,                                                    //exploitable, can use chainlink or some oracle to fix
            IERC20Upgradeable(AAVE_TOKEN).balanceOf(address(this)),
            0
        );

        ISwapRouter(ROUTER).exactInput(fromAAVETowBTCParams); //swapping from aave to wbtc using uniswap like above


        
        uint256 earned =IERC20Upgradeable(want).balanceOf(address(this)).sub(_before);

        /// @notice Keep this in so you get paid!
        (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) =
            _processPerformanceFees(earned);

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earned, block.number);

        return earned;
    }

    // Alternative Harvest with Price received from harvester, used to avoid exessive front-running
    function harvest(uint256 price)
        external
        whenNotPaused
        returns (uint256 harvested)
    {}

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();

        if (balanceOfWant() > 0) {
            ILendingPool(LENDING_POOL).deposit(
                want,
                balanceOfWant(),
                address(this),
                0
            );
            //balanceOfWant is from BaseStrategy.sol
        }
        //if there is a balance deposit it
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _processPerformanceFees(uint256 _amount)
        internal
        returns (
            uint256 governancePerformanceFee,
            uint256 strategistPerformanceFee
        )
    {
        governancePerformanceFee = _processFee(
            want,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistPerformanceFee = _processFee(
            want,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }
}
