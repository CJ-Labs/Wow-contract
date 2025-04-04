// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IWowFactory} from "./interfaces/IWowFactory.sol";
import {Coin} from "./Coin.sol";

/* 
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
 
    WOW         WOW         WOW    
*/
contract WowFactoryImpl is IWowFactory, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    address public immutable coinImpl;

    constructor(address _coinImpl) initializer {
        coinImpl = _coinImpl;
    }

    /// @notice Create a coin
    /// @param _creator The creator address
    /// @param _platformReferrer The platform referrer address
    /// @param _tokenURI The ERC20z token URI
    /// @param _name The coin name
    /// @param _symbol The coin symbol
    function deploy(
        address _creator,
        address _platformReferrer,
        string memory _tokenURI,
        string memory _name,
        string memory _symbol
    ) external payable nonReentrant returns (address) {
        bytes32 salt = _generateSalt(_creator, _tokenURI);

        Coin coin = Coin(payable(Clones.cloneDeterministic(coinImpl, salt)));

        coin.initialize{value: msg.value}(_creator, _platformReferrer, _tokenURI, _name, _symbol);

        emit WowTokenCreated(
            address(this),
            _creator,
            _platformReferrer,
            coin.protocolFeeRecipient(),
            address(0),
            _tokenURI,
            _name,
            _symbol,
            address(coin),
            coin.poolAddress()
        );

        emit CoinCreated(
            msg.sender,
            _creator,
            _creator,
            coin.platformReferrer(),
            address(0),
            _tokenURI,
            _name,
            _symbol,
            address(coin),
            coin.poolAddress()
        );

        return address(coin);
    }

    /// @dev Generates a unique salt for deterministic deployment
    function _generateSalt(address _creator, string memory _tokenURI) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                msg.sender,
                _creator,
                keccak256(abi.encodePacked(_tokenURI)),
                block.coinbase,
                block.number,
                block.prevrandao,
                block.timestamp,
                tx.gasprice,
                tx.origin
            )
        );
    }

    /// @notice Initializes the factory proxy contract
    /// @param _owner Address of the contract owner
    /// @dev Can only be called once due to initializer modifier
    function initialize(address _owner) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
    }

    /// @notice The implementation address of the factory contract
    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @dev Authorizes an upgrade to a new implementation
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {}
}
