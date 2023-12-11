**All solutions are in test folder with attack smart contracts**

# Mr Steal Yo Crypto CTF

**A set of challenges to learn offensive security of smart contracts.** Featuring interesting challenges loosely (or directly) inspired by real world exploits.

Created by [@0xToshii](https://twitter.com/0xToshii)

## Play

Visit [mrstealyocrypto.xyz](https://mrstealyocrypto.xyz)

Primer & Hints: [degenjungle.substack.com/p/mr-steal-yo-crypto-wargame](https://degenjungle.substack.com/p/mr-steal-yo-crypto-wargame)

Note: main branch includes solutions, run <code>git checkout implement</code> to see problems without their respective solutions

## Foundry Instructions

1. Install foundry: [foundry-book](https://book.getfoundry.sh/getting-started/installation)

2. Clone this repo and install dependencies

```console
forge install
```

3. Code your solutions and run the associated test files

```console
forge test --match-path test/challenge-name.sol
```

### Rules & Tips

- In all challenges you must use the account called attacker (unless otherwise specified).
- In some cases, you may need to code and deploy custom smart contracts.
