#!/bin/sh
# tmux 快捷提示（仅在交互式 shell 首次登录时显示）

if [ -t 0 ] && [ -z "$TMUX" ] && [ -z "$TMUX_TIPS_SHOWN" ]; then
    export TMUX_TIPS_SHOWN=1
    cat <<'EOF'

💡 多窗口会话支持:
   ikpkg tmux        # 安装 tmux
   tmux              # 启动多会话环境

   tmux 常用快捷键 (按 Ctrl+b 后):
   c     创建新窗口
   n/p   切换到下一个/上一个窗口
   0-9   切换到指定窗口
   d     脱离会话（后台运行）

   tmux attach      # 重新连接会话

EOF
fi
