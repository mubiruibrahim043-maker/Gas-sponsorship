// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GasSponsor is Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error GasSponsor__ZeroAddress();
    error GasSponsor__ZeroAmount();
    error GasSponsor__InsufficientBalance();
    error GasSponsor__OnlyRouter();
    error GasSponsor__TransferFailed();
    error GasSponsor__ExceedsMaxGas();
    error GasSponsor__UnauthorizedUser();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed sender, uint256 amount);

    event Withdrawal(address indexed owner, uint256 amount);

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    event GasReleased(address indexed relayer, uint256 amount);

    event MaxGasPerTransactionUpdated(uint256 oldAmount, uint256 newAmount);

    event UserAuthorizationUpdated(address indexed user, bool authorized);

    /// @notice SHA-256 hash of the immutable Gas Sponsorship v1 security report.
    /// @dev The report is stored in the repository at:
    ///      security/GasSponsorship-Security-Audit-v1.md
    bytes32 public constant SECURITY_REPORT_HASH = 0xa0800cada3cb23de6656c6edf01f8f1c66f802699c6cba55dab2cf0f8a23f255;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public router;
    uint256 public maxGasPerTransaction;
    mapping(address => bool) public authorizedUsers;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) {
            revert GasSponsor__ZeroAddress();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyRouter() {
        if (msg.sender != router) {
            revert GasSponsor__OnlyRouter();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                            ROUTER SETUP
    //////////////////////////////////////////////////////////////*/

    function setRouter(address newRouter) external onlyOwner {
        if (newRouter == address(0)) {
            revert GasSponsor__ZeroAddress();
        }

        address oldRouter = router;

        router = newRouter;

        emit RouterUpdated(oldRouter, newRouter);
    }

    function setMaxGasPerTransaction(uint256 newAmount) external onlyOwner {
        if (newAmount == 0) revert GasSponsor__ZeroAmount();

        uint256 oldAmount = maxGasPerTransaction;
        maxGasPerTransaction = newAmount;

        emit MaxGasPerTransactionUpdated(oldAmount, newAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          RELEASE GAS
    //////////////////////////////////////////////////////////////*/

    function releaseGas(address, address relayer, uint256 amount) external onlyRouter {
        if (relayer == address(0)) revert GasSponsor__ZeroAddress();
        if (amount == 0) revert GasSponsor__ZeroAmount();
        if (amount > maxGasPerTransaction) {
            revert GasSponsor__ExceedsMaxGas();
        }
        if (address(this).balance < amount) {
            revert GasSponsor__InsufficientBalance();
        }

        (bool success,) = payable(relayer).call{value: amount}("");
        if (!success) revert GasSponsor__TransferFailed();

        emit GasReleased(relayer, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW ETH
    //////////////////////////////////////////////////////////////*/

    function withdraw(uint256 amount) external onlyOwner {
        if (amount == 0) {
            revert GasSponsor__ZeroAmount();
        }

        if (address(this).balance < amount) {
            revert GasSponsor__InsufficientBalance();
        }

        (bool success,) = payable(owner()).call{value: amount}("");

        if (!success) {
            revert GasSponsor__TransferFailed();
        }

        emit Withdrawal(owner(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function setUserAuthorization(address user, bool authorized) external onlyOwner {
        if (user == address(0)) {
            revert GasSponsor__ZeroAddress();
        }

        authorizedUsers[user] = authorized;

        emit UserAuthorizationUpdated(user, authorized);
    }
}
