# 合约架构整理
```
contract kənˈtrækt

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

--- EasySwapVault （vɔːlt） : 钱包和转账层
ETHBalance：用户eth余额
NFTBalance：用户nft余额
depositETH : 存入NFT
withdrawNFT :  取出NFT

---OrderValidator: 订单验证器
// 订单号 -> 订单金额 ：CANCELLED 为 已经取消
mapping(OrderKey => uint256) public filledAmount;

---ProtocolManager: 管理协议费
protocolShare : 手续费

```

# 数据结构
### 二叉搜索树 (binary tree) 
```
每个节点最多有两个子节点，且满足：左子节点 < 父节点 < 右子节点。
缺点： 当连续插入一段数据后，会退化成链表

```
### 红黑树 (red-black tree)
```
是一种自平衡的BST，额外增加了颜色属性（红/黑）和一系列平衡规则。
设定规则：用“黑色高度相同”和“红色不相邻”两条核心规则作为平衡的衡量标准。
违规触发：一旦插入或删除操作导致树的结构可能趋向不平衡（表现为违反了规则），修复机制立刻被触发。
旋转调整：通过旋转操作来改变树的结构，物理上降低树的高度，消除长链。
变色维持：通过变色操作来满足颜色规则，同时保证旋转后黑色高度不变。
```
### B+Tree
```
B+Tree是多路搜索树，一个节点可以有M个分支（M可能为100甚至更大）
```

# EVM 数据存储
```
Calldata
这是一个特殊的、只读的区域，用于存储触发合约执行的原始交易数据。

memory : EVM自身的内存,临时存储，函数执行期间有效
主要存储 : 存储函数的参数和返回值。

Stack : 栈是 EVM 执行计算的核心区域,有1024个slot
存储局部变量(如果是值类型，如 uint, bool)；存储计算过程中的中间结果。

Storage : 持久化存储在区块链上，因此操作它需要消耗 Gas，且非常昂贵。
主要存储：映射 (Mapping)，动态数组 等全局变量

Stack 特例 ：
可知长度的数组 ：直接存储值（int a=3）
未知长度的数组 ：存储一个keccack256的 hash值
,指向memory或storage（int [] arr ）
```

# gas 优化
```
1. 使用事件（Event）来记录不需要链上访问的历史数据。
2. 尽可能使用 memory 和 calldata 。
3. 利用存储打包，将多个小尺寸变量声明在一起,放在一个槽中。
一个存储槽 = 32 字节（256 位）
存储打包：如果多个连续声明的状态变量的大小总和小于或等于 32 字节，EVM 会尝试将它们“打包”到同一个存储槽中，而不是每个变量独占一个槽。

```

# 代理升级
```
透明代理(Transparent Proxy（ˈprɑːksi）)
UUPS代理(Universal Upgradeable Proxy Standard)
升级逻辑的位置：透明代理将升级逻辑放在代理合约（Proxy Contract）中，而UUPS代理将升级逻辑(logic ) 内置在 实现合约（Implemented Contract）中。

```

# 交易撮合
```
挂单（make）
撮合 (match)
链上订单薄（on-chain-orderbook）

存储：
红黑树(red-black tree) 和 链式队列(chain/linked queue (kjuː))

```

# 资产安全
```
1. 卖家先存入 nft，买家先存入eth
2. 接口限制，vault 合约只能被 orderbook 合约调用
3. ReentrancyGuardUpgradeable ：防止提款重入攻击:  __ReentrancyGuard_init -> nonReentrant
open zeppelin(ˈzepəlɪn)
Re entrance Guard  Upgrade able
 (ɪnˈtræns  ɡɑːrd  ˈʌpɡreɪd)
4. 多签: 提取手续费需要多签
```

# 双花攻击
```
双花攻击（Double-Spend Attack） 指的是攻击者试图将同一笔数字货币花费两次的恶意行为。
分布式账本，共识机制，工作量证明，最长链原则
Consensus Mechanism， Distributed Ledger，Proof-of-Work (PoW)，Longest Chain Rule

挖矿就是争夺记账权
Bitcoin mining is competing for the right to add a new block to the blockchain.

```

# Redis 缓存雪崩 （Cache Avalanche （ˈævəlæntʃ） ）
```
大量缓存数据同时过期（失效） 或 Redis 缓存服务直接宕机

1. 在设置缓存数据的过期时间时，在基础值上增加一个随机时间因子。
set key value ex (3600 + random(0, 300))

2. 使用redis高可用集群

```
