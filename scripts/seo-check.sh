#!/bin/bash
# Basic SEO check script for r2drop.com
# Run this before major releases to catch common SEO issues

set -e

echo "🔍 R2Drop SEO Health Check"
echo "========================="

WEBSITE_DIR="$(dirname "$0")/../www"
ISSUES=0

echo "📄 Checking homepage..."

# Check H1 tag (should have exactly one)
H1_COUNT=$(grep -c "<h1[^>]*>" "$WEBSITE_DIR/index.html" || echo "0")
if [ "$H1_COUNT" -ne 1 ]; then
    echo "❌ Homepage should have exactly 1 H1 tag (found: $H1_COUNT)"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ Homepage H1 structure looks good"
fi

# Check for multiple H2s that aren't semantic
H2_COUNT=$(grep -c "<h2[^>]*>" "$WEBSITE_DIR/index.html" || echo "0")
if [ "$H2_COUNT" -gt 6 ]; then
    echo "⚠️  Homepage has $H2_COUNT H2 tags - check if any are decorative and should be divs"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ Homepage H2 count reasonable ($H2_COUNT)"
fi

echo ""
echo "📝 Checking meta descriptions..."

# Check articles page for beta language
if grep -q "Free during beta" "$WEBSITE_DIR/articles.html"; then
    echo "❌ Articles page still contains 'Free during beta' language"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ Articles page meta description up to date"
fi

# Check for empty meta descriptions
EMPTY_DESC=$(find "$WEBSITE_DIR" -name "*.html" -exec grep -L "meta.*description" {} \; | wc -l)
if [ "$EMPTY_DESC" -gt 0 ]; then
    echo "❌ Found $EMPTY_DESC HTML files without meta descriptions"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ All HTML files have meta descriptions"
fi

echo ""
echo "🖼️  Checking OG images..."

# Check for generic OG images
GENERIC_OG=$(find "$WEBSITE_DIR" -name "*.html" -exec grep -l "cdn.r2drop.com/site/og.png" {} \; | wc -l)
if [ "$GENERIC_OG" -gt 1 ]; then
    echo "❌ Found $GENERIC_OG files still using generic OG image:"
    find "$WEBSITE_DIR" -name "*.html" -exec grep -l "cdn.r2drop.com/site/og.png" {} \;
    ISSUES=$((ISSUES + 1))
else
    echo "✅ Blog posts have specific OG images"
fi

echo ""
echo "🔗 Checking canonical URLs..."

# Check for missing canonical URLs
MISSING_CANONICAL=$(find "$WEBSITE_DIR" -name "*.html" -exec grep -L "rel=\"canonical\"" {} \; | wc -l)
if [ "$MISSING_CANONICAL" -gt 0 ]; then
    echo "⚠️  Found $MISSING_CANONICAL files without canonical URLs"
    find "$WEBSITE_DIR" -name "*.html" -exec grep -L "rel=\"canonical\"" {} \; | head -5
    ISSUES=$((ISSUES + 1))
else
    echo "✅ All HTML files have canonical URLs"
fi

echo ""
echo "📊 Summary"
echo "=========="

if [ "$ISSUES" -eq 0 ]; then
    echo "🎉 No SEO issues found! Site is ready for deployment."
    exit 0
else
    echo "⚠️  Found $ISSUES SEO issues that should be addressed."
    echo ""
    echo "Common fixes:"
    echo "- Convert decorative headings from H2 to div or H3"
    echo "- Update meta descriptions to current product positioning"
    echo "- Assign specific OG images to blog posts"
    echo "- Add canonical URLs to all pages"
    exit 1
fi