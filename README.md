#  NFT Market 

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.js
```
# EasySwapContract

链上部署脚本
```shell
1. 部署 EasySwapVault 和 EasySwapOrderBook
npx hardhat run scripts/deploy.js  --network sepolia

2. 关联两个合约
npx hardhat run scripts/deploy_setbook.js  --network sepolia

```

测试脚本
```shell
npm cache clean --force
npx hardhat clean && npx hardhat compile
npx hardhat test test/testEasySwap_make.js   --network sepolia
npx hardhat test test/testEasySwap_match.js 
```


合约架构整理
```
--- EasySwapOrderBook: 业务逻辑层
1.makeOrders : 下单
2.matchOrders : 匹配订单
3.editOrders : 编辑订单
4.cancelOrders : 取消订单

--- OrderStorage : 数据存储层
// (订单key-> 订单的详细信息)
mapping(OrderKey => LibOrder.DBOrder) public orders;

// 买入和卖出的价格排序
// 买入/卖出 -> 价格树
mapping(address => mapping(LibOrder.Side => RedBlackTreeLibrary.Tree)) public priceTrees;

// 订单队列： 买入/卖出 -> （价格-> 价格队列）
mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue))) public orderQueues;

--- EasySwapVault : 钱包和转账层
ETHBalance：用户eth余额
NFTBalance：用户nft余额
depositETH : 存入NFT
withdrawNFT :  取出NFT

---OrderValidator: 订单验证器
// 订单号 -> 订单金额 ：CANCELLED 为 已经取消
mapping(OrderKey => uint256) public filledAmount;

---ProtocolManager: 管理协议费
protocolShare :


```
