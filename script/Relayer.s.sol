// SPDX-License-Identifier: LicenseRef-Gas-Sponsorship-Commercial-License
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {GasSponsorRouter} from "../src/GasSponsorRouter.sol";

contract Relayer is Script {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 constant SPONSOR_AMOUNT = 0.01 ether;

    /*//////////////////////////////////////////////////////////////
                                RUN
    //////////////////////////////////////////////////////////////*/

    function run() external {
        /*
         * ---------------------------------------------------------
         * RELAYER PRIVATE KEY
         * ---------------------------------------------------------
         *
         * This is the account that actually submits the
         * transaction to the blockchain.
         */

        uint256 relayerPrivateKey = vm.envUint("RELAYER_PRIVATE_KEY");

        /*
         * ---------------------------------------------------------
         * USER PRIVATE KEY
         * ---------------------------------------------------------
         *
         * In a real production relayer service, the user would
         * sign off-chain and send the signature to the relayer.
         *
         * Here we use vm.sign() so we can demonstrate the
         * complete flow with Foundry.
         */

        uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");

        /*
         * ---------------------------------------------------------
         * CONTRACT ADDRESSES
         * ---------------------------------------------------------
         */

        address routerAddress = vm.envAddress("ROUTER_ADDRESS");

        address targetAddress = vm.envAddress("TARGET_ADDRESS");

        address sponsorAddress = vm.envAddress("SPONSOR_ADDRESS");

        /*
         * Create Router interface.
         */

        GasSponsorRouter router = GasSponsorRouter(routerAddress);

        /*
         * Calculate user's address.
         */

        address user = vm.addr(userPrivateKey);

        /*
         * ---------------------------------------------------------
         * CREATE TARGET CALL
         * ---------------------------------------------------------
         *
         * This example assumes the target has:
         *
         * setValue(uint256)
         */

        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 123);

        /*
         * ---------------------------------------------------------
         * GET USER NONCE
         * ---------------------------------------------------------
         */

        uint256 nonce = router.getNonce(user);

        /*
         * ---------------------------------------------------------
         * CREATE META TRANSACTION
         * ---------------------------------------------------------
         */

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: targetAddress,
            sponsor: sponsorAddress,
            data: data,
            nonce: nonce,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        /*
         * ---------------------------------------------------------
         * CREATE EIP-712 DIGEST
         * ---------------------------------------------------------
         */

        bytes32 digest = router.getTypedDataHash(metaTx);

        /*
         * ---------------------------------------------------------
         * USER SIGNS
         * ---------------------------------------------------------
         *
         * This simulates the user signing off-chain.
         */

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        console2.log("User:", user);

        console2.log("Relayer:", vm.addr(relayerPrivateKey));

        console2.log("Router:", routerAddress);

        console2.log("Target:", targetAddress);

        console2.log("Sponsor:", sponsorAddress);

        console2.log("Nonce:", nonce);

        /*
         * ---------------------------------------------------------
         * RELAYER SUBMITS TRANSACTION
         * ---------------------------------------------------------
         */

        vm.startBroadcast(relayerPrivateKey);

        router.execute(metaTx, signature);

        vm.stopBroadcast();

        console2.log("Meta-transaction executed successfully.");
    }
}
