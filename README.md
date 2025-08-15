# Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.js
```
# EasySwapContract


部署和升级脚本
```
npx hardhat clean && npx hardhat compile

npx hardhat deploy   --tags deployNftAuction --network sepolia 

```

合约架构整理
```
--- EasySwapOrderBook: 主要业务逻辑
1.makeOrders : 下单
2.matchOrders : 匹配订单
3.editOrders : 编辑订单
4.cancelOrders : 取消订单

--- EasySwapVault : NFT 的转入，转出工具 ; eth 和 NFT 都存在这个地址
depositETH : 存入NFT
withdrawNFT :  取出NFT

--- OrderStorage : 订单存储层
// (订单key-> 订单的详细信息)
mapping(OrderKey => LibOrder.DBOrder) public orders;

// 买入和卖出的价格排序
// 买入/卖出 -> 价格树
mapping(address => mapping(LibOrder.Side => RedBlackTreeLibrary.Tree)) public priceTrees;

// 订单队列： 买入/卖出 -> （价格-> 价格队列）
mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue))) public orderQueues;

---OrderValidator: 订单存储层
// 订单号 -> 订单金额 ：CANCELLED 为 已经取消
mapping(OrderKey => uint256) public filledAmount;

---ProtocolManager: 匹配订单的工具类
protocolShare :


```
