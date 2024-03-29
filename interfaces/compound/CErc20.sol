// Copyright (C) 2020 Zerion Inc. <https://zerion.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: LGPL-3.0-only
//it was supposed to be redeemAmount as a parameter for redeemUnderlying and uint paramters were made uint256
pragma solidity ^0.6.11;

/**
 * @dev CErc20 contract interface.
 * The CErc20 contract is available here
 * github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20.sol.
 */
interface CErc20 {

    function borrowBalanceCurrent(address) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function mint(uint256) external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256 ) external returns (uint256); 

    function borrowBalanceStored(address) external view returns (uint256);

    function underlying() external view returns (address);

    function borrowIndex() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);
}
