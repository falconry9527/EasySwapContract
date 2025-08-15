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

import {OrderStorage} from "./OrderStorage.sol";
import {OrderValidator} from "./OrderValidator.sol";
import {ProtocolManager} from "./ProtocolManager.sol";

// ContextUpgradeable ： 级合约中提供安全的上下文信息访问 __Context_init
// 代理模式下直接使用 msg.sender 会导致获取到的是代理合约地址而非实际调用者
// 获取正确的调用者地址: address sender = _msgSender();

// OwnableUpgradeable ： 权限管理   __Ownable_init -> onlyOwner
// ReentrancyGuardUpgradeable ：防止提款重入攻击:  __ReentrancyGuard_init -> nonReentrant

// PausableUpgradeable :  主要为合约添加暂停类功能：
// __Pausable_init();  pause() ；unpause()；
// whenNotPaused ：修饰器：用于修饰只能在合约未暂停时执行的函数
// whenPaused ：修饰器：用于修饰只能在合约暂停时执行的函数
contract EasySwapOrderBook is
    IEasySwapOrderBook,
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OrderStorage,
    ProtocolManager,
    OrderValidator
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

        __OrderStorage_init();
        __ProtocolManager_init(newProtocolShare);
        __OrderValidator_init(EIP712Name, EIP712Version);

        setVault(newVault);
    }

    modifier onlyDelegateCall() {
        _checkDelegateCall();
        _;
    }

    function _checkDelegateCall() private view {
        require(address(this) != self);
    }

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    address private immutable self = address(this);

    address private _vault;

    function setVault(address newVault) public onlyOwner {
        require(newVault != address(0), "HD: zero address");
        _vault = newVault;
    }

    /**
     *
     *  下单： 卖出NFT
     * @notice Create multiple orders and transfer related assets.
     * @dev If Side=List, you need to authorize the EasySwapOrderBook contract first (creating a List order will transfer the NFT to the order pool).
     * @dev If Side=Bid, you need to pass {value}: the price of the bid (similarly, creating a Bid order will transfer ETH to the order pool).
     * @dev order.maker needs to be msg.sender.
     * @dev order.price cannot be 0.
     * @dev order.expiry needs to be greater than block.timestamp, or 0.
     * @dev order.salt cannot be 0.
     * @param newOrders Multiple order structure data.
     * @return newOrderKeys The unique id of the order is returned in order, if the id is empty, the corresponding order was not created correctly.
     *
     *   LibOrder.Order : 结构体
     *   Side side;
     *   SaleKind saleKind;
     *   address maker;
     *   Asset nft;
     *   Price price; // unit price of nft
     *   uint64 expiry;
     *   uint64 salt;
     *
     */
    function makeOrders(
        LibOrder.Order[] calldata newOrders
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (OrderKey[] memory newOrderKeys)
    {
        uint256 orderLength = newOrders.length;
        newOrderKeys = new OrderKey[](orderLength);
        uint128 ETHAmount; // total eth amount
        for (uint256 i = 0; i < orderLength; ++i) {
            uint128 buyPrice; // the price of bid order
            // ？？？ nft 为什么会有 amount ？不是 1个tokenID 对应1个 nft 吗
            if (newOrders[i].side == LibOrder.Side.Bid) {
                buyPrice =
                    Price.unwrap(newOrders[i].price) *
                    newOrders[i].nft.amount;
            }
            OrderKey newOrderKey = _makeOrderTry(newOrders[i], buyPrice);
            newOrderKeys[i] = newOrderKey;
            if (
                // if the order is not created successfully, the eth will be returned
                OrderKey.unwrap(newOrderKey) !=
                OrderKey.unwrap(LibOrder.ORDERKEY_SENTINEL)
            ) {
                ETHAmount += buyPrice;
            }
        }
        if (msg.value > ETHAmount) {
            // return the remaining eth，if the eth is not enough, the transaction will be reverted
            _msgSender().safeTransferETH(msg.value - ETHAmount);
        }
    }

    function _makeOrderTry(
        LibOrder.Order calldata order,
        uint128 ETHAmount
    ) internal returns (OrderKey newOrderKey) {
        // salt 常用于 CREATE2 操作码，用于预先计算智能合约或 NFT 合约的部署地址，而无需实际部署合约
        if (
            order.maker == _msgSender() && // only maker can make order
            Price.unwrap(order.price) != 0 && // price cannot be zero
            order.salt != 0 && // salt cannot be zero
            (order.expiry > block.timestamp || order.expiry == 0) && // expiry must be greater than current block timestamp or no expiry
            filledAmount[LibOrder.hash(order)] == 0 // order cannot be canceled or filled
        ) {
            newOrderKey = LibOrder.hash(order);

            // deposit asset to vault
            if (order.side == LibOrder.Side.List) {
                if (order.nft.amount != 1) {
                    // limit list order amount to 1
                    return LibOrder.ORDERKEY_SENTINEL;
                }
                IEasySwapVault(_vault).depositNFT(
                    newOrderKey,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId
                );
            } else if (order.side == LibOrder.Side.Bid) {
                if (order.nft.amount == 0) {
                    return LibOrder.ORDERKEY_SENTINEL;
                }
                IEasySwapVault(_vault).depositETH{value: uint256(ETHAmount)}(
                    newOrderKey,
                    ETHAmount
                );
            }

            _addOrder(order);

            emit LogMake(
                newOrderKey,
                order.side,
                order.saleKind,
                order.maker,
                order.nft,
                order.price,
                order.expiry,
                order.salt
            );
        } else {
            emit LogSkipOrder(LibOrder.hash(order), order.salt);
        }
    }
}
