# ikshell 多会话使用指南

ikshell 通过 **tmux** 实现多窗口会话支持，无需修改应用架构。

## 快速开始

### 1. 安装 tmux

```sh
ikpkg tmux
```

### 2. 启动 tmux

```sh
tmux
```

现在你进入了 tmux 环境，底部会显示状态栏。

## 基本操作

### 创建和管理窗口

所有 tmux 命令需要先按 **前缀键** `Ctrl+b`，然后按功能键：

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+b` `c` | 创建新窗口 |
| `Ctrl+b` `n` | 切换到下一个窗口 |
| `Ctrl+b` `p` | 切换到上一个窗口 |
| `Ctrl+b` `0-9` | 切换到指定编号窗口 |
| `Ctrl+b` `,` | 重命名当前窗口 |
| `Ctrl+b` `&` | 关闭当前窗口 |

### 分屏操作

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+b` `%` | 垂直分屏 |
| `Ctrl+b` `"` | 水平分屏 |
| `Ctrl+b` `方向键` | 在分屏间切换 |
| `Ctrl+b` `x` | 关闭当前面板 |

### 会话管理

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+b` `d` | 脱离会话（后台运行） |
| `tmux attach` | 重新连接会话 |
| `tmux ls` | 列出所有会话 |
| `tmux new -s name` | 创建命名会话 |
| `tmux attach -t name` | 连接到指定会话 |

## 使用场景

### 场景1：同时运行多个任务

```sh
# 窗口0：编辑代码
vim app.py

# Ctrl+b c 创建窗口1：运行程序
python app.py

# Ctrl+b c 创建窗口2：查看日志
tail -f app.log

# Ctrl+b 0/1/2 快速切换
```

### 场景2：后台任务

```sh
# 启动长时间运行的任务
npm run build

# Ctrl+b d 脱离会话
# 关闭 ikshell 应用也不影响任务继续运行

# 下次打开应用后
tmux attach  # 重新连接，任务仍在运行
```

### 场景3：开发环境

```sh
# 创建命名会话
tmux new -s dev

# 窗口0：编辑器
vim src/

# Ctrl+b c 窗口1：编译
ikpkg c
gcc -o app main.c

# Ctrl+b c 窗口2：测试
./app

# Ctrl+b c 窗口3：git操作
git status
```

## 配置优化

创建 `~/.tmux.conf` 自定义配置：

```sh
cat > ~/.tmux.conf <<'EOF'
# 启用鼠标支持
set -g mouse on

# 256色支持
set -g default-terminal "screen-256color"

# 状态栏样式
set -g status-style bg=blue,fg=white
set -g status-right "%H:%M %d-%b"

# 窗口索引从1开始
set -g base-index 1
set -g pane-base-index 1

# 快速重载配置
bind r source-file ~/.tmux.conf \; display "配置已重载"
EOF
```

重新启动 tmux 或按 `Ctrl+b` `:` 输入 `source-file ~/.tmux.conf` 加载配置。

## 替代方案：screen

如果你更喜欢 screen：

```sh
ikpkg screen
screen
```

screen 快捷键（前缀 `Ctrl+a`）：
- `Ctrl+a` `c` - 创建窗口
- `Ctrl+a` `n/p` - 切换窗口
- `Ctrl+a` `d` - 脱离会话
- `screen -r` - 重新连接

## 技巧

### 1. 自动启动 tmux

编辑 `~/.profile`：

```sh
if command -v tmux >/dev/null 2>&1 && [ -z "$TMUX" ]; then
    tmux attach || tmux new
fi
```

### 2. 命名窗口提高效率

```sh
# Ctrl+b , 输入窗口名称
编辑器
编译
测试
```

状态栏显示窗口名，更容易识别。

### 3. 复制模式

在 tmux 中选择和复制文本：

1. `Ctrl+b` `[` 进入复制模式
2. 用方向键移动光标
3. 按空格开始选择
4. 按回车复制
5. `Ctrl+b` `]` 粘贴

## 常见问题

**Q: tmux 状态栏显示异常？**
A: 在设置中调整字体大小，确保终端宽度足够。

**Q: 如何退出 tmux？**
A: 关闭所有窗口（输入 `exit` 或 `Ctrl+d`），或 `Ctrl+b` `&` 强制关闭。

**Q: 会话能保持多久？**
A: 只要 ikshell 应用在运行，会话就持续存在。关闭应用会终止所有会话。

**Q: 能在多个 iPad 上共享会话吗？**
A: 不能，每个 ikshell 实例独立运行。

## 更多资源

- tmux 官方文档: `man tmux`
- 快速参考: `tmux list-keys`
- ikshell 仓库: https://github.com/your-repo/ikshell
