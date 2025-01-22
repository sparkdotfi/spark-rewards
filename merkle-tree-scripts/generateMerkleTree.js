const { StandardMerkleTree } = require('@openzeppelin/merkle-tree');
const fs = require('fs');
const path = require('path'); // For handling file paths
const { BigNumber } = require('ethers');

// Helper function to hash a leaf
function hashLeaf(epoch, account, token, cumulativeAmount) {
    return [
        epoch.toString(),
        account.toString(),
        token.toString(),
        BigNumber.from(cumulativeAmount)
    ];
}

// Function to generate a Merkle Tree
function generateMerkleTree(rewards) {
    /**
     * Rewards should be an array of objects in the following format:
     * [
     *   { epoch: uint256, account: "0x...", token: "0x...", cumulativeAmount: uint256 },
     *   ...
     * ]
     */

    // Map rewards to structured leaves
    const tree = StandardMerkleTree.of(
        rewards.map(({ epoch, account, token, cumulativeAmount }) =>
            hashLeaf(epoch, account, token, cumulativeAmount)
        ),
        ["uint256", "address", "address", "uint256"]
    );

    // Return the Merkle Root and the Tree instance
    return { root: tree.root, tree };
}

// Function to write the Merkle Tree data to a JSON file
function writeMerkleTreeToFile(filePath, tree, rewards) {
    const treeData = {
        root: tree.root, // Use `tree.root` for the Merkle root
        values: rewards.map((reward, index) => {
            const proof = tree.getProof(index);
            return {
                ...reward,
                proof
            };
        })
    };
    fs.writeFileSync(filePath, JSON.stringify(treeData, null, 2), 'utf8');
}

// Function to read rewards data from a JSON file
function readRewardsData(filePath) {
    const data = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(data);
}

// Example usage
// (async () => {
//     // Read rewards data from a JSON file
//     const rewardsFilePath = './rewards.json';
//     const rewards = readRewardsData(rewardsFilePath);

//     // Generate the Merkle Tree
//     const { root, tree } = generateMerkleTree(rewards);

//     console.log("Merkle Root:", root);

//     // Write the Merkle Tree data to a JSON file
//     const outputFilePath = './merkleTree.json';
//     writeMerkleTreeToFile(outputFilePath, tree, rewards);

//     console.log("Merkle tree and proofs written to:", outputFilePath);
// })();

(async () => {
    const args = process.argv.slice(2);

    if (args.length < 2) {
        console.error("Usage: node generateMerkleTree.js <inputRewardsFilePath> <outputMerkleFilePath>");
        process.exit(1);
    }

    const inputFilePath = path.resolve(args[0]);
    const outputFilePath = path.resolve(args[1]);

    try {
        // Read rewards data from the specified JSON file
        const rewards = readRewardsData(inputFilePath);

        // Generate the Merkle Tree
        const { root, tree } = generateMerkleTree(rewards);

        console.log("Merkle Root:", root);

        // Write the Merkle Tree data to the specified JSON file
        writeMerkleTreeToFile(outputFilePath, tree, rewards);

        console.log("Merkle tree and proofs written to:", outputFilePath);
    } catch (error) {
        console.error("Error:", error.message);
        process.exit(1);
    }
})();
