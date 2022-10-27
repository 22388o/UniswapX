// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReactorEvents} from "../base/ReactorEvents.sol";
import {OrderInfoLib} from "../lib/OrderInfoLib.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {SignedOrder, ResolvedOrder, OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Generic reactor logic for settling off-chain signed orders
///     using arbitrary fill methods specified by a taker
abstract contract BaseReactor is IReactor, ReactorEvents {
    using SafeTransferLib for ERC20;
    using OrderInfoLib for OrderInfo;

    ISignatureTransfer public immutable permit2;

    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    /// @inheritdoc IReactor
    function execute(SignedOrder memory order, address fillContract, bytes calldata fillData) external override {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = resolve(order);

        _fill(resolvedOrders, fillContract, fillData);
    }

    /// @inheritdoc IReactor
    function executeBatch(SignedOrder[] memory orders, address fillContract, bytes calldata fillData) public override {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](orders.length);

        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }
        _fill(resolvedOrders, fillContract, fillData);
    }

    /// @notice validates and fills a list of orders, marking it as filled
    function _fill(ResolvedOrder[] memory orders, address fillContract, bytes calldata fillData) internal {
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory order = orders[i];
                order.info.validate();
                transferInputTokens(order, fillContract);
            }
        }

        IReactorCallback(fillContract).reactorCallback(orders, msg.sender, fillData);

        unchecked {
            // transfer output tokens to their respective recipients
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory resolvedOrder = orders[i];

                for (uint256 j = 0; j < resolvedOrder.outputs.length; j++) {
                    OutputToken memory output = resolvedOrder.outputs[j];
                    ERC20(output.token).safeTransferFrom(fillContract, output.recipient, output.amount);
                }

                emit Fill(orders[i].hash, msg.sender, resolvedOrder.info.nonce, resolvedOrder.info.offerer);
            }
        }
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(SignedOrder memory order) internal view virtual returns (ResolvedOrder memory resolvedOrder);

    /// @notice Transfers tokens to the fillContract
    /// @param order The encoded order to transfer tokens for
    /// @param to The address to transfer tokens to
    function transferInputTokens(ResolvedOrder memory order, address to) internal virtual;
}
