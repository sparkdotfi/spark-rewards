const { StandardMerkleTree } = require('@openzeppelin/merkle-tree');
const fs = require('fs'); // For reading and writing JSON files
const path = require('path'); // For handling file paths

// Helper function to normalize leaf data
function hashLeaf(epoch, account, token, cumulativeAmount) {
    return [
        epoch.toString(),
        account.toLowerCase(), // Normalize account to lowercase
        token.toLowerCase(),   // Normalize token to lowercase
        cumulativeAmount.toString(),
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

    // Calculate the total number of claims (size of values array)
    const totalClaims = rewards.length;

    // Return the Merkle Root, Tree instance, Total Amount, and Total Claims
    return { root: tree.root, tree, totalClaims };
}

// Function to write the Merkle Tree data to a JSON file
function writeMerkleTreeToFile(filePath, tree, rewards, totalClaims) {
    const treeData = {
        root: tree.root, // Use `tree.root` for the Merkle root
        totalClaims: totalClaims, // Include the total number of claims
        values: rewards.map((reward, index) => {
            const proof = tree.getProof(index);

            // Use hashLeaf to normalize data
            const [epoch, account, token, cumulativeAmount] = hashLeaf(
                reward.epoch,
                reward.account,
                reward.token,
                reward.cumulativeAmount
            );

            return {
                epoch,
                account,
                token,
                cumulativeAmount,
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

// Main function to handle command-line arguments
(async () => {
    const args = process.argv.slice(2);

    if (args.length < 2) {
        console.error("Usage: node generateMerkleTree.js <inputRewardsFilePath> <outputFilePath>");
        process.exit(1);
    }

    const inputFilePath = path.resolve(args[0]);
    const outputFilePath = path.resolve(args[1]);

    try {
        // Read rewards data from the specified JSON file
        const rewards = readRewardsData(inputFilePath);

        // Generate the Merkle Tree and calculate the total amount of claims and total number of claims
        const { root, tree, totalClaims } = generateMerkleTree(rewards);

        console.log("Merkle Root:", root);
        console.log("Total Number of Claims:", totalClaims);

        // Write the Merkle Tree data to the specified JSON file
        writeMerkleTreeToFile(outputFilePath, tree, rewards, totalClaims);

        console.log("Merkle tree and proofs written to:", outputFilePath);
    } catch (error) {
        console.error("Error:", error.message);
        process.exit(1);
    }
})();
