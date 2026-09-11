// SPDX-License-Identifier: LicenseRef-Gas-Sponsorship-Commercial-License
pragma solidity ^0.8.35;

import {GasSponsorRouter} from "./GasSponsorRouter.sol";

contract ReentrantTarget {
    GasSponsorRouter public router;

    constructor(address _router) {
        router = GasSponsorRouter(_router);
    }

    function attack(GasSponsorRouter.MetaTransaction calldata metaTx, bytes calldata signature) external {
        // Try to execute the same signed transaction again
        router.execute(metaTx, signature);
    }
}
