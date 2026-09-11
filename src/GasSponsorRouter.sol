// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

interface IGasSponsor {
    function releaseGas(address user, address relayer, uint256 amount) external;
}

interface ISponsorRegistry {
    function isRegistered(address sponsor) external view returns (bool);

    function getSponsor(address sponsor) external view returns (address gasSponsor, address router, bool active);
}

contract GasSponsorRouter is EIP712 {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error GasSponsorRouter__ZeroAddress();
    error GasSponsorRouter__InvalidSignature();
    error GasSponsorRouter__DeadlineExpired();
    error GasSponsorRouter__InvalidNonce();
    error GasSponsorRouter__ExecutionFailed();
    error GasSponsorRouter__InvalidTarget();
    error GasSponsorRouter__ZeroGasPayment();
    error GasSponsorRouter__SponsorNotRegistered();
    error GasSponsorRouter__InvalidSponsorRouter();

    /*//////////////////////////////////////////////////////////////
                                STRUCT
    //////////////////////////////////////////////////////////////*/

    struct MetaTransaction {
        address user;
        address target;
        address sponsor;
        bytes data;
        uint256 nonce;
        uint256 deadline;
        uint256 sponsorAmount;
    }

    /*//////////////////////////////////////////////////////////////
                          EIP-712 TYPEHASH
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant META_TRANSACTION_TYPEHASH = keccak256(
        "MetaTransaction(address user,address target,address sponsor,bytes data,uint256 nonce,uint256 deadline,uint256 sponsorAmount)"
    );

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    ISponsorRegistry public immutable registry;

    mapping(address user => uint256 nonce) public nonces;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MetaTransactionExecuted(
        address indexed user,
        address indexed relayer,
        address indexed target,
        address sponsor,
        uint256 nonce,
        uint256 sponsorAmount
    );

    event NonceUsed(address indexed user, uint256 nonce);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address sponsorRegistry) EIP712("GasSponsorRouter", "1") {
        if (sponsorRegistry == address(0)) {
            revert GasSponsorRouter__ZeroAddress();
        }

        registry = ISponsorRegistry(sponsorRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                              EXECUTE
    //////////////////////////////////////////////////////////////*/

    function execute(MetaTransaction calldata metaTx, bytes calldata signature) external returns (bytes memory result) {
        // Check target
        if (metaTx.target == address(0)) {
            revert GasSponsorRouter__InvalidTarget();
        }

        // Check sponsor
        if (metaTx.sponsor == address(0)) {
            revert GasSponsorRouter__ZeroAddress();
        }

        // Check reimbursement amount
        if (metaTx.sponsorAmount == 0) {
            revert GasSponsorRouter__ZeroGasPayment();
        }

        // Check deadline
        if (block.timestamp > metaTx.deadline) {
            revert GasSponsorRouter__DeadlineExpired();
        }

        // Get user's current nonce
        uint256 currentNonce = nonces[metaTx.user];

        // Check nonce
        if (metaTx.nonce != currentNonce) {
            revert GasSponsorRouter__InvalidNonce();
        }

        // Check sponsor registration
        if (!registry.isRegistered(metaTx.sponsor)) {
            revert GasSponsorRouter__SponsorNotRegistered();
        }

        // Get sponsor information
        (address gasSponsorAddress, address registeredRouter, bool active) = registry.getSponsor(metaTx.sponsor);

        // Make sure sponsor is active
        if (!active) {
            revert GasSponsorRouter__SponsorNotRegistered();
        }

        // Make sure this Router is the registered Router
        if (registeredRouter != address(this)) {
            revert GasSponsorRouter__InvalidSponsorRouter();
        }

        /*//////////////////////////////////////////////////////////////
                          VERIFY SIGNATURE
        //////////////////////////////////////////////////////////////*/

        bytes32 digest = _hashTypedDataV4(_hashMetaTransaction(metaTx));

        address signer = digest.recover(signature);

        if (signer != metaTx.user) {
            revert GasSponsorRouter__InvalidSignature();
        }

        /*//////////////////////////////////////////////////////////////
                              USE NONCE
        //////////////////////////////////////////////////////////////*/

        nonces[metaTx.user] = currentNonce + 1;

        emit NonceUsed(metaTx.user, currentNonce);

        /*//////////////////////////////////////////////////////////////
                         FORWARD TRANSACTION
        //////////////////////////////////////////////////////////////*/

        bytes memory forwardData = abi.encodePacked(metaTx.data, metaTx.user);

        (bool success, bytes memory returnData) = metaTx.target.call(forwardData);

        if (!success) {
            revert GasSponsorRouter__ExecutionFailed();
        }

        /*//////////////////////////////////////////////////////////////
                         REIMBURSE RELAYER
        //////////////////////////////////////////////////////////////*/

        IGasSponsor(gasSponsorAddress).releaseGas(metaTx.user, msg.sender, metaTx.sponsorAmount);

        /*//////////////////////////////////////////////////////////////
                                EVENT
        //////////////////////////////////////////////////////////////*/

        emit MetaTransactionExecuted(
            metaTx.user, msg.sender, metaTx.target, metaTx.sponsor, metaTx.nonce, metaTx.sponsorAmount
        );

        return returnData;
    }

    /*//////////////////////////////////////////////////////////////
                       HASH META TRANSACTION
    //////////////////////////////////////////////////////////////*/

    function _hashMetaTransaction(MetaTransaction calldata metaTx) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                META_TRANSACTION_TYPEHASH,
                metaTx.user,
                metaTx.target,
                metaTx.sponsor,
                keccak256(metaTx.data),
                metaTx.nonce,
                metaTx.deadline,
                metaTx.sponsorAmount
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                         EIP-712 HASH HELPER
    //////////////////////////////////////////////////////////////*/

    function getTypedDataHash(MetaTransaction calldata metaTx) external view returns (bytes32) {
        return _hashTypedDataV4(_hashMetaTransaction(metaTx));
    }

    /*//////////////////////////////////////////////////////////////
                         DOMAIN SEPARATOR
    //////////////////////////////////////////////////////////////*/

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /*//////////////////////////////////////////////////////////////
                              NONCE
    //////////////////////////////////////////////////////////////*/

    function getNonce(address user) external view returns (uint256) {
        return nonces[user];
    }
}
