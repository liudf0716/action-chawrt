#!/bin/bash

# 配置区域：定义仓库和分支映射（使用 | 分隔字段避免空格冲突）
# 核心仓库（稳定性高）
CORE_REPOS=(
    "https://github.com/openwrt/openwrt.git|https://github.com/liudf0716/chawrt.git|chawrt|main"
    "https://github.com/openwrt/packages.git|https://github.com/liudf0716/packages.git|packages|master"
)

# Luci仓库（单独同步）
LUCI_REPOS=(
    "https://github.com/openwrt/luci.git|https://github.com/liudf0716/luci.git|luci|master"
)

# 核心分支同步配置
CORE_CHAWRT_BRANCH=(
    "chawrt|main|main"          # REPO_DIR|YOUR_BRANCH|UPSTREAM_BRANCH
    "packages|chawrt/master|master"
)

# Luci分支同步配置
LUCI_CHAWRT_BRANCH=(
    "luci|chawrt/master|master"
)

# 核心24.10分支配置
CORE_CHAWRT_24_10_BRANCH=(
    "chawrt|24.10|openwrt-24.10"
    "packages|chawrt/24.10|openwrt-24.10"
)

# Luci 24.10分支配置
LUCI_CHAWRT_24_10_BRANCH=(
    "luci|chawrt/24.10|openwrt-24.10"
)

# 优雅处理中断
trap 'echo "脚本被中断"; exit 1' SIGINT

CORE_FAILED_TASKS=()
LUCI_FAILED_TASKS=()

# 安全的同步函数（用于luci等不稳定仓库）
safe_sync_repo() {
    local MAX_RETRIES=3
    local RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "尝试同步 ($((RETRY_COUNT + 1))/$MAX_RETRIES): $1"
        
        if sync_repo "$1"; then
            echo "同步成功: $1"
            return 0
        fi
        
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "等待5秒后重试..."
            sleep 5
        fi
    done
    
    echo "同步最终失败: $1"
    return 1
}

# 安全的分支同步函数
safe_sync_chawrt_branch() {
    local MAX_RETRIES=3
    local RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "尝试分支同步 ($((RETRY_COUNT + 1))/$MAX_RETRIES): $1"
        
        if sync_chawrt_branch "$1" "luci"; then
            echo "分支同步成功: $1"
            return 0
        fi
        
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "等待5秒后重试..."
            sleep 5
        fi
    done
    
    echo "分支同步最终失败: $1"
    return 1
}

# 同步仓库函数
sync_repo() {
    IFS='|' read -r UPSTREAM_REPO FORK_REPO REPO_DIR BRANCH <<< "$1"
    
    echo "同步仓库: $REPO_DIR (分支: $BRANCH)"

    # 克隆仓库（如果不存在）
    if [ ! -d "$REPO_DIR" ]; then
        echo "克隆仓库: $FORK_REPO"
        if ! git clone "$FORK_REPO" "$REPO_DIR"; then
            echo "克隆失败: $REPO_DIR"
            return 1
        fi
    fi

    if ! cd "$REPO_DIR"; then
        echo "无法进入目录: $REPO_DIR"
        return 1
    fi

    # 添加上游远程仓库
    if ! git remote | grep -q upstream; then
        if ! git remote add upstream "$UPSTREAM_REPO"; then
            echo "添加上游仓库失败: $UPSTREAM_REPO"
            cd ..
            return 1
        fi
    fi

    # 获取最新代码
    if ! git fetch --all; then
        echo "拉取代码失败: $REPO_DIR"
        cd ..
        return 1
    fi

    cd ..
    echo "成功同步仓库: $REPO_DIR"
    return 0
}

# 同步分支函数
sync_chawrt_branch() {
    IFS='|' read -r REPO_DIR YOUR_BRANCH UPSTREAM_BRANCH <<< "$1"
    local TASK_TYPE="${2:-core}"  # 默认为core类型

    echo "同步分支: 仓库=$REPO_DIR, 目标分支=$YOUR_BRANCH, 上游分支=$UPSTREAM_BRANCH"

    if [ ! -d "$REPO_DIR" ]; then
        echo "仓库不存在: $REPO_DIR"
        if [ "$TASK_TYPE" = "luci" ]; then
            LUCI_FAILED_TASKS+=("$REPO_DIR (not exist)")
        else
            CORE_FAILED_TASKS+=("$REPO_DIR (not exist)")
        fi
        return 1
    fi

    if ! cd "$REPO_DIR"; then
        echo "无法进入目录: $REPO_DIR"
        if [ "$TASK_TYPE" = "luci" ]; then
            LUCI_FAILED_TASKS+=("$REPO_DIR (cd)")
        else
            CORE_FAILED_TASKS+=("$REPO_DIR (cd)")
        fi
        return 1
    fi

    # 切换到目标分支（若不存在则基于上游创建）
    if git show-ref --verify --quiet "refs/heads/$YOUR_BRANCH"; then
        git checkout "$YOUR_BRANCH"
    else
        echo "创建新分支: $YOUR_BRANCH 基于 upstream/$UPSTREAM_BRANCH"
        if ! git checkout -b "$YOUR_BRANCH" "upstream/$UPSTREAM_BRANCH"; then
            echo "创建分支失败"
            if [ "$TASK_TYPE" = "luci" ]; then
                LUCI_FAILED_TASKS+=("$REPO_DIR (create branch)")
            else
                CORE_FAILED_TASKS+=("$REPO_DIR (create branch)")
            fi
            cd ..
            return 1
        fi
    fi

    # 合并上游分支（谨慎使用 -Xtheirs!）
    echo "合并上游分支: upstream/$UPSTREAM_BRANCH 到 $YOUR_BRANCH"
    if ! git merge "upstream/$UPSTREAM_BRANCH" --no-edit -Xtheirs; then
        echo "合并冲突！请手动解决: $REPO_DIR"
        git status
        if [ "$TASK_TYPE" = "luci" ]; then
            LUCI_FAILED_TASKS+=("$REPO_DIR (merge)")
        else
            CORE_FAILED_TASKS+=("$REPO_DIR (merge)")
        fi
        cd ..
        return 1
    fi

    # 推送到远程仓库
    echo "推送分支: $YOUR_BRANCH 到 origin"
    if ! git push "https://${GH_TOKEN}@github.com/liudf0716/${REPO_DIR}.git" "$YOUR_BRANCH"; then
        echo "推送失败: $REPO_DIR"
        if [ "$TASK_TYPE" = "luci" ]; then
            LUCI_FAILED_TASKS+=("$REPO_DIR (push)")
        else
            CORE_FAILED_TASKS+=("$REPO_DIR (push)")
        fi
        cd ..
        return 1
    fi

    cd ..
    return 0
}

