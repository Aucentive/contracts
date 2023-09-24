// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IERC20} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol";
import {IAxelarGasService} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";

// import {AddressWhitelist} from "@uma/core/contracts/common/implementation/AddressWhitelist.sol";
// import {OptimisticOracleV2Interface, IERC20} from "@uma/core/contracts/optimistic-oracle-v2/interfaces/OptimisticOracleV2Interface.sol";
// import {IdentifierWhitelistInterface} from "@uma/core/contracts/data-verification-mechanism/interfaces/IdentifierWhitelistInterface.sol";

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
  }

  IAxelarGasService public immutable gasService;

  IERC20 public immutable USDC;

  address private _owner;

  mapping(bytes32 => Service) public _services;

  mapping(address => uint256) private _outstandingBalances; // earned balances that are not yet withdrawn

  // OptimisticOracleV2Interface public oo;

  // mapping(bytes32 => uint256) public requestTimes;

  constructor(
    address _gateway,
    address _gasService,
    address _usdc
  )
    // address _umaOo
    AxelarExecutable(_gateway)
  {
    gasService = IAxelarGasService(_gasService);
    USDC = IERC20(_usdc);
    // USDC = IERC20(gateway.tokenAddresses("USDC"));

    // oo = OptimisticOracleV2Interface(_umaOo);

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
        USDC.transfer(serviceSender, service.paidAmount);
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
      USDC.balanceOf(msg.sender) >= service.minAmount,
      "Insufficient balance for payment"
    );
    require(
      USDC.allowance(msg.sender, address(this)) >= payAmount,
      "Insufficient allowance for payment"
    );

    // Approval required
    USDC.transferFrom(msg.sender, address(this), payAmount);

    _markServiceAsPaid(serviceId, payAmount);
  }

  function _markServiceAsPaid(bytes32 serviceId, uint256 payAmount) internal {
    Service storage service = _services[serviceId]; // SLOAD here to reduce gas (load as `storage`!)

    service.paidAmount = payAmount;
    service.paidAt = uint64(block.timestamp);
    service.status = ServiceStatus.PENDING_COMPLETION;

    emit ServicePaid(serviceId, payAmount);
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
    USDC.transfer(msg.sender, balance);
  }

  /**
   *
   * UMA Optimistic Oracle
   *
   * For verifying some off-chain states for service status modification, e.g. complete
   *
   */

  /*
  function requestData(
    bytes32 identifier,
    string memory ancillaryString
  ) public {
    uint256 requestTime = block.timestamp;
    requestTimes[identifier] = requestTime;

    bytes memory ancillaryData = bytes(ancillaryString);
    uint256 reward = 0; // Set the reward to 0 (so we dont have to fund it from this contract).

    // Now, make the price request to the Optimistic oracle and set the liveness to 30 so it will settle quickly.
    oo.requestPrice(
      identifier,
      requestTime,
      ancillaryData,
      IERC20(USDC),
      reward
    );
    oo.setCustomLiveness(identifier, requestTime, ancillaryData, 30);
  }

  function settleRequest(
    bytes32 identifier,
    string memory ancillaryString
  ) public {
    oo.settle(
      address(this),
      identifier,
      requestTimes[identifier],
      bytes(ancillaryString)
    );
  }

  // Fetch the resolved price from the Optimistic Oracle that was settled.
  function getSettledData(
    bytes32 identifier,
    string memory ancillaryString
  ) public view returns (int256) {
    return
      oo
        .getRequest(
          address(this),
          identifier,
          requestTimes[identifier],
          bytes(ancillaryString)
        )
        .resolvedPrice;
  }

  function modifyOpimisticOracle(address _oo) public onlyOwner {
    oo = OptimisticOracleV2Interface(_oo);
  }
  */

  /**
   *
   * Axelar
   *
   * For bridging tokens and NFTs as payments
   *
   */

  function _executeWithToken(
    string calldata,
    string calldata,
    bytes calldata payload,
    string calldata tokenSymbol,
    uint256 amount
  ) internal override {
    address[] memory recipients = abi.decode(payload, (address[]));
    address tokenAddress = gateway.tokenAddresses(tokenSymbol);

    uint256 sentAmount = amount / recipients.length;
    for (uint256 i = 0; i < recipients.length; i++) {
      IERC20(tokenAddress).transfer(recipients[i], sentAmount);
    }
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
}
