const { expect } = require("chai")
const { ethers, upgrades } = require("hardhat")
const { toBn } = require("evm-bn")
const { Side, SaleKind } = require("./common")
// const { exp } = require("@prb/math")

let owner, addr1, addr2, addrs
let esVault, esDex, testERC721, testLibOrder
const AddressZero = "0x0000000000000000000000000000000000000000";
const Byte32Zero = "0x0000000000000000000000000000000000000000000000000000000000000000";
const Uint128Max = toBn("340282366920938463463.374607431768211455");
const Uint256Max = toBn("115792089237316195423570985008687907853269984665640564039457.584007913129639935");

describe("EasySwap Test", function () {
    beforeEach(async function () {
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        // console.log("owner: ", owner.address)

        const esVaultFactory = await ethers.getContractFactory("EasySwapVault")
        const esDexFactory = await ethers.getContractFactory("EasySwapOrderBook")
        const testERC721Factory = await ethers.getContractFactory("TestERC721")
        const testLibOrderFactory = await ethers.getContractFactory("LibOrderTest")

        // 部署 LibOrderTest 
        testLibOrder = await testLibOrderFactory.deploy()
        // await testLibOrder.waitForDeployment();
        console.log("testLibOrder deployed to:", await testLibOrder.address);

        // 部署NFT 
        testERC721 = await testERC721Factory.deploy()
        // await testERC721.waitForDeployment();
        console.log("testERC721 deployed to:", await testERC721.address);

        // 部署 EasySwapVault
        esVault = await upgrades.deployProxy(esVaultFactory, { initializer: 'initialize' });
        // await esVault.waitForDeployment();
        console.log("esVault deployed to:", await esVault.address);

        // 部署 EasySwapOrderBook
        newProtocolShare = 200;
        EIP712Name = "EasySwapOrderBook"
        EIP712Version = "1"
        esDex = await upgrades.deployProxy(esDexFactory, [newProtocolShare, esVault.address, EIP712Name, EIP712Version], 
            {initializer: 'initialize' });
        // await esDex.waitForDeployment();
        console.log("esDex deployed to:", await esDex.address);
        for (let i = 0; i < 10; i++) {
           await testERC721.mint(owner.address, i );
        }
        testERC721.connect(owner).setApprovalForAll(esVault.address, true)
        testERC721.connect(owner).setApprovalForAll(esDex.address, true)

        await esVault.setOrderBook(esDex.address)
    })

    describe("should make order successfully", async () => {
        it("should make list/sell order successfully 111 ", async () => {
            const now = parseInt(new Date() / 1000) + 100000
            const salt = 1;
            const nftAddress = testERC721.address;
            const tokenId = 0;
            const nftAmount = 1;
            const order = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: toBn("0.01"),
                expiry: now,
                salt: salt,
            }
            const orders = [order];

            orderKeys = await esDex.connect(owner).makeOrders(orders)
            expect(orderKeys[0]).to.not.equal(Byte32Zero)
            // console.log("ordorderKeys: ", orderKeys)

            await expect(await esDex.connect(owner).makeOrders(orders)).to.emit(esDex, "LogMake")

            const orderHash = await testLibOrder.getOrderHash(order)
            console.log("orderHash: ", orderHash)

            dbOrder = await esDex.orders(orderHash)
            // console.log("dbOrder: ", dbOrder)
            expect(dbOrder.order.maker).to.equal(owner.address)
            expect(await testERC721.ownerOf(0)).to.equal(esVault.address)
        })

        it("should make list/sell order and return orders successfully 222 ", async () => {
            const now = parseInt(new Date() / 1000) + 100000
            const salt = 1;
            const nftAddress = testERC721.address;
            const tokenId = 0;
            const order = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: toBn("0.01"),
                expiry: now,
                salt: salt,
            }
            const orders = [order];

            orderKeys = await esDex.connect(owner).makeOrders(orders)
            expect(orderKeys[0]).to.not.equal(Byte32Zero)

        })

        it("should make bid/buy order successfully", async () => {
            const now = parseInt(new Date() / 1000) + 100000
            const salt = 1;
            const nftAddress = testERC721.address;
            const tokenId = 0;
            const order = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: toBn("0.01"),
                expiry: now,
                salt: salt,
            }
            const orders = [order];

            orderKeys = await esDex.callStatic.makeOrders(orders, { value: toBn("0.02") })
            expect(orderKeys[0]).to.not.equal(Byte32Zero)

            await expect(await esDex.makeOrders(orders, { value: toBn("0.02") }))
                .to.changeEtherBalances([owner, esVault], [toBn("-0.01"), toBn("0.01")]);

            const orderHash = await testLibOrder.getOrderHash(order)
            // console.log("orderHash: ", orderHash)

            dbOrder = await esDex.orders(orderHash)
            // console.log("dbOrder: ", dbOrder)
            expect(dbOrder.order.maker).to.equal(owner.address)
        })

        it("should make two side order successfully", async () => {
            const now = parseInt(new Date() / 1000) + 100000
            const salt = 1;
            const nftAddress = testERC721.address;
            const tokenId = 0;
            const listOrder = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: toBn("0.01"),
                expiry: now,
                salt: salt,
            }

            const bidOrder = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: toBn("0.01"),
                expiry: now,
                salt: salt,
            }
            const orders = [listOrder, bidOrder];

            orderKeys = await esDex.callStatic.makeOrders(orders, { value: toBn("0.02") })
            expect(orderKeys[0]).to.not.equal(Byte32Zero)
            expect(orderKeys[1]).to.not.equal(Byte32Zero)

            await expect(await esDex.makeOrders(orders, { value: toBn("0.02") }))
                .to.changeEtherBalances([owner, esVault], [toBn("-0.01"), toBn("0.01")]);

            const listOrderHash = await testLibOrder.getOrderHash(listOrder)
            dbOrder = await esDex.orders(listOrderHash)
            expect(dbOrder.order.maker).to.equal(owner.address)
            expect(await testERC721.ownerOf(0)).to.equal(esVault.address)

            const bidOrderHash = await testLibOrder.getOrderHash(bidOrder)
            dbOrder2 = await esDex.orders(bidOrderHash)
            expect(dbOrder2.order.maker).to.equal(owner.address)
        })
    })

})
