// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {RedBlackTreeLibrary, Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";
import {IOrderStorage} from "./interface/IOrderStorage.sol";

error CannotInsertDuplicateOrder(OrderKey orderKey);

// 数据存储层一般不支持升级
contract OrderStorage is Initializable,IOrderStorage {
    address public owner;

    // 构造函数：部署时设置所有者
    constructor() {
        owner = msg.sender;
    }

    // 自定义修饰器：仅允许所有者调用
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _; // 继续执行函数逻辑
    }

    address public orderBook;
    modifier onlyEasySwapOrderBook() {
        require(msg.sender == orderBook, "HV: only EasySwap OrderBook");
        _;
    }
    
    function setOrderBook(address newOrderBook) public onlyOwner {
        require(newOrderBook != address(0), "HV: zero address");
        orderBook = newOrderBook;
    }

    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;

    /// @dev all order keys are wrapped in a sentinel value to avoid collisions
    // OrderKey->LibOrder.DBOrder(包含下一个订单的  OrderKey next)
    // orders : 包含所有价格都订单，每个价格是一条链 
    mapping(OrderKey => LibOrder.DBOrder) public orders;

    /// @dev price tree for each collection and side, sorted by price
    // nft address->（买入/卖出 -> 价格树 Tree）
    // 价格树：只保留是否有有某个价格，没有保存具体订单
    mapping(address => mapping(LibOrder.Side => RedBlackTreeLibrary.Tree)) public priceTrees;

    /// @dev order queue for each collection, side and expecially price, sorted by orderKey
    // nft address->（买入/卖出 -> （价格->订单队列) ） 
    // 订单队列 只保留 head 和 tail 两个订单 ， 全量订单在 orders 保存
    mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue))) public orderQueues;

    function __OrderStorage_init() internal onlyInitializing {}

    function __OrderStorage_init_unchained() internal onlyInitializing {}

    function onePlus(uint256 x) internal pure returns (uint256) {
        unchecked {
            return 1 + x;
        }
    }

    function getOrder(
       OrderKey orderKey
    ) external view onlyEasySwapOrderBook returns (LibOrder.DBOrder memory orderDb) {
      return orders[orderKey] ;
    }

    function addOrder(
        LibOrder.Order memory order
    ) external  onlyEasySwapOrderBook returns (OrderKey orderKey) {
        // 获取订单的hash值
        orderKey = LibOrder.hash(order);
        //  判断订单是否已经存在
        if (orders[orderKey].order.maker != address(0)) {
            revert CannotInsertDuplicateOrder(orderKey);
        }

        // insert price to price tree if not exists
        RedBlackTreeLibrary.Tree storage priceTree = priceTrees[order.nft.collection][order.side];
        if (!priceTree.exists(order.price)) {
            priceTree.insert(order.price);
        }

        // insert order to order queue
        // OrderKey head;
        // OrderKey tail;
        LibOrder.OrderQueue storage orderQueue = orderQueues[order.nft.collection][order.side][order.price];

        if (LibOrder.isSentinel(orderQueue.head)) { // 队列是否初始化
            // 创建新的队列 : 开始和结尾订单都 0 orderkey
            orderQueues[order.nft.collection][order.side][ order.price] = LibOrder.OrderQueue(
                LibOrder.ORDERKEY_SENTINEL,
                LibOrder.ORDERKEY_SENTINEL
            );
            orderQueue = orderQueues[order.nft.collection][order.side][order.price];
        }
        if (LibOrder.isSentinel(orderQueue.tail)) { // 队列是否为空
            // 更新队列
            orderQueue.head = orderKey;
            orderQueue.tail = orderKey;
            // 更新orders
            orders[orderKey] = LibOrder.DBOrder( // 创建新的订单，插入队列， 下一个订单为sentinel
                order,
                LibOrder.ORDERKEY_SENTINEL
            );
        } else { // 队列不为空
            // 更新 orders
            // 上一个 order（orderQueue.tail） 的 next= orderKey
            orders[orderQueue.tail].next = orderKey; // 将新订单插入队列尾部
            // 本订单的 previous = 上个 order （orderQueue.tail）
            orders[orderKey] = LibOrder.DBOrder(
                order,
                LibOrder.ORDERKEY_SENTINEL
            );
            // 更新队列 
            orderQueue.tail = orderKey;
        }
    }

    function removeOrder(
        LibOrder.Order memory order
    ) external  onlyEasySwapOrderBook returns (OrderKey orderKey) {
        LibOrder.OrderQueue storage orderQueue = orderQueues[order.nft.collection][order.side][order.price];
        orderKey = orderQueue.head;
        OrderKey prevOrderKey  = LibOrder.ORDERKEY_SENTINEL;
        bool found;
        while (LibOrder.isNotSentinel(orderKey) && !found) {
            LibOrder.DBOrder memory dbOrder = orders[orderKey];
            // 对 orders 进行循环遍历
            if (
                (dbOrder.order.maker == order.maker) &&
                (dbOrder.order.saleKind == order.saleKind) &&
                (dbOrder.order.expiry == order.expiry) &&
                (dbOrder.order.salt == order.salt) &&
                (dbOrder.order.nft.tokenId == order.nft.tokenId) &&
                (dbOrder.order.nft.amount == order.nft.amount)
            ) {
                OrderKey temp = orderKey;
                // emit OrderRemoved(order.nft.collection, orderKey, order.maker, order.side, order.price, order.nft, block.timestamp);
                // ====== 更新 orderQueue 
                if (OrderKey.unwrap(orderQueue.head) ==OrderKey.unwrap(orderKey)) {
                    orderQueue.head = dbOrder.next;
                } else {
                    // orders 开头不要修改，开头之后需要修改
                    orders[prevOrderKey].next = dbOrder.next;
                }
                if (OrderKey.unwrap(orderQueue.tail) ==OrderKey.unwrap(orderKey)) {
                    orderQueue.tail = prevOrderKey;
                }
                // 移动到下一个订单
                prevOrderKey = orderKey;
                orderKey = dbOrder.next;
                delete orders[temp];
                found = true;
            } else {
                prevOrderKey = orderKey;
                orderKey = dbOrder.next;
            }
        }

        if (found) {
            if (LibOrder.isSentinel(orderQueue.head)) {
                // 如果找到订单，而且该价格已经没有订单了，就要删除 orderQueues  ，移除 priceTree
                delete orderQueues[order.nft.collection][order.side][order.price];
                RedBlackTreeLibrary.Tree storage priceTree = priceTrees[order.nft.collection][order.side];
                if (priceTree.exists(order.price)) {
                    priceTree.remove(order.price);
                }
            }
        } else {
            revert("Cannot remove missing order");
        }
    }

}
