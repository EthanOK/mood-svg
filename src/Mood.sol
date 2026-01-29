// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Mood is Ownable, ERC721 {
    using Strings for uint256;

    enum MoodType {
        NULL,
        HAPPY,
        SAD
    }

    struct MoodData {
        // 1 bytes
        MoodType moodType;
        // 31 bytes
        uint248 traitValue;
    }

    string public constant HAPPY_URI =
        "data:image/svg+xml;base64,PHN2ZyB2aWV3Qm94PSIwIDAgMjAwIDIwMCIgd2lkdGg9IjQwMCIgIGhlaWdodD0iNDAwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgogIDxjaXJjbGUgY3g9IjEwMCIgY3k9IjEwMCIgZmlsbD0ieWVsbG93IiByPSI3OCIgc3Ryb2tlPSJibGFjayIgc3Ryb2tlLXdpZHRoPSIzIi8+CiAgPGcgY2xhc3M9ImV5ZXMiPgogICAgPGNpcmNsZSBjeD0iNjEiIGN5PSI4MiIgcj0iMTIiLz4KICAgIDxjaXJjbGUgY3g9IjEyNyIgY3k9IjgyIiByPSIxMiIvPgogIDwvZz4KICA8cGF0aCBkPSJtMTM2LjgxIDExNi41M2MuNjkgMjYuMTctNjQuMTEgNDItODEuNTItLjczIiBzdHlsZT0iZmlsbDpub25lOyBzdHJva2U6IGJsYWNrOyBzdHJva2Utd2lkdGg6IDM7Ii8+Cjwvc3ZnPg==";

    string public constant SAD_URI =
        "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAyNHB4IiBoZWlnaHQ9IjEwMjRweCIgdmlld0JveD0iMCAwIDEwMjQgMTAyNCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8cGF0aCBmaWxsPSIjMzMzIiBkPSJNNTEyIDY0QzI2NC42IDY0IDY0IDI2NC42IDY0IDUxMnMyMDAuNiA0NDggNDQ4IDQ0OCA0NDgtMjAwLjYgNDQ4LTQ0OFM3NTkuNCA2NCA1MTIgNjR6bTAgODIwYy0yMDUuNCAwLTM3Mi0xNjYuNi0zNzItMzcyczE2Ni42LTM3MiAzNzItMzcyIDM3MiAxNjYuNiAzNzIgMzcyLTE2Ni42IDM3Mi0zNzIgMzcyeiIvPgogIDxwYXRoIGZpbGw9IiNFNkU2RTYiIGQ9Ik01MTIgMTQwYy0yMDUuNCAwLTM3MiAxNjYuNi0zNzIgMzcyczE2Ni42IDM3MiAzNzIgMzcyIDM3Mi0xNjYuNiAzNzItMzcyLTE2Ni42LTM3Mi0zNzItMzcyek0yODggNDIxYTQ4LjAxIDQ4LjAxIDAgMCAxIDk2IDAgNDguMDEgNDguMDEgMCAwIDEtOTYgMHptMzc2IDI3MmgtNDguMWMtNC4yIDAtNy44LTMuMi04LjEtNy40QzYwNCA2MzYuMSA1NjIuNSA1OTcgNTEyIDU5N3MtOTIuMSAzOS4xLTk1LjggODguNmMtLjMgNC4yLTMuOSA3LjQtOC4xIDcuNEgzNjBhOCA4IDAgMCAxLTgtOC40YzQuNC04NC4zIDc0LjUtMTUxLjYgMTYwLTE1MS42czE1NS42IDY3LjMgMTYwIDE1MS42YTggOCAwIDAgMS04IDguNHptMjQtMjI0YTQ4LjAxIDQ4LjAxIDAgMCAxIDAtOTYgNDguMDEgNDguMDEgMCAwIDEgMCA5NnoiLz4KICA8cGF0aCBmaWxsPSIjMzMzIiBkPSJNMjg4IDQyMWE0OCA0OCAwIDEgMCA5NiAwIDQ4IDQ4IDAgMSAwLTk2IDB6bTIyNCAxMTJjLTg1LjUgMC0xNTUuNiA2Ny4zLTE2MCAxNTEuNmE4IDggMCAwIDAgOCA4LjRoNDguMWM0LjIgMCA3LjgtMy4yIDguMS03LjQgMy43LTQ5LjUgNDUuMy04OC42IDk1LjgtODguNnM5MiAzOS4xIDk1LjggODguNmMuMyA0LjIgMy45IDcuNCA4LjEgNy40SDY2NGE4IDggMCAwIDAgOC04LjRDNjY3LjYgNjAwLjMgNTk3LjUgNTMzIDUxMiA1MzN6bTEyOC0xMTJhNDggNDggMCAxIDAgOTYgMCA0OCA0OCAwIDEgMC05NiAweiIvPgo8L3N2Zz4=";

    uint256 private _tokenIdCounter = _startTokenId();

    mapping(uint256 => MoodData) private moodData;

    constructor() ERC721("Bored Ape Yacht Club", "BAYC") Ownable(_msgSender()) {
        _batchMint(_msgSender(), 100);
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter > 0 ? _tokenIdCounter - _startTokenId() : 0;
    }

    function _startTokenId() internal pure virtual returns (uint256) {
        return 1;
    }

    function batchMint(address to, uint256 amount) public onlyOwner {
        _batchMint(to, amount);
    }

    function _batchMint(address to, uint256 amount) private {
        require(amount <= 100, "MINT_AMOUNT_EXCEEDED_100");

        uint256 __tokenIdCounter = _tokenIdCounter;

        for (uint256 i; i < amount; i++) {
            uint256 tokenId = __tokenIdCounter;
            _mint(to, tokenId);

            uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, tokenId)));

            moodData[tokenId].moodType = random % 2 == 0 ? MoodType.HAPPY : MoodType.SAD;

            moodData[tokenId].traitValue = uint248(random % 100) + 1;

            __tokenIdCounter++;
        }
        _tokenIdCounter = __tokenIdCounter;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory baseURI = _baseURI();
        string memory imageURI;
        MoodType mood = moodData[tokenId].moodType;

        if (mood == MoodType.HAPPY) {
            imageURI = HAPPY_URI;
        } else if (mood == MoodType.SAD) {
            imageURI = SAD_URI;
        }

        return string(
            abi.encodePacked(
                baseURI,
                Base64.encode(
                    abi.encodePacked(
                        '{"name": "',
                        string(abi.encodePacked(symbol(), " #", tokenId.toString())),
                        '", "description": "A SVG NFT!", "attributes": [{"trait_type": "Mood", "value": ',
                        uint256(moodData[tokenId].traitValue).toString(),
                        '}], "image": "',
                        imageURI,
                        '"}'
                    )
                )
            )
        );
    }

    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }
}
