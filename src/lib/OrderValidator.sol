// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../interfaces/ReactorStructs.sol";
import {IValidationContract} from "../interfaces/IValidationContract.sol";

contract OrderValidator {
    error InvalidReactor();
    error DeadlinePassed();
    error InvalidOrder();

    /// @notice Validates an order, reverting if invalid
    /// @param order The order to validate
    function validateOrder(OrderInfo memory order) public view {
        if (address(this) != order.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > order.deadline) {
            revert DeadlinePassed();
        }

        if (block.timestamp < order.deadline) {
            revert DeadlinePassed();
        }

        // TODO: maybe bubble up error
        // TODO: maybe needs to not be view
        if (
            order.validationContract != address(0)
                && !IValidationContract(order.validationContract).validate(order)
        ) {
            revert InvalidOrder();
        }
    }
}
