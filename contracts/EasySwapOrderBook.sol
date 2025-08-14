import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {LibTransferSafeUpgradeable, IERC721} from "./libraries/LibTransferSafeUpgradeable.sol";
import {Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";
import {LibPayInfo} from "./libraries/LibPayInfo.sol";

import {IEasySwapOrderBook} from "./interface/IEasySwapOrderBook.sol";
import {IEasySwapVault} from "./interface/IEasySwapVault.sol";

// import {OrderStorage} from "./OrderStorage.sol";
// import {OrderValidator} from "./OrderValidator.sol";
// import {ProtocolManager} from "./ProtocolManager.sol";

//  IEasySwapOrderBook,
contract EasySwapOrderBook is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
    // OrderStorage,
    // ProtocolManager,
    // OrderValidator
{
    using LibTransferSafeUpgradeable for address;
    using LibTransferSafeUpgradeable for IERC721;
    event LogMake(
        OrderKey orderKey,
        LibOrder.Side indexed side,
        LibOrder.SaleKind indexed saleKind,
        address indexed maker,
        LibOrder.Asset nft,
        Price price,
        uint64 expiry,
        uint64 salt
    );

    event LogCancel(OrderKey indexed orderKey, address indexed maker);

    event LogMatch(
        OrderKey indexed makeOrderKey,
        OrderKey indexed takeOrderKey,
        LibOrder.Order makeOrder,
        LibOrder.Order takeOrder,
        uint128 fillPrice
    );

    event LogWithdrawETH(address recipient, uint256 amount);
    event BatchMatchInnerError(uint256 offset, bytes msg);
    event LogSkipOrder(OrderKey orderKey, uint64 salt);

    /**
     * @notice Initialize contracts.
     * @param newProtocolShare Default protocol fee.
     * @param newVault easy swap vault address.
     */
    function initialize(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) public initializer {
        __EasySwapOrderBook_init(
            newProtocolShare,
            newVault,
            EIP712Name,
            EIP712Version
        );
    }

    function __EasySwapOrderBook_init(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing {
        __EasySwapOrderBook_init_unchained(
            newProtocolShare,
            newVault,
            EIP712Name,
            EIP712Version
        );
    }

    function __EasySwapOrderBook_init_unchained(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing {
        __Context_init();
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
        __Pausable_init();

        // __OrderStorage_init();
        // __ProtocolManager_init(newProtocolShare);
        // __OrderValidator_init(EIP712Name, EIP712Version);

        // setVault(newVault);
    }
}
