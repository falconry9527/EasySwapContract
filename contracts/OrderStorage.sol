// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {RedBlackTreeLibrary, Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";

error CannotInsertDuplicateOrder(OrderKey orderKey);

// 数据存储层一般不支持升级
contract OrderStorage is Initializable {
    // 把 RedBlackTreeLibrary 的方法赋予 Tree 结构体使用
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;

    /// @dev price tree for each collection and side, sorted by price
    // nft collection address->（买入/卖出 -> 价格树 Tree）
    // 价格树：只保留是否有有某个价格，没有保存具体订单
    mapping(address => mapping(LibOrder.Side => RedBlackTreeLibrary.Tree)) public priceTrees;

    /// @dev order queue for each collection, side and expecially price, sorted by orderKey
    // nft collection address->（买入/卖出 -> （价格->订单队列) ） 
    // 订单队列 只保留 head 和 tail 两个订单 ， 全量订单在 orders 保存
    mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue))) public orderQueues;

    /// @dev all order keys are wrapped in a sentinel value to avoid collisions
    // OrderKey->LibOrder.DBOrder(包含下一个订单的  OrderKey next)
    // orders : 包含所有价格都订单，每个价格是一条链 
    mapping(OrderKey => LibOrder.DBOrder) public orders;

    function __OrderStorage_init() internal onlyInitializing {}

    function __OrderStorage_init_unchained() internal onlyInitializing {}

    function onePlus(uint256 x) internal pure returns (uint256) {
        unchecked {
            return 1 + x;
        }
    }

    function getBestPrice(
        address collection,
        LibOrder.Side side
    ) public view returns (Price price) {
        price = (side == LibOrder.Side.Bid)
            ? priceTrees[collection][side].last()
            : priceTrees[collection][side].first();

    }

    function getNextBestPrice(
        address collection,
        LibOrder.Side side,
        Price price
    ) public view returns (Price nextBestPrice) {
        if (RedBlackTreeLibrary.isEmpty(price)) {
            nextBestPrice = (side == LibOrder.Side.Bid)
                ? priceTrees[collection][side].last()
                : priceTrees[collection][side].first();
        } else {
            nextBestPrice = (side == LibOrder.Side.Bid)
                ? priceTrees[collection][side].prev(price)
                : priceTrees[collection][side].next(price);
           // 买入 Bid：找更低的价格
           // 卖出 list：找更高的价格
        }
    }

    function _addOrder(
        LibOrder.Order memory order
    ) internal returns (OrderKey orderKey) {
        // 获取订单的hash值
        orderKey = LibOrder.hash(order);
        if (orders[orderKey].order.maker != address(0)) {
            // 如果订单已存在，就直接报错退出
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
            // 更新orders
            orders[orderKey] = LibOrder.DBOrder( // 创建新的订单，插入队列， 下一个订单为sentinel
                order,
                LibOrder.ORDERKEY_SENTINEL
            );
            // 更新队列
            orderQueue.head = orderKey;
            orderQueue.tail = orderKey;
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

    function _removeOrder(
        LibOrder.Order memory order
    ) internal returns (OrderKey orderKey) {
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
                    // 如果移除的是第一个订单
                    // orderQueue 只会在移除第一个 和 最后一个订单的时候发生修改
                    orderQueue.head = dbOrder.next;
                } 
                if (OrderKey.unwrap(orderQueue.tail) ==OrderKey.unwrap(orderKey)) {
                    // 如果移除的是最后一个订单
                   // orderQueue 只会在移除第一个 和 最后一个订单的时候发生修改
                    orderQueue.tail = prevOrderKey;
                }
                if (OrderKey.unwrap(orderQueue.head) !=OrderKey.unwrap(orderKey)) {
                    // 如果移除的不是第一个订单
                    // orders 只会在第二个订单之后发生修改
                    orders[prevOrderKey].next = dbOrder.next;
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

    /**
     * @dev Retrieves a list of orders that match the specified criteria.
     * @param collection The address of the NFT collection.
     * @param tokenId The ID of the NFT.
     * @param side The side of the orders to retrieve (buy or sell).
     * @param saleKind The type of sale (fixed price or auction).
     * @param count The maximum number of orders to retrieve.
     * @param price The maximum price of the orders to retrieve.
     */
    function getOrders(
        address collection,
        uint256 tokenId,
        LibOrder.Side side,
        LibOrder.SaleKind saleKind,
        uint256 count,
        Price price
        // OrderKey firstOrderKey
    )
        external
        view
        returns (LibOrder.Order[] memory resultOrders, OrderKey nextOrderKey)
    {
        resultOrders = new LibOrder.Order[](count);

        if (RedBlackTreeLibrary.isEmpty(price)) {
            // 没有给出价格，就找出最低 和 最高价格
            price = getBestPrice(collection, side);
        } else {
            price = getNextBestPrice(collection, side, price);

        }

        uint256 i;
        while (RedBlackTreeLibrary.isNotEmpty(price) && i < count) {
            // 循环遍历所有价格 price ，直到没有数据
            LibOrder.OrderQueue memory orderQueue = orderQueues[collection][side][price];
            OrderKey orderKey = orderQueue.head;
            while (LibOrder.isNotSentinel(orderKey)) {
                LibOrder.DBOrder memory order = orders[orderKey];
                orderKey = order.next;
            }
       
            while (LibOrder.isNotSentinel(orderKey) && i < count) {
                LibOrder.DBOrder memory dbOrder = orders[orderKey];
                orderKey = dbOrder.next;
                if (
                    (dbOrder.order.expiry != 0 &&
                        dbOrder.order.expiry < block.timestamp)
                ) {
                    continue;
                }

                if (
                    (side == LibOrder.Side.Bid) &&
                    (saleKind == LibOrder.SaleKind.FixedPriceForCollection)
                ) {
                    if (
                        (dbOrder.order.side == LibOrder.Side.Bid) &&
                        (dbOrder.order.saleKind ==
                            LibOrder.SaleKind.FixedPriceForItem)
                    ) {
                        continue;
                    }
                }

                if (
                    (side == LibOrder.Side.Bid) &&
                    (saleKind == LibOrder.SaleKind.FixedPriceForItem)
                ) {
                    if (
                        (dbOrder.order.side == LibOrder.Side.Bid) &&
                        (dbOrder.order.saleKind ==
                            LibOrder.SaleKind.FixedPriceForItem) &&
                        (tokenId != dbOrder.order.nft.tokenId)
                    ) {
                        continue;
                    }
                }

                resultOrders[i] = dbOrder.order;
                nextOrderKey = dbOrder.next;
                i = onePlus(i);
            }
            price = getNextBestPrice(collection, side, price);
        }
    }

    function getBestOrder(
        address collection,
        uint256 tokenId,
        LibOrder.Side side,
        LibOrder.SaleKind saleKind
    ) external view returns (LibOrder.Order memory orderResult) {
        Price price = getBestPrice(collection, side);
        while (RedBlackTreeLibrary.isNotEmpty(price)) {
            LibOrder.OrderQueue memory orderQueue = orderQueues[collection][
                side
            ][price];
            OrderKey orderKey = orderQueue.head;
            while (LibOrder.isNotSentinel(orderKey)) {
                LibOrder.DBOrder memory dbOrder = orders[orderKey];
                if (
                    (side == LibOrder.Side.Bid) &&
                    (saleKind == LibOrder.SaleKind.FixedPriceForItem)
                ) {
                    if (
                        (dbOrder.order.side == LibOrder.Side.Bid) &&
                        (dbOrder.order.saleKind ==
                            LibOrder.SaleKind.FixedPriceForItem) &&
                        (tokenId != dbOrder.order.nft.tokenId)
                    ) {
                        orderKey = dbOrder.next;
                        continue;
                    }
                }

                if (
                    (side == LibOrder.Side.Bid) &&
                    (saleKind == LibOrder.SaleKind.FixedPriceForCollection)
                ) {
                    if (
                        (dbOrder.order.side == LibOrder.Side.Bid) &&
                        (dbOrder.order.saleKind ==
                            LibOrder.SaleKind.FixedPriceForItem)
                    ) {
                        orderKey = dbOrder.next;
                        continue;
                    }
                }

                if (
                    (dbOrder.order.expiry == 0 ||
                        dbOrder.order.expiry > block.timestamp)
                ) {
                    orderResult = dbOrder.order;
                    break;
                }
                orderKey = dbOrder.next;
            }
            if (Price.unwrap(orderResult.price) > 0) {
                break;
            }
            price = getNextBestPrice(collection, side, price);
        }
    }

    uint256[50] private __gap;
}
