const axios = require("axios");
const fs = require("fs");

// Configuration
const LOG_FILE = "ip_rotations.log";
const JSON_LOG_FILE = "ip_rotations_detailed.json";
const API_URL = "http://api.ipify.org?format=json";
const DEFAULT_REQUESTS = 20;
const TIMEOUT = 5000; // timeout in ms

// Get number of requests from command line argument or use default
const numRequests = process.argv[2]
  ? parseInt(process.argv[2])
  : DEFAULT_REQUESTS;

/**
 * Check IP rotation by making multiple requests to the API
 * @param {number} requests - Number of requests to make
 * @returns {Promise<string[]>} - Array of IP addresses from responses
 */
async function checkIPRotation(requests) {
  const ips = new Set();
  const results = [];
  const ipCount = {};
  const metrics = {
    successCount: 0,
    failCount: 0,
    startTime: Date.now(),
    responseTimes: [],
  };

  console.log(`Testing API routing with ${requests} requests...`);
  console.log(`Date: ${new Date().toISOString()}`);
  console.log(`Target URL: ${API_URL}`);
  console.log("");

  for (let i = 0; i < requests; i++) {
    const startTime = Date.now();
    try {
      const response = await axios.get(API_URL, { timeout: TIMEOUT });
      const responseTime = Date.now() - startTime;
      const ip = response.data.ip;

      results.push(ip);
      ips.add(ip);
      ipCount[ip] = (ipCount[ip] || 0) + 1;

      metrics.successCount++;
      metrics.responseTimes.push(responseTime);

      console.log(`Request ${i + 1}: ${ip} (${responseTime}ms)`);

      // Wait briefly between requests
      await new Promise((resolve) => setTimeout(resolve, 1000));
    } catch (error) {
      metrics.failCount++;
      console.error(`Request ${i + 1}: Failed - ${error.message}`);
    }
  }

  // Calculate metrics
  metrics.totalTime = Date.now() - metrics.startTime;
  metrics.avgResponseTime =
    metrics.responseTimes.length > 0
      ? metrics.responseTimes.reduce((a, b) => a + b, 0) /
        metrics.responseTimes.length
      : 0;

  // Print summary
  console.log("\nSummary:");
  console.log(`Total requests: ${requests}`);
  console.log(`Successful requests: ${metrics.successCount}`);
  console.log(`Failed requests: ${metrics.failCount}`);
  console.log(`Average response time: ${metrics.avgResponseTime.toFixed(1)}ms`);
  console.log(`Unique IPs detected: ${ips.size}`);
  console.log(`IPs found: ${Array.from(ips).join(", ")}`);

  console.log("\nIP distribution:");
  Object.entries(ipCount).forEach(([ip, count]) => {
    const percentage = ((count / requests) * 100).toFixed(1);
    const bar = "#".repeat(Math.floor(percentage / 5)); // Visual bar
    console.log(`${ip}: ${count} requests (${percentage}%) ${bar}`);
  });

  // Log to file
  const logEntry = `${new Date().toISOString()}: Requests=${requests}, Success=${
    metrics.successCount
  }, Failed=${metrics.failCount}, AvgTime=${metrics.avgResponseTime.toFixed(
    1
  )}ms, Unique IPs=${ips.size}, IPs=${Array.from(ips).join(",")}`;
  fs.appendFileSync(LOG_FILE, logEntry + "\n");

  // Log detailed JSON data
  const detailedLog = {
    timestamp: new Date().toISOString(),
    requests: {
      total: requests,
      success: metrics.successCount,
      failed: metrics.failCount,
    },
    performance: {
      totalTime: metrics.totalTime,
      avgResponseTime: metrics.avgResponseTime,
    },
    ipData: {
      uniqueCount: ips.size,
      ips: Array.from(ips),
      distribution: ipCount,
    },
  };

  fs.appendFileSync(JSON_LOG_FILE, JSON.stringify(detailedLog) + "\n");

  return results;
}

// Run the test when script is executed directly
if (require.main === module) {
  checkIPRotation(numRequests);
}

// Export for use in other scripts
module.exports = { checkIPRotation };
