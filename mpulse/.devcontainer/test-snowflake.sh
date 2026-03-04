#!/bin/bash
set -e

echo "============================================"
echo "  Snowflake CLI Connection Test"
echo "============================================"
echo ""

echo "Step 1: Change to data_ops_ingestion"
cd /workspace/DPI_Analytics_DBT/data_ops_ingestion || { echo "❌ Directory not found"; exit 1; }
echo "  → $(pwd)"
echo ""

echo "Step 2: Verify snow CLI is available"
snow --version
echo ""

echo "Step 3: List connections (should show config entries)"
snow connection list
echo ""

echo "Step 4: Test default connection (will prompt for auth)"
echo "  → Authenticate in your browser when prompted..."
snow connection test
echo ""

echo "============================================"
echo "  Auth complete. Testing cached credentials..."
echo "============================================"
echo ""

echo "Step 5: Test connection again (should use cached creds)"
snow connection test
echo ""

echo "============================================"
echo "  ✅ If Step 5 succeeded without a browser"
echo "     prompt, credential caching is working."
echo "============================================"
