// test/mocks/MockProtocolRewards.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IProtocolRewards} from "../../src/interfaces/IProtocolRewards.sol";

contract MockProtocolRewards is IProtocolRewards {
    mapping(address => uint256) private _balances;

    function depositBatch(
        address[] calldata recipients,
        uint256[] calldata amounts,
        bytes4[] calldata reasons,
        string calldata memo
    ) external payable {
        for (uint256 i = 0; i < recipients.length; i++) {
            _balances[recipients[i]] += amounts[i];
        }
    }

    function deposit(
        address to,
        bytes4 why,
        string calldata comment
    ) external payable {
        _balances[to] += msg.value;
    }

    function withdrawFor(address recipient, uint256 amount) external {
        require(_balances[recipient] >= amount, "Insufficient balance");
        _balances[recipient] -= amount;
        (bool success,) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
}