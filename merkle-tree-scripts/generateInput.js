// JavaScript version of the script to generate input data
const fs = require('fs');

// Constants
const tokenAddress = "0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f";
const epoch = 1;
const cumulativeMin = BigInt("10000000000000000"); // 0.01 ETH
const cumulativeMax = BigInt("10000000000000000000000000"); // 10,000 ETH
const outputFile = "input_data.json";
const entries = 100000;

// Function to generate a random Ethereum address
function generateRandomEthAddress() {
    return "0x" + [...Array(20)].map(() => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('');
}

// Function to generate the data
function generateData(entries) {
    const data = [];
    for (let i = 0; i < entries; i++) {
        const entry = {
            epoch: epoch,
            account: generateRandomEthAddress(),
            token: tokenAddress,
            cumulativeAmount: (cumulativeMin + BigInt(Math.floor(Math.random() * Number(cumulativeMax - cumulativeMin)))).toString()
        };
        data.push(entry);
    }
    return data;
}

// Generate the data with specified amount of entries
const data = generateData(entries);

// Write the data to a JSON file
fs.writeFileSync(outputFile, JSON.stringify(data, null, 4));

console.log(`Generated ${data.length} entries and saved to ${outputFile}`);