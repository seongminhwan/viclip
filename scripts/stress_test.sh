#!/bin/bash
# VTool Performance Stress Test Script
# Generates test data and measures performance

set -e

VTOOL_DB="$HOME/Library/Application Support/VTool/vtool.db"

echo "=== VTool 性能压测脚本 ==="
echo ""

# Check if sqlite3 exists
if ! command -v sqlite3 &> /dev/null; then
    echo "❌ sqlite3 未安装"
    exit 1
fi

# Check database exists
if [ ! -f "$VTOOL_DB" ]; then
    echo "❌ 数据库不存在: $VTOOL_DB"
    echo "请先运行 VTool 至少一次以创建数据库"
    exit 1
fi

# Get current count
CURRENT_COUNT=$(sqlite3 "$VTOOL_DB" "SELECT COUNT(*) FROM clipboard_items")
echo "📊 当前条目数: $CURRENT_COUNT"
echo ""

# Ask user
echo "选择操作:"
echo "  1) 生成 1000 条测试文本"
echo "  2) 生成 5000 条测试文本"
echo "  3) 生成 10000 条测试文本"
echo "  4) 生成 500000 条 (50万)"
echo "  5) 生成 10000000 条 (1000万)"
echo "  6) 查询性能测试"
echo "  7) 清除测试数据"
echo "  0) 退出"
echo ""
read -p "请输入选项 [0-7]: " CHOICE

case $CHOICE in
    1|2|3|4|5)
        case $CHOICE in
            1) COUNT=1000 ;;
            2) COUNT=5000 ;;
            3) COUNT=10000 ;;
            4) COUNT=500000 ;;
            5) COUNT=10000000 ;;
        esac
        
        echo ""
        echo "⏳ 正在生成 $COUNT 条测试数据..."
        
        START_TIME=$(date +%s.%N)
        
        # Generate test data using SQL
        # Get current max position
        MAX_POS=$(sqlite3 "$VTOOL_DB" "SELECT COALESCE(MAX(position), 0) FROM clipboard_items")
        
        sqlite3 "$VTOOL_DB" <<EOF
-- Insert test data with proper positions
WITH RECURSIVE cnt(x) AS (
    SELECT 1
    UNION ALL
    SELECT x+1 FROM cnt WHERE x < $COUNT
)
INSERT INTO clipboard_items (id, content_type, content, is_external, content_size, created_at, position, is_favorite, source_app, source_bundle_id)
SELECT 
    lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6))),
    'text',
    CAST('压测数据 #' || ($MAX_POS + x) || ' - ' || datetime('now') AS BLOB),
    0,
    50,
    strftime('%s', 'now') + x,
    $MAX_POS + x,
    0,
    'StressTest',
    'com.vtool.stresstest'
FROM cnt;

-- Update FTS index
INSERT INTO clipboard_fts(rowid, text_content)
SELECT rowid, CAST(content AS TEXT) FROM clipboard_items WHERE source_app = 'StressTest';
EOF
        
        END_TIME=$(date +%s.%N)
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        
        NEW_COUNT=$(sqlite3 "$VTOOL_DB" "SELECT COUNT(*) FROM clipboard_items")
        
        echo "✅ 完成!"
        echo "   添加了: $COUNT 条"
        echo "   总条目: $NEW_COUNT"
        echo "   耗时: ${DURATION}秒"
        echo "   速率: $(echo "scale=0; $COUNT / $DURATION" | bc) 条/秒"
        ;;
        
    6)
        echo ""
        echo "⏳ 正在测试查询性能..."
        
        # Test 1: Count
        echo ""
        echo "📝 测试1: COUNT(*)"
        time sqlite3 "$VTOOL_DB" "SELECT COUNT(*) FROM clipboard_items"
        
        # Test 2: Recent items
        echo ""
        echo "📝 测试2: 获取最近100条"
        time sqlite3 "$VTOOL_DB" "SELECT id FROM clipboard_items ORDER BY position DESC LIMIT 100" > /dev/null
        
        # Test 3: FTS search
        echo ""
        echo "📝 测试3: FTS5 全文搜索"
        time sqlite3 "$VTOOL_DB" "SELECT COUNT(*) FROM clipboard_items ci JOIN clipboard_fts fts ON ci.rowid = fts.rowid WHERE clipboard_fts MATCH 'test'"
        
        # Test 4: Pagination
        echo ""
        echo "📝 测试4: 分页查询 (OFFSET 5000)"
        time sqlite3 "$VTOOL_DB" "SELECT id FROM clipboard_items ORDER BY position DESC LIMIT 100 OFFSET 5000" > /dev/null
        ;;
        
    7)
        echo ""
        read -p "⚠️  确定清除测试数据? (y/N): " CONFIRM
        if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
            echo "⏳ 正在清除..."
            # Delete from main table first, FTS will be rebuilt on next app launch
            sqlite3 "$VTOOL_DB" "DELETE FROM clipboard_items WHERE source_app = 'StressTest'"
            # Rebuild FTS index
            sqlite3 "$VTOOL_DB" "INSERT INTO clipboard_fts(clipboard_fts) VALUES('rebuild')" 2>/dev/null || true
            NEW_COUNT=$(sqlite3 "$VTOOL_DB" "SELECT COUNT(*) FROM clipboard_items")
            echo "✅ 清除完成，剩余 $NEW_COUNT 条"
        fi
        ;;
        
    0)
        echo "退出"
        exit 0
        ;;
        
    *)
        echo "无效选项"
        exit 1
        ;;
esac
