// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAxelarGasService} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IERC20} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol";

contract AucentiveSpoke {
  IAxelarGateway public immutable gateway;
  IAxelarGasService public immutable gasService;

  IERC20 public immutable USDC;

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

  // IERC20 public USDC;

  address private _owner;

  mapping(bytes32 => ServicePaymentSlip) private _servicePaymentSlips;

  mapping(address => uint256) private _outstandingBalances; // earned balances that are not yet withdrawn

  constructor(address _gateway, address _gasService) {
    gateway = IAxelarGateway(_gateway);
    gasService = IAxelarGasService(_gasService);
    USDC = IERC20(gateway.tokenAddresses("USDC"));

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
    USDC.transfer(recipient, balance);
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
      USDC.allowance(msg.sender, address(this)) >= payAmount,
      "Insufficient allowance for payment"
    );

    require(msg.value > 0, "Gas payment is required");

    // Approval required
    USDC.transferFrom(msg.sender, address(this), payAmount);

    USDC.approve(address(gateway), payAmount);

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

  function sendToMany(
    string memory destinationChain,
    string memory destinationAddress,
    address[] calldata destinationAddresses,
    string memory symbol,
    uint256 amount
  ) external payable {
    require(msg.value > 0, "Gas payment is required");

    address tokenAddress = gateway.tokenAddresses(symbol);

    IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
    IERC20(tokenAddress).approve(address(gateway), amount);

    bytes memory payload = abi.encode(destinationAddresses);

    gasService.payNativeGasForContractCallWithToken{value: msg.value}(
      address(this),
      destinationChain,
      destinationAddress,
      payload,
      symbol,
      amount,
      msg.sender
    );

    gateway.callContractWithToken(
      destinationChain,
      destinationAddress,
      payload,
      symbol,
      amount
    );
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
