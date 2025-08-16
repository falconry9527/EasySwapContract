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
     * @param newProtocolShare Default protocol fee : 手续费
     * @param newVault easy swap vault address : 存储层合约地址
     * EasySwapVault ： 是数据存储层，逻辑和数据存储隔离开：数据存储不能升级，因为每次升级就相当于一个新的合约，存储的数据就丢失了
     *  EIP712Name  : 合约名称
     *  EIP712Version  ：合约版本
     * 
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

        OrderStorage.__OrderStorage_init();
        ProtocolManager.__ProtocolManager_init(newProtocolShare);
        OrderValidator.__OrderValidator_init(EIP712Name, EIP712Version);

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
        uint128 ethAmount; // total eth amount
        for (uint256 i = 0; i < orderLength; ++i) {
            uint128 buyPrice; // the price of bid order
            if (newOrders[i].side == LibOrder.Side.Bid) {
                // amount : 一般都是1  
                buyPrice =Price.unwrap(newOrders[i].price) * newOrders[i].nft.amount;
            }
            OrderKey newOrderKey = _makeOrderTry(newOrders[i], buyPrice);
            newOrderKeys[i] = newOrderKey;
            if ( OrderKey.unwrap(newOrderKey) != OrderKey.unwrap(LibOrder.ORDERKEY_SENTINEL)) {
                // newOrderKey != 1 
                // byte32 转数字 
                ethAmount += buyPrice;
            }
        }
        if (msg.value > ethAmount) {
            // return the remaining eth，if the eth is not enough, the transaction will be reverted
            // msg.valu :  是 用户传过来的 金额 
            // ETHAmount : 是 算出的价格
            _msgSender().safeTransferETH(msg.value - ethAmount);
        }
        // 如果资金不够怎么搞 ？？？？？
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
                // 卖出 NFT ,先把 NFT 转进来
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
                // 买入 NFT ，先把钱转进来
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

    /**
     * 取消订单
     * @dev Cancels multiple orders by their order keys.
     * @param orderKeys The array of order keys to cancel.
     */
    function cancelOrders(
        OrderKey[] calldata orderKeys
    )
        external
        override
        whenNotPaused
        nonReentrant
        returns (bool[] memory successes)
    {
        successes = new bool[](orderKeys.length);
        for (uint256 i = 0; i < orderKeys.length; ++i) {
            bool success = _cancelOrderTry(orderKeys[i]);
            successes[i] = success;
        }
    }

    function _cancelOrderTry(
        OrderKey orderKey
    ) internal returns (bool success) {
        LibOrder.Order memory order = orders[orderKey].order;

        if (
            order.maker == _msgSender() &&
            filledAmount[orderKey] < order.nft.amount // only unfilled order can be canceled
        ) {
            OrderKey orderHash = LibOrder.hash(order);
            _removeOrder(order);
            // withdraw asset from vault
            if (order.side == LibOrder.Side.List) {
                // 取消卖出： 退回NFT
                IEasySwapVault(_vault).withdrawNFT(
                    orderHash,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId
                );
            } else if (order.side == LibOrder.Side.Bid) {
                // 取消买入： 退回ETH
                uint256 availNFTAmount = order.nft.amount -
                    filledAmount[orderKey];
                IEasySwapVault(_vault).withdrawETH(
                    orderHash,
                    Price.unwrap(order.price) * availNFTAmount, // the withdraw amount of eth
                    order.maker
                );
            }
            _cancelOrder(orderKey);
            success = true;
            emit LogCancel(orderKey, order.maker);
        } else {
            emit LogSkipOrder(orderKey, order.salt);
        }
    }

    /**
     * @notice Cancels multiple orders by their order keys.
     * @dev newOrder's saleKind, side, maker, and nft must match the corresponding order of oldOrderKey, otherwise it will be skipped; only the price can be modified.
     * @dev newOrder's expiry and salt can be regenerated.
     * @param editDetails The edit details of oldOrderKey and new order info
     * @return newOrderKeys The unique id of the order is returned in order, if the id is empty, the corresponding order was not edit correctly.
     */
    function editOrders(
        LibOrder.EditDetail[] calldata editDetails
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (OrderKey[] memory newOrderKeys)
    {
        newOrderKeys = new OrderKey[](editDetails.length);

        uint256 bidETHAmount;
        for (uint256 i = 0; i < editDetails.length; ++i) {
            (OrderKey newOrderKey, uint256 bidPrice) = _editOrderTry(
                editDetails[i].oldOrderKey,
                editDetails[i].newOrder
            );
            bidETHAmount += bidPrice;
            newOrderKeys[i] = newOrderKey;
        }
        if (msg.value > bidETHAmount) {
            // 如果存入的eth过多，退还用户的 eth
            _msgSender().safeTransferETH(msg.value - bidETHAmount);
        }
    }

    function _editOrderTry(
        OrderKey oldOrderKey,
        LibOrder.Order calldata newOrder
    ) internal returns (OrderKey newOrderKey, uint256 deltaBidPrice) {
        LibOrder.Order memory oldOrder = orders[oldOrderKey].order;

        // check order, only the price and amount can be modified
        if (
            (oldOrder.saleKind != newOrder.saleKind) ||
            (oldOrder.side != newOrder.side) ||
            (oldOrder.maker != newOrder.maker) ||
            (oldOrder.nft.collection != newOrder.nft.collection) ||
            (oldOrder.nft.tokenId != newOrder.nft.tokenId) ||
            filledAmount[oldOrderKey] >= oldOrder.nft.amount // order cannot be canceled or filled
        ) {
            emit LogSkipOrder(oldOrderKey, oldOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }

        // check new order is valid
        if (
            newOrder.maker != _msgSender() ||
            newOrder.salt == 0 ||
            (newOrder.expiry < block.timestamp && newOrder.expiry != 0) ||
            filledAmount[LibOrder.hash(newOrder)] != 0 // order cannot be canceled or filled
        ) {
            emit LogSkipOrder(oldOrderKey, newOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }

        // cancel old order
        uint256 oldFilledAmount = filledAmount[oldOrderKey];
        _removeOrder(oldOrder); // remove order from order storage
        _cancelOrder(oldOrderKey); // cancel order from order book
        emit LogCancel(oldOrderKey, oldOrder.maker);

        newOrderKey = _addOrder(newOrder); // add new order to order storage

        // make new order
        if (oldOrder.side == LibOrder.Side.List) {
            IEasySwapVault(_vault).editNFT(oldOrderKey, newOrderKey);
        } else if (oldOrder.side == LibOrder.Side.Bid) {
            uint256 oldRemainingPrice = Price.unwrap(oldOrder.price) *
                (oldOrder.nft.amount - oldFilledAmount);
            uint256 newRemainingPrice = Price.unwrap(newOrder.price) *
                newOrder.nft.amount;
            if (newRemainingPrice > oldRemainingPrice) {
                deltaBidPrice = newRemainingPrice - oldRemainingPrice;
                IEasySwapVault(_vault).editETH{value: uint256(deltaBidPrice)}(
                    oldOrderKey,
                    newOrderKey,
                    oldRemainingPrice,
                    newRemainingPrice,
                    oldOrder.maker
                );
            } else {
                IEasySwapVault(_vault).editETH(
                    oldOrderKey,
                    newOrderKey,
                    oldRemainingPrice,
                    newRemainingPrice,
                    oldOrder.maker
                );
            }
        }

        emit LogMake(
            newOrderKey,
            newOrder.side,
            newOrder.saleKind,
            newOrder.maker,
            newOrder.nft,
            newOrder.price,
            newOrder.expiry,
            newOrder.salt
        );
    }

   //============== PausableUpgradeable ==============
    function unpause() external onlyOwner {
        _unpause();
    }

    function pause() external onlyOwner {
        _pause();
    }
   //============== payable ==============
    function withdrawETH(
        address recipient,
        uint256 amount
    ) external nonReentrant onlyOwner {
        recipient.safeTransferETH(amount);
        emit LogWithdrawETH(recipient, amount);
    }
    receive() external payable {}


}
