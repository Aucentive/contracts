// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAxelarGasService} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IERC20} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol";

// import {AddressWhitelist} from "@uma/core/contracts/common/implementation/AddressWhitelist.sol";
// import {OptimisticOracleV2Interface, IERC20} from "@uma/core/contracts/optimistic-oracle-v2/interfaces/OptimisticOracleV2Interface.sol";
// import {IdentifierWhitelistInterface} from "@uma/core/contracts/data-verification-mechanism/interfaces/IdentifierWhitelistInterface.sol";

contract AucentiveSpoke {
  IAxelarGateway public immutable gateway;
  IAxelarGasService public immutable gasService;

  event ServicePaymentSent(bytes32 serviceId, uint256 payAmount);
  event ServicePaymentConfirmed(bytes32 serviceId);
  event ServicePaymentRefunded(bytes32 serviceId, uint256 refundAmount);

  enum ServicePaymentSlipStatus {
    Pending,
    Paid,
    Refunded
  }

  struct ServicePaymentSlip {
    address sender;
    uint256 paidAmount; // amount paid by sender
    uint64 paidAt; // UNIX seconds
    uint64 confirmedAt; // UNIX seconds
    ServicePaymentSlipStatus status;
  }

  IERC20 public PAYMENT_TOKEN;

  address private _owner;

  mapping(bytes32 => ServicePaymentSlip) private _servicePaymentSlips;

  mapping(address => uint256) private _outstandingBalances; // earned balances that are not yet withdrawn

  constructor(address _gateway, address _gasService) {
    // address _umaOo
    gateway = IAxelarGateway(_gateway);
    gasService = IAxelarGasService(_gasService);
    PAYMENT_TOKEN = IERC20(gateway.tokenAddresses("USDC"));

    _transferOwnership(msg.sender);
  }

  modifier onlyOwner() {
    require(_owner == msg.sender, "Ownable: caller is not the owner");
    _;
  }

  function withdrawBalanceViaAdmin(address recipient) public onlyOwner {
    uint256 balance = _outstandingBalances[recipient];
    require(balance > 0, "No balance to withdraw");

    _outstandingBalances[recipient] = 0;
    PAYMENT_TOKEN.transfer(recipient, balance);
  }

  /**
   *
   * Axelar
   *
   */

  /// @dev Cross-chain service payment — only USDC for now
  function sendServicePayment(
    string memory destinationChain,
    string memory destinationAddress,
    bytes32 serviceId,
    uint256 payAmount
  ) public payable {
    require(msg.value > 0, "Gas amount must be greater than 0");

    require(
      PAYMENT_TOKEN.allowance(msg.sender, address(this)) >= payAmount,
      "Insufficient allowance for payment"
    );

    require(msg.value > 0, "Gas payment is required");

    // Approval required
    PAYMENT_TOKEN.transferFrom(msg.sender, address(this), payAmount);

    PAYMENT_TOKEN.approve(address(gateway), payAmount);

    // First, lock-in tokens on this contract (we don't actually send the tokens to the target chain)
    // Then, send the payload of `serviceId` and `payAmount` to the target chain

    bytes memory payload = abi.encode(serviceId, payAmount);

    gasService.payNativeGasForContractCallWithToken{value: msg.value}(
      address(this),
      destinationChain,
      destinationAddress,
      payload,
      "USDC",
      payAmount,
      msg.sender
    );

    gateway.callContractWithToken(
      destinationChain,
      destinationAddress,
      payload,
      "USDC",
      payAmount
    );

    emit ServicePaymentSent(serviceId, payAmount);
  }

  function settleService(
    string calldata destinationChain,
    string calldata destinationAddress,
    string calldata value
  ) external payable {
    require(msg.value > 0, "Gas payment is required");

    bytes memory payload = abi.encode(value);
    gasService.payNativeGasForContractCall{value: msg.value}(
      address(this),
      destinationChain,
      destinationAddress,
      payload,
      msg.sender
    );
    gateway.callContract(destinationChain, destinationAddress, payload);
  }

  /**
   *
   * Misc.
   *
   */

  function owner() public view virtual returns (address) {
    return _owner;
  }

  function transferOwnership(address newOwner) public virtual onlyOwner {
    require(newOwner != address(0), "Ownable: ew owner is the zero address");
    _transferOwnership(newOwner);
  }

  function _transferOwnership(address newOwner) internal virtual {
    _owner = newOwner;
  }
}
