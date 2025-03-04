#!/bin/bash

# 配置区域：定义仓库和分支映射（使用 | 分隔字段避免空格冲突）
REPOS=(
    "https://github.com/openwrt/openwrt.git|https://github.com/liudf0716/chawrt.git|chawrt|main"
    "https://github.com/openwrt/packages.git|https://github.com/liudf0716/packages.git|packages|master"
    "https://github.com/openwrt/luci.git|https://github.com/liudf0716/luci.git|luci|master"
)

CHAWRT_BRANCH=(
    "chawrt|chawrt-main|main"          # REPO_DIR|YOUR_BRANCH|UPSTREAM_BRANCH
    "packages|chawrt/master|master"
)

CHAWRT_24_10_BRANCH=(
    "chawrt|24.10|openwrt-24.10"
    "packages|chawrt/24.10|openwrt-24.10"
)

# 优雅处理中断
trap 'echo "脚本被中断"; exit 1' SIGINT

FAILED_TASKS=()

# 同步仓库函数
sync_repo() {
    IFS='|' read -r UPSTREAM_REPO FORK_REPO REPO_DIR BRANCH <<< "$1"
    
    echo "同步仓库: $REPO_DIR (分支: $BRANCH)"

    # 克隆仓库（如果不存在）
    if [ ! -d "$REPO_DIR" ]; then
        echo "克隆仓库: $FORK_REPO"
        git clone "$FORK_REPO" "$REPO_DIR" || { 
            echo "克隆失败: $REPO_DIR"
            FAILED_TASKS+=("$REPO_DIR (clone)")
            return
        }
    fi

    cd "$REPO_DIR" || { 
        echo "无法进入目录: $REPO_DIR"
        FAILED_TASKS+=("$REPO_DIR (cd)")
        return
    }

    # 添加上游远程仓库
    if ! git remote | grep -q upstream; then
        git remote add upstream "$UPSTREAM_REPO" || {
            echo "添加上游仓库失败: $UPSTREAM_REPO"
            FAILED_TASKS+=("$REPO_DIR (add upstream)")
            cd ..
            return
        }
    fi

    # 获取最新代码
    git fetch --all || {
        echo "拉取代码失败: $REPO_DIR"
        FAILED_TASKS+=("$REPO_DIR (fetch)")
        cd ..
        return
    }

    cd ..
    echo "成功同步仓库: $REPO_DIR"
}

# 同步分支函数
sync_chawrt_branch() {
    IFS='|' read -r REPO_DIR YOUR_BRANCH UPSTREAM_BRANCH <<< "$1"

    echo "同步分支: 仓库=$REPO_DIR, 目标分支=$YOUR_BRANCH, 上游分支=$UPSTREAM_BRANCH"

    if [ ! -d "$REPO_DIR" ]; then
        echo "仓库不存在: $REPO_DIR"
        FAILED_TASKS+=("$REPO_DIR (not exist)")
        return
    fi

    cd "$REPO_DIR" || {
        echo "无法进入目录: $REPO_DIR"
        FAILED_TASKS+=("$REPO_DIR (cd)")
        return
    }

    # 切换到目标分支（若不存在则基于上游创建）
    if git show-ref --verify --quiet "refs/heads/$YOUR_BRANCH"; then
        git checkout "$YOUR_BRANCH"
    else
        echo "创建新分支: $YOUR_BRANCH 基于 upstream/$UPSTREAM_BRANCH"
        git checkout -b "$YOUR_BRANCH" "upstream/$UPSTREAM_BRANCH" || {
            echo "创建分支失败"
            FAILED_TASKS+=("$REPO_DIR (create branch)")
            cd ..
            return
        }
    fi

    # 合并上游分支（谨慎使用 -Xtheirs!）
    echo "合并上游分支: upstream/$UPSTREAM_BRANCH 到 $YOUR_BRANCH"
    git merge "upstream/$UPSTREAM_BRANCH" --no-edit -Xtheirs || {
        echo "合并冲突！请手动解决: $REPO_DIR"
        git status
        FAILED_TASKS+=("$REPO_DIR (merge)")
        cd ..
        return
    }

    # 推送到远程仓库
    echo "推送分支: $YOUR_BRANCH 到 origin"
    git push "https://${GH_TOKEN}@github.com/liudf0716/${REPO_DIR}.git" "$YOUR_BRANCH" || {
        echo "推送失败: $REPO_DIR"
        FAILED_TASKS+=("$REPO_DIR (push)")
        cd ..
        return
    }

    cd ..
}

# 检查 GitHub Token
if [ -z "$GH_TOKEN" ]; then
    echo "错误: 未设置 GH_TOKEN 环境变量"
    exit 1
fi

# 主流程
echo "开始同步所有仓库..."
for REPO_INFO in "${REPOS[@]}"; do
    sync_repo "$REPO_INFO"
done

echo "同步 chawrt 分支..."
for BRANCH_INFO in "${CHAWRT_BRANCH[@]}"; do
    sync_chawrt_branch "$BRANCH_INFO"
done

# 可选：同步 24.10 分支
# for BRANCH_INFO in "${CHAWRT_24_10_BRANCH[@]}"; do
#     sync_chawrt_branch "$BRANCH_INFO"
# done

# 输出失败任务
if [ ${#FAILED_TASKS[@]} -ne 0 ]; then
    echo "以下任务失败:"
    printf -- "- %s\n" "${FAILED_TASKS[@]}"
    exit 1
else
    echo "所有任务成功完成！"
fi