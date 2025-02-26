// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title NFTRenderer
 * @notice On-chain SVG generation for .pow domain NFTs
 */
library NFTRenderer {
    using Strings for uint256;

    /**
     * @notice Generate SVG for a domain
     * @param name The domain name (without .pow suffix)
     */
    function generateSVG(
        string memory name
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<svg width="1000" height="1000" viewBox="0 0 1000 1000" xmlns="http://www.w3.org/2000/svg">',
                    "<defs><style>.f{font-family:Montserrat,-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif}</style></defs>",
                    '<rect width="1000" height="1000" fill="#0a0a0a"/>',
                    '<text x="960" y="55" text-anchor="end" class="f" font-weight="600" font-size="18" letter-spacing="2" fill="#555">POW LABS</text>',
                    '<text x="40" y="960" class="f">',
                    '<tspan fill="#fff" font-weight="800" font-size="72" letter-spacing="-1">',
                    name,
                    "</tspan>",
                    '<tspan fill="#555" font-weight="600" font-size="36">.pow</tspan>',
                    "</text></svg>"
                )
            );
    }

    /**
     * @notice Generate full token URI with metadata
     * @param tokenId The token ID
     * @param name The domain name
     * @param owner Current owner address
     * @param expires Expiration timestamp
     */
    function tokenURI(
        uint256 tokenId,
        string memory name,
        address owner,
        uint256 expires
    ) internal pure returns (string memory) {
        string memory svg = generateSVG(name);
        string memory svgBase64 = Base64.encode(bytes(svg));

        string memory json = string(
            abi.encodePacked(
                '{"name":"',
                name,
                '.pow",',
                '"description":"PoW Name Service domain - scarcity through computation, not capital.",',
                '"image":"data:image/svg+xml;base64,',
                svgBase64,
                '",',
                '"attributes":[',
                '{"trait_type":"Domain","value":"',
                name,
                '.pow"},',
                '{"trait_type":"Token ID","value":"',
                tokenId.toString(),
                '"},',
                '{"trait_type":"Owner","value":"',
                addressToString(owner),
                '"},',
                '{"trait_type":"Expires","display_type":"date","value":',
                expires.toString(),
                "}",
                "]}"
            )
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(bytes(json))
                )
            );
    }

    function addressToString(
        address addr
    ) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}
