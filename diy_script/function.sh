#!/bin/bash

# 打包toolchain目录
if [[ "$REBUILD_TOOLCHAIN" = 'true' ]]; then
    cd $OPENWRT_PATH
    sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    if [[ -d ".ccache" && -n "$(ls -A .ccache)" ]]; then
        echo "🔍 缓存目录内容:"
        ls -Alh .ccache
        ccache_dir=".ccache"
    fi
    echo "📦 工具链目录大小:"
    du -h --max-depth=1 ./staging_dir
    tar -I zstdmt -cf "$GITHUB_WORKSPACE/output/$CACHE_NAME.tzst" staging_dir/host* staging_dir/tool* $ccache_dir
    echo "📁 输出目录内容:"
    ls -lh "$GITHUB_WORKSPACE/output"
    if [[ ! -e "$GITHUB_WORKSPACE/output/$CACHE_NAME.tzst" ]]; then
        echo "❌ 工具链打包失败!"
        exit 1
    fi
    echo "✅ 工具链打包完成"
    exit 0
fi

# 创建toolchain缓存保存目录
[ -d "$GITHUB_WORKSPACE/output" ] || mkdir "$GITHUB_WORKSPACE/output"

# 颜色输出
color() {
    case "$1" in
        cr) echo -e "\e[1;31m$2\e[0m" ;;
        cg) echo -e "\e[1;32m$2\e[0m" ;;
        cy) echo -e "\e[1;33m$2\e[0m" ;;
        cb) echo -e "\e[1;34m$2\e[0m" ;;
        cp) echo -e "\e[1;35m$2\e[0m" ;;
        cc) echo -e "\e[1;36m$2\e[0m" ;;
        ch) echo -e "\e[1;41m$2\e[0m" ;;
    esac
}

# 状态显示和时间统计
status() {
    local check=$? end_time=$(date '+%H:%M:%S') total_time
    total_time="==> 用时 $[$(date +%s -d $end_time) - $(date +%s -d $begin_time)] 秒"
    [[ $total_time =~ [0-9]+ ]] || total_time=""
    if [[ $check = 0 ]]; then
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(color cy $1) [ $(color cg ✔) ] $(echo -e "\e[1m$total_time")
    else
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(color cy $1) [ $(color cr ✕) ] $(echo -e "\e[1m$total_time")
    fi
}

# 查找目录
find_dir() {
    find $1 -maxdepth 3 -type d -name "$2" -print -quit 2>/dev/null
}

# 打印信息
print_info() {
    printf "%s %-40s %s %s %s\n" "$1" "$2" "$3" "$4" "$5"
}

# 添加整个源仓库(git clone)
git_clone() {
    local repo_url branch target_dir current_dir
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    target_dir="${1:-${repo_url##*/}}"
    git clone -q $branch --depth=1 "$repo_url" "$target_dir" 2>/dev/null || {
        print_info $(color cr 拉取) "$repo_url" [ $(color cr ✖) ]
        return 1
    }
    rm -rf $target_dir/{.git*,README*.md,LICENSE}
    current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
    if [[ -d "$current_dir" ]]; then
        rm -rf "$current_dir"
        mv -f "$target_dir" "${current_dir%/*}"
        print_info $(color cg 替换) "$target_dir" [ $(color cg ✔) ]
    else
        mv -f "$target_dir" "$destination_dir"
        print_info $(color cb 添加) "$target_dir" [ $(color cb ✔) ]
    fi
}

# 添加源仓库内的指定目录
clone_dir() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    git clone -q $branch --depth=1 "$repo_url" "$temp_dir" 2>/dev/null || {
        print_info $(color cr 拉取) "$repo_url" [ $(color cr ✖) ]
        rm -rf "$temp_dir"
        return 1
    }
    local target_dir source_dir current_dir
    for target_dir in "$@"; do
        source_dir=$(find_dir "$temp_dir" "$target_dir")
        [[ -d "$source_dir" ]] || \
        source_dir=$(find "$temp_dir" -maxdepth 4 -type d -name "$target_dir" -print -quit) && \
        [[ -d "$source_dir" ]] || {
            print_info $(color cr 查找) "$target_dir" [ $(color cr ✖) ]
            continue
        }
        current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
        if [[ -d "$current_dir" ]]; then
            rm -rf "$current_dir"
            mv -f "$source_dir" "${current_dir%/*}"
            print_info $(color cg 替换) "$target_dir" [ $(color cg ✔) ]
        else
            mv -f "$source_dir" "$destination_dir"
            print_info $(color cb 添加) "$target_dir" [ $(color cb ✔) ]
        fi
    done
    rm -rf "$temp_dir"
}