# 检查 GitHub Token
if [ -z "$GH_TOKEN" ]; then
    echo "错误: 未设置 GH_TOKEN 环境变量"
    exit 1
fi

# 主流程 - 核心仓库同步（必须成功）
echo "========================================="
echo "第一阶段: 同步核心仓库 (chawrt, packages)"
echo "========================================="
for REPO_INFO in "${CORE_REPOS[@]}"; do
    if ! sync_repo "$REPO_INFO"; then
        IFS='|' read -r _ _ REPO_DIR _ <<< "$REPO_INFO"
        CORE_FAILED_TASKS+=("$REPO_DIR (repo sync)")
    fi
done

echo "同步核心分支..."
for BRANCH_INFO in "${CORE_CHAWRT_BRANCH[@]}"; do
    if ! sync_chawrt_branch "$BRANCH_INFO" "core"; then
        IFS='|' read -r REPO_DIR _ _ <<< "$BRANCH_INFO"
        CORE_FAILED_TASKS+=("$REPO_DIR (branch sync)")
    fi
done

# 可选：同步核心 24.10 分支
echo "同步核心 24.10 分支..."
for BRANCH_INFO in "${CORE_CHAWRT_24_10_BRANCH[@]}"; do
    if ! sync_chawrt_branch "$BRANCH_INFO" "core"; then
        IFS='|' read -r REPO_DIR _ _ <<< "$BRANCH_INFO"
        CORE_FAILED_TASKS+=("$REPO_DIR (24.10 branch sync)")
    fi
done

# 检查核心任务是否成功
if [ ${#CORE_FAILED_TASKS[@]} -ne 0 ]; then
    echo "========================================="
    echo "核心任务失败，停止执行！"
    echo "失败的核心任务:"
    printf -- "- %s\n" "${CORE_FAILED_TASKS[@]}"
    echo "========================================="
    exit 1
else
    echo "========================================="
    echo "核心任务全部成功完成！"
    echo "========================================="
fi

# 第二阶段 - Luci仓库同步（允许失败）
echo ""
echo "========================================="
echo "第二阶段: 同步Luci仓库 (允许失败)"
echo "========================================="
for REPO_INFO in "${LUCI_REPOS[@]}"; do
    if ! safe_sync_repo "$REPO_INFO"; then
        IFS='|' read -r _ _ REPO_DIR _ <<< "$REPO_INFO"
        LUCI_FAILED_TASKS+=("$REPO_DIR (repo sync)")
    fi
done

echo "同步Luci分支..."
for BRANCH_INFO in "${LUCI_CHAWRT_BRANCH[@]}"; do
    if ! safe_sync_chawrt_branch "$BRANCH_INFO"; then
        IFS='|' read -r REPO_DIR _ _ <<< "$BRANCH_INFO"
        LUCI_FAILED_TASKS+=("$REPO_DIR (branch sync)")
    fi
done

# 同步Luci 24.10 分支
echo "同步Luci 24.10 分支..."
for BRANCH_INFO in "${LUCI_CHAWRT_24_10_BRANCH[@]}"; do
    if ! safe_sync_chawrt_branch "$BRANCH_INFO"; then
        IFS='|' read -r REPO_DIR _ _ <<< "$BRANCH_INFO"
        LUCI_FAILED_TASKS+=("$REPO_DIR (24.10 branch sync)")
    fi
done

# 输出最终结果
echo ""
echo "========================================="
echo "同步任务完成总结"
echo "========================================="

if [ ${#LUCI_FAILED_TASKS[@]} -ne 0 ]; then
    echo "Luci相关任务失败 (不影响核心功能):"
    printf -- "- %s\n" "${LUCI_FAILED_TASKS[@]}"
    echo ""
    echo "核心任务: ✅ 成功"
    echo "Luci任务: ❌ 部分失败 (可忽略)"
    echo ""
    echo "建议: 可以手动处理Luci相关问题，或稍后重新运行脚本"
else
    echo "🎉 所有任务全部成功完成！"
fi

echo "========================================="