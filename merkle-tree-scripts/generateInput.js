const fs = require('fs');

// Change these values as needed
const tokenAddresses = [
    "0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f",
    "0x2e234DAe75C793f67A35089C9d99245E1C58470b"
];
const cumulativeMin = BigInt("10000000000000000"); // 0.01 ETH
const cumulativeMax = BigInt("10000000000000000000000000"); // 10,000 ETH
const numberOfEntries = 100; // Set the number of entries to generate
const outputFilePath = "input_data.json"; // Set output file name

// Function to generate a random Ethereum address
function generateRandomEthAddress() {
    return "0x" + [...Array(20)].map(() => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('');
}

// Function to generate a random token address
function getRandomToken() {
    return tokenAddresses[Math.floor(Math.random() * tokenAddresses.length)];
}

// Function to generate a random epoch
function getRandomEpoch() {
    return (Math.floor(Math.random() * 5) + 1).toString(); // Random epoch from 1 to 5
}

// Function to generate the data
function generateData(entries) {
    const data = [];
    for (let i = 0; i < entries; i++) {
        const entry = {
            epoch: getRandomEpoch(),
            account: generateRandomEthAddress(),
            token: getRandomToken(),
            cumulativeAmount: (cumulativeMin + BigInt(Math.floor(Math.random() * Number(cumulativeMax - cumulativeMin)))).toString()
        };
        data.push(entry);
    }
    return data;
}

// Main function
(async () => {
    // Generate the data with the specified number of entries
    const data = generateData(numberOfEntries);

    // Write the data to a JSON file
    fs.writeFileSync(outputFilePath, JSON.stringify(data, null, 4));

    console.log(`Generated ${data.length} entries and saved to ${outputFilePath}`);
})();