# 添加源仓库内的所有子目录
clone_all() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    git clone -q $branch --depth=1 "$repo_url" "$temp_dir" 2>/dev/null || {
        print_info $(color cr 拉取) "$repo_url" [ $(color cr ✖) ]
        rm -rf "$temp_dir"
        return 1
    }
    process_dir() {
	    # 解析排除列表（!xxx）
	    local exclude_list=()
        for arg in "$@"; do
            [[ "$arg" == !* ]] && exclude_list+=("${arg:1}")
        done
        while IFS= read -r source_dir; do
            local target_dir=$(basename "$source_dir")
            # 排除目录
			for ex in "${exclude_list[@]}"; do
                if [[ "$target_dir" == "$ex" ]]; then
                    print_info $(color cr 排除) "$target_dir" [ $(color cr ✔) ]
                    continue 2
                fi
            done
            local current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
            if [[ -d "$current_dir" ]]; then
                rm -rf "$current_dir"
                mv -f "$source_dir" "${current_dir%/*}"
                print_info $(color cg 替换) "$target_dir" [ $(color cg ✔) ]
            else
                mv -f "$source_dir" "$destination_dir"
                print_info $(color cb 添加) "$target_dir" [ $(color cb ✔) ]
            fi
        done < <(find "$1" -maxdepth 1 -mindepth 1 -type d ! -name '.*')
    }
    if [[ $# -eq 0 ]]; then
        process_dir "$temp_dir"
	else
	    # 有参数 → 可能包含子目录 + 排除
        local subdirs=()
        for arg in "$@"; do
            [[ "$arg" != !* ]] && subdirs+=("$arg")
        done
        if [[ ${#subdirs[@]} -eq 0 ]]; then
		    # 只有排除参数
            process_dir "$temp_dir" "$@"
        else
		    # 指定子目录 + 排除（!xxx）
            for dir_name in "${subdirs[@]}"; do
                if [[ -d "$temp_dir/$dir_name" ]]; then
                    process_dir "$temp_dir/$dir_name" "$@"
                else
                    print_info $(color cr 目录) "$dir_name" [ $(color cr ✖) ]
                fi
            done
        fi
    fi
    rm -rf "$temp_dir"
}

# 源仓库与分支
SOURCE_REPO=$(basename $REPO_URL)
echo "SOURCE_REPO=$SOURCE_REPO" >>$GITHUB_ENV

# 平台架构
TARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_BOARD/{print $2}' .config)
SUBTARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_SUBTARGET/{print $2}' .config)
DEVICE_TARGET=$TARGET_NAME-$SUBTARGET_NAME
echo "DEVICE_TARGET=$DEVICE_TARGET" >>$GITHUB_ENV

# 内核版本
KERNEL=$(grep -oP 'KERNEL_PATCHVER:=\K[\d\.]+' "target/linux/$TARGET_NAME/Makefile")
KERNEL_FILE="include/kernel-$KERNEL"
[ -e "$KERNEL_FILE" ] || KERNEL_FILE="target/linux/generic/kernel-$KERNEL"
KERNEL_VERSION=$(grep -oP 'LINUX_KERNEL_HASH-\K[\d\.]+' "$KERNEL_FILE")
echo "KERNEL_VERSION=$KERNEL_VERSION" >>$GITHUB_ENV

# toolchain缓存文件名
TOOLS_HASH=$(git log --pretty=tformat:"%h" -n1 tools toolchain)
CACHE_NAME="$SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-cache-$TOOLS_HASH"
echo "CACHE_NAME=$CACHE_NAME" >>$GITHUB_ENV

# 下载并部署toolchain
if [[ "$TOOLCHAIN" = 'true' ]]; then
    #cache_xa=$(curl -sL "https://api.github.com/repos/$GITHUB_REPOSITORY/releases" | awk -F '"' '/download_url/{print $4}' | grep "$CACHE_NAME")
    cache_xa="https://github.com/$GITHUB_REPOSITORY/releases/download/toolchain-cache/$CACHE_NAME.tzst"
	cache_xc=$(curl -sL "https://api.github.com/repos/JejzOne/toolchain-cache/releases" | awk -F '"' '/download_url/{print $4}' | grep "$CACHE_NAME")
    #if [[ $cache_xa || $cache_xc ]]; then
    if curl -Isf $cache_xa >/dev/null 2>&1 || [ $cache_xc ]; then
        begin_time=$(date '+%H:%M:%S')
        curl -Isf $cache_xa >/dev/null 2>&1 && wget -qc -t=3 $cache_xa || wget -qc -t=3 $cache_xc
        [ -e *.tzst ]; status "下载toolchain缓存文件"
        [ -e *.tzst ] && {
            begin_time=$(date '+%H:%M:%S')
            tar -I unzstd -xf *.tzst || tar -xf *.tzst
           # [ $cache_xa ] || (cp *.tzst $GITHUB_WORKSPACE/output && echo "OUTPUT_RELEASE=true" >>$GITHUB_ENV)
            sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
            [ -d staging_dir ]; status "部署toolchain编译缓存"
        }
    else
        echo -e "$(color ch 下载toolchain缓存文件)                         [ $(color cr ✕) ]"
        echo "CANCEL_TOOLCHAIN=true" >>$GITHUB_ENV
    fi
else
    echo -e "$(color ch 使用toolchain缓存文件)                         [ $(color cr ✕) ]"
    echo "CANCEL_TOOLCHAIN=true" >>$GITHUB_ENV
fi

# 创建插件保存目录
destination_dir="package/A"
[ -d "$destination_dir" ] || mkdir -p "$destination_dir"

if [ -z "$DEVICE_TARGET" ] || [ "$DEVICE_TARGET" == "-" ]; then
  echo -e "$(color cy "📊 当前编译信息")"
  echo "========================================"
  echo "🔷 固件源码: $(color cc "$SOURCE_REPO")"
  echo "🔷 源码分支: $(color cc "$REPO_BRANCH")"
  echo "========================================"
else
  echo -e "$(color cy "📊 当前编译信息")"
  echo "========================================"
  echo "🔷 固件源码: $(color cc "$SOURCE_REPO")"
  echo "🔷 源码分支: $(color cc "$REPO_BRANCH")"
  echo "🔷 目标设备: $(color cc "$DEVICE_TARGET")"
  echo "🔷 内核版本: $(color cc "$KERNEL_VERSION")"
  echo "========================================"
fi
