const { ethers, upgrades } = require("hardhat")

async function main() {
  const [deployer] = await ethers.getSigners()
  console.log("deployer: ", deployer.address)

  esDexAddress = "0xcEE5AA84032D4a53a0F9d2c33F36701c3eAD5895"
  esVaultAddress = "0xaD65f3dEac0Fa9Af4eeDC96E95574AEaba6A2834"
  const esVault = await (
    await ethers.getContractFactory("EasySwapVault")
  ).attach(esVaultAddress)
  tx = await esVault.setOrderBook(esDexAddress)
  await tx.wait()
  console.log("esVault setOrderBook tx:", tx.hash)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
