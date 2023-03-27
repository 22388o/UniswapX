// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

address constant ETH_ADDRESS = 0x0000000000000000000000000000000000000000;

/// @title CurrencyLibrary
/// @dev This library allows for transferring native ETH and ERC20s via direct taker OR fill contract.
library CurrencyLibrary {
    using SafeTransferLib for ERC20;

    /// @notice Thrown when a native transfer fails
    error NativeTransferFailed();

    /// @notice Get the balance of a currency for addr
    /// @param currency The currency to get the balance of
    /// @param addr The address to get the balance of
    /// @return balance The balance of the currency for addr
    function balanceOf(address currency, address addr) internal view returns (uint256 balance) {
        if (currency == ETH_ADDRESS) {
            balance = addr.balance;
        } else {
            balance = ERC20(currency).balanceOf(addr);
        }
    }

    /// @notice Transfer currency to recipient
    /// @param currency The currency to transfer
    /// @param recipient The recipient of the currency
    /// @param amount The amount of currency to transfer
    function transfer(address currency, address recipient, uint256 amount) internal {
        if (currency == ETH_ADDRESS) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert NativeTransferFailed();
        } else {
            ERC20(currency).safeTransfer(recipient, amount);
        }
    }

    /// @notice Transfer currency from msg.sender to the recipient
    /// @dev if curency is ETH, the value must have been sent in the execute call and is transferred directly
    /// @dev if curency is token, the value is transferred from msg.sender via permit2
    /// @param currency The currency to transfer
    /// @param recipient The recipient of the currency
    /// @param amount The amount of currency to transfer
    function transferFromDirectTaker(address currency, address recipient, uint256 amount, address permit2) internal {
        if (currency == ETH_ADDRESS) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert NativeTransferFailed();
        } else {
            IAllowanceTransfer(permit2).transferFrom(msg.sender, recipient, SafeCast.toUint160(amount), currency);
        }
    }
}
