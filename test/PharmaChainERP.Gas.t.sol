// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PharmaChainERPBase.t.sol";

contract PharmaChainERPGasTest is PharmaChainERPBase {
    function testGasCriticalPathWithinBudget() public {
        uint256 mintGas = _callAndMeasure(
            logistics,
            abi.encodeCall(PharmaChainERP.mintBatch, ("GTIN-GAS", 1000, 30))
        );

        uint256 releaseGas = _callAndMeasure(
            quality,
            abi.encodeCall(PharmaChainERP.releaseBatch, (1, keccak256("coa-gas"), "ipfs://coa/gas"))
        );

        uint256 shipGas = _callAndMeasure(
            logistics,
            abi.encodeCall(PharmaChainERP.shipBatch, (1, carrier, destination, 1000))
        );

        uint256 receiveGas = _callAndMeasure(
            destination,
            abi.encodeCall(PharmaChainERP.receiveShipment, (1, 990, 10, "quebra"))
        );

        assertLt(mintGas, 500_000);
        assertLt(releaseGas, 400_000);
        assertLt(shipGas, 500_000);
        assertLt(receiveGas, 550_000);
    }
}
