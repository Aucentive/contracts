// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IERC20} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol";
import {IAxelarGasService} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";

// import {IAddressWhitelist} from "@uma/core/contracts/common/implementation/AddressWhitelist.sol";
// import {OptimisticOracleV3Interface, IERC20} from "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
// import {IdentifierWhitelistInterface} from "@uma/core/contracts/data-verification-mechanism/interfaces/IdentifierWhitelistInterface.sol";

import {FTDataAsserter} from "./FTDataAsserter.sol";

contract AucentiveHub is AxelarExecutable {
  event ServicePaid(bytes32 serviceId, uint256 payAmount);
  event ServiceCompleted(bytes32 serviceId);
  event ServiceCancelled(bytes32 serviceId);

  enum ServiceStatus {
    PENDING_PAYMENT, // pending payment from sender (could be from anyone)
    PENDING_COMPLETION, // pending work/reply from recipient (so, already sent to user)
    CANCELLED, // cancelled
    INVALIDATED, // invalidated by system
    FAILED, // failed to deliver (for whatever reason)
    COMPLETED // recipient has replied to email or executed services
  }

  // pack slots (amounts are unfortunately 256 bits)
  struct Service {
    uint256 minAmount; // min required by recipient
    uint256 paidAmount; // amount paid by sender
    uint64 createdAt; // UNIX seconds
    uint64 paidAt; // UNIX seconds
    uint64 completedAt; // UNIX seconds
    uint64 duration; // valid duration from `createdAt`
    ServiceStatus status;
    // bytes32 request; // FT, email, github, etc.
  }

  IAxelarGasService public immutable gasService;

  FTDataAsserter public ftDataAsserter;

  IERC20 public PAYMENT_TOKEN;

  address private _owner;

  mapping(bytes32 => Service) public _services;

  mapping(address => uint256) private _outstandingBalances; // earned balances that are not yet withdrawn

  // mapping(bytes32 => uint256) public requestTimes;

  constructor(
    address _gateway,
    address _gasService,
    address _usdc,
    address _ftDataAsserter
  ) AxelarExecutable(_gateway) {
    gasService = IAxelarGasService(_gasService);
    PAYMENT_TOKEN = IERC20(_usdc);
    // USDC = IERC20(gateway.tokenAddresses("USDC"));

    ftDataAsserter = FTDataAsserter(_ftDataAsserter);

    _transferOwnership(msg.sender);
  }

  modifier onlyOwner() {
    require(_owner == msg.sender, "Ownable: caller is not the owner");
    _;
  }

  /**
   *
   * Logic
   *
   */

  function createService(
    bytes32 serviceId,
    uint256 minAmount,
    uint64 duration
  ) public onlyOwner {
    require(_services[serviceId].createdAt == 0, "Service already exists");
    _services[serviceId] = Service({
      minAmount: minAmount,
      paidAmount: 0,
      createdAt: uint64(block.timestamp),
      paidAt: 0,
      completedAt: 0,
      duration: duration,
      status: ServiceStatus.PENDING_PAYMENT
    });
  }

  function modifyServiceStatus(
    bytes32 serviceId,
    ServiceStatus status,
    address serviceSender,
    address serviceRecipient
  ) public onlyOwner {
    require(
      serviceSender != address(0) && serviceRecipient != address(0),
      "Service sender & recipient cannot be zero address"
    );

    require(_services[serviceId].createdAt != 0, "Service does not exist");

    Service storage service = _services[serviceId]; // SLOAD here to reduce gas (load as `storage`!)
    service.status = status;

    if (status == ServiceStatus.COMPLETED) {
      service.completedAt = uint64(block.timestamp);
      _outstandingBalances[serviceRecipient] += service.paidAmount;

      emit ServiceCompleted(serviceId);
    } else if (
      status == ServiceStatus.CANCELLED || status == ServiceStatus.FAILED
    ) {
      if (service.paidAmount > 0) {
        // refund sender
        PAYMENT_TOKEN.transfer(serviceSender, service.paidAmount);
        service.paidAmount = 0;
      }

      emit ServiceCancelled(serviceId);
    } else if (status == ServiceStatus.INVALIDATED) {
      // TODO: invalidated service due to reasons like spam, flagged for malicious intent, etc.
    }
  }

  function payForService(bytes32 serviceId, uint256 payAmount) public {
    Service memory service = _services[serviceId]; // SLOAD here to reduce gas (load as `view-only`!)

    require(service.createdAt != 0, "Service does not exist");
    require(
      service.status == ServiceStatus.PENDING_PAYMENT,
      "Service is not pending payment"
    );
    require(
      PAYMENT_TOKEN.balanceOf(msg.sender) >= service.minAmount,
      "Insufficient balance for payment"
    );
    require(
      PAYMENT_TOKEN.allowance(msg.sender, address(this)) >= payAmount,
      "Insufficient allowance for payment"
    );

    // Approval required
    PAYMENT_TOKEN.transferFrom(msg.sender, address(this), payAmount);

    _markServiceAsPaid(serviceId, payAmount);
  }

  function settleServiceViaDataAsserter(bytes32 serviceId) public {
    (bool isSettled, bytes32 settledData) = ftDataAsserter.getData(serviceId);

    if (!isSettled) {
      revert("Data not settled");
    }

    if (settledData == bytes32("yes")) {
      _markServiceAsCompleted(serviceId);
    } else if (settledData == bytes32("no")) {
      _markServiceAsFailed(serviceId);
    } else {
      revert("Invalid data");
    }
  }

  function _markServiceAsPaid(bytes32 serviceId, uint256 payAmount) internal {
    Service storage service = _services[serviceId]; // SLOAD here to reduce gas (load as `storage`!)

    service.paidAmount = payAmount;
    service.paidAt = uint64(block.timestamp);
    service.status = ServiceStatus.PENDING_COMPLETION;

    emit ServicePaid(serviceId, payAmount);
  }

  function _markServiceAsCompleted(bytes32 serviceId) internal {
    Service storage service = _services[serviceId];
    service.status = ServiceStatus.COMPLETED;
  }

  function _markServiceAsFailed(bytes32 serviceId) internal {
    Service storage service = _services[serviceId];
    service.status = ServiceStatus.FAILED;
  }

  // function withdrawBalance() public {
  //     uint256 balance = _outstandingBalances[msg.sender];
  //     require(balance > 0, "No balance to withdraw");
  //
  //     _outstandingBalances[msg.sender] = 0;
  //     PAYMENT_TOKEN.transfer(msg.sender, balance);
  // }

  function withdrawBalance() public {
    uint256 balance = _outstandingBalances[msg.sender];
    // require(balance > 0, "No balance to withdraw");

    _outstandingBalances[msg.sender] = 0;
    PAYMENT_TOKEN.transfer(msg.sender, balance);
  }

  /**
   *
   * Axelar
   *
   * For bridging tokens and NFTs as payments
   *
   */

  function _execute(
    string calldata, // sourceChain
    string calldata, // sourceAddress
    bytes calldata payload
  ) internal override {
    (ServiceStatus status, bytes32 serviceId) = abi.decode(
      payload,
      (ServiceStatus, bytes32)
    );

    require(_services[serviceId].createdAt != 0, "Service does not exist");

    Service storage service = _services[serviceId]; // SLOAD here to reduce gas (load as `storage`!)
    service.status = status;
  }

  /**
   *
   * Misc.
   *
   */

  function owner() public view returns (address) {
    return _owner;
  }

  function transferOwnership(address newOwner) public onlyOwner {
    require(newOwner != address(0), "Ownable: ew owner is the zero address");
    _transferOwnership(newOwner);
  }

  function _transferOwnership(address newOwner) internal {
    _owner = newOwner;
  }

  function services(bytes32 serviceId) public view returns (Service memory) {
    return _services[serviceId];
  }

  function changePaymentToken(address newToken) public onlyOwner {
    PAYMENT_TOKEN = IERC20(newToken);
  }

  function changeFTDataAsserter(address _ftDataAsserter) public onlyOwner {
    ftDataAsserter = FTDataAsserter(_ftDataAsserter);
  }
}
