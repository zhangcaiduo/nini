#!/bin/bash

# ==========================================
# NINI 实战派单词本 - 极简一键安装脚本
# ==========================================

# 管道执行时 stdin 被占用，强制从终端读取用户输入
exec </dev/tty

GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
DIM="\033[2m"
RESET="\033[0m"

clear
echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN}      NINI 极简实战单词本 - 一键部署向导${RESET}"
echo -e "${CYAN}====================================================${RESET}"
echo ""

# 1. 交互式配置
read -p "👉 请输入你想使用的端口 (默认 8888): " PORT
PORT=${PORT:-8888}

echo -e "${DIM}支持各大兼容 OpenAI 格式的 API (如 DeepSeek, Groq, 各种中转等)${RESET}"
read -p "👉 API 地址 (默认 https://api.deepseek.com/v1/chat/completions): " API_URL
API_URL=${API_URL:-"https://api.deepseek.com/v1/chat/completions"}

read -p "👉 模型名称 (默认 deepseek-chat): " MODEL_NAME
MODEL_NAME=${MODEL_NAME:-"deepseek-chat"}

read -p "👉 API KEY: " API_KEY
if [ -z "$API_KEY" ]; then
    echo -e "${YELLOW}⚠️ API KEY 不能为空，请重新运行脚本！${RESET}"
    exit 1
fi

# 2. 创建目录
INSTALL_DIR="$HOME/nini_vocab"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 3. 写入配置文件
cat << EOF > config.json
{
    "port": $PORT,
    "api_url": "$API_URL",
    "model": "$MODEL_NAME",
    "api_key": "$API_KEY"
}
EOF

# 4. 写入零依赖 Python 后端 (server.py)
cat << 'PYEOF' > server.py
import json, sqlite3, urllib.request, os
from http.server import BaseHTTPRequestHandler, HTTPServer

# 加载配置
with open('config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

API_KEY = config.get("api_key")
API_URL = config.get("api_url")
MODEL = config.get("model")
PORT = int(config.get("port", 8888))

# 初始化数据库
def init_db():
    conn = sqlite3.connect('vocab.db')
    conn.execute('CREATE TABLE IF NOT EXISTS words (id INTEGER PRIMARY KEY AUTOINCREMENT, word TEXT UNIQUE, data TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    conn.close()

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            with open('index.html', 'rb') as f:
                self.wfile.write(f.read())
        elif self.path == '/api/words':
            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            conn = sqlite3.connect('vocab.db')
            c = conn.cursor()
            c.execute('SELECT data FROM words ORDER BY id DESC')
            words = [json.loads(r[0]) for r in c.fetchall()]
            conn.close()
            self.wfile.write(json.dumps(words).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/api/generate':
            length = int(self.headers.get('content-length', 0))
            body = json.loads(self.rfile.read(length))
            word = body.get('word', '').strip()

            if not word:
                self.send_response(400)
                self.end_headers()
                return

            # AI 系统提示词 (实战派毒舌调教)
            sys_prompt = """
            你是一个精通英语俚语、游戏黑话和社媒文化的老师。
            返回JSON格式：{"word":"单词","phonetic":"音标","meaning":"精确中文释义","examples":[{"type":"场景","en":"英文造句","zh":"中文翻译"}]}
            必须造3个极具实战气息的句子：
            1. Gaming (游戏互喷或黑话)
            2. Twitter (推特抬杠、讽刺、对线)
            3. Tech (极客、程序员吐槽)
            """
            
            payload = {
                "model": MODEL,
                "messages": [
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": f"给我单词 '{word}' 的实战解析"}
                ],
                "response_format": {"type": "json_object"}
            }

            headers = {
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json"
            }
            req = urllib.request.Request(API_URL, data=json.dumps(payload).encode('utf-8'), headers=headers)
            
            try:
                resp = urllib.request.urlopen(req, timeout=30)
                result = json.loads(resp.read().decode('utf-8'))
                ai_content = json.loads(result['choices'][0]['message']['content'])
                
                # 存入数据库
                conn = sqlite3.connect('vocab.db')
                conn.execute('INSERT OR REPLACE INTO words (word, data) VALUES (?, ?)', (ai_content['word'], json.dumps(ai_content)))
                conn.commit()
                conn.close()
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json; charset=utf-8')
                self.end_headers()
                self.wfile.write(json.dumps(ai_content).encode('utf-8'))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))

init_db()
print(f"Server running on port {PORT}...")
HTTPServer(('0.0.0.0', PORT), RequestHandler).serve_forever()
PYEOF

# 5. 写入纯黑白单页前端 (index.html)
cat << 'HTMLEOF' > index.html
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>NINI Vocab</title>
    <style>
        /* 极简黑白风 CSS */
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
        body { background-color: #f5f5f5; color: #111; display: flex; justify-content: center; height: 100vh; overflow: hidden; }
        .app-container { width: 100%; max-width: 480px; background: #fff; height: 100%; position: relative; box-shadow: 0 0 20px rgba(0,0,0,0.05); display: flex; flex-direction: column; }
        
        header { padding: 20px; text-align: center; border-bottom: 1px solid #eee; font-weight: bold; font-size: 1.2rem; background: #fff; z-index: 10; }
        .content { flex: 1; overflow-y: auto; padding: 20px; padding-bottom: 80px; }
        
        /* 列表样式 */
        .word-item { padding: 15px; border: 1px solid #eee; border-radius: 8px; margin-bottom: 12px; cursor: pointer; transition: 0.2s; background: #fafafa; }
        .word-item:hover { border-color: #111; }
        .word-title { font-size: 1.2rem; font-weight: bold; margin-bottom: 5px; display: flex; justify-content: space-between;}
        .word-meaning { font-size: 0.9rem; color: #666; }

        /* 详情页样式 */
        .detail-view { display: none; position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: #fff; z-index: 20; flex-direction: column; }
        .detail-header { padding: 20px; border-bottom: 1px solid #eee; display: flex; align-items: center; }
        .back-btn { font-size: 1.5rem; cursor: pointer; margin-right: 15px; }
        .detail-content { padding: 20px; overflow-y: auto; flex: 1; }
        .d-word { font-size: 2rem; font-weight: bold; }
        .d-phonetic { color: #666; margin: 10px 0; display: inline-block; padding: 5px 10px; background: #f0f0f0; border-radius: 20px; font-size: 0.9rem; cursor: pointer;}
        .d-meaning { font-size: 1.1rem; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 1px solid #eee; }
        .example-box { margin-bottom: 20px; padding: 15px; border-left: 3px solid #111; background: #f9f9f9; }
        .ex-type { font-size: 0.8rem; font-weight: bold; text-transform: uppercase; color: #888; margin-bottom: 5px; }
        .ex-en { font-size: 1.05rem; margin-bottom: 8px; cursor: pointer; }
        .ex-zh { font-size: 0.9rem; color: #555; }

        /* 浮动添加按钮 & 弹窗 */
        .fab { position: absolute; bottom: 30px; right: 30px; width: 60px; height: 60px; background: #111; color: #fff; border-radius: 50%; display: flex; justify-content: center; align-items: center; font-size: 2rem; cursor: pointer; box-shadow: 0 4px 10px rgba(0,0,0,0.2); z-index: 15; }
        .modal-overlay { display: none; position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 30; justify-content: center; align-items: flex-end; }
        .modal { background: #fff; width: 100%; padding: 30px 20px; border-radius: 20px 20px 0 0; transform: translateY(100%); transition: transform 0.3s ease; }
        .modal.active { transform: translateY(0); }
        .modal h3 { margin-bottom: 15px; }
        .modal input { width: 100%; padding: 15px; border: 1px solid #ccc; border-radius: 8px; font-size: 1.1rem; margin-bottom: 15px; }
        .modal button { width: 100%; padding: 15px; background: #111; color: #fff; border: none; border-radius: 8px; font-size: 1.1rem; cursor: pointer; font-weight: bold; }
        .modal button:disabled { background: #ccc; }
        
        /* 播放图标 */
        .play-icon { margin-left: 8px; font-size: 1.1rem; }
    </style>
</head>
<body>

<div class="app-container">
    <header>NINI Vocab</header>
    <div class="content" id="list-view">
        </div>

    <div class="detail-view" id="detail-view">
        <div class="detail-header">
            <div class="back-btn" onclick="closeDetail()">←</div>
            <div style="font-weight: bold;">Details</div>
        </div>
        <div class="detail-content" id="detail-content">
            </div>
    </div>

    <div class="fab" onclick="openModal()">+</div>

    <div class="modal-overlay" id="modal-overlay" onclick="closeModal(event)">
        <div class="modal" id="modal" onclick="event.stopPropagation()">
            <h3>Add New Word</h3>
            <input type="text" id="word-input" placeholder="输入你想记录的单词..." autocomplete="off">
            <button id="submit-btn" onclick="generateWord()">AI 组局造句</button>
        </div>
    </div>
</div>

<script>
    let wordsData = [];

    // 语音朗读功能 (Web Speech API)
    function speakText(text) {
        const utterance = new SpeechSynthesisUtterance(text);
        utterance.lang = 'en-US';
        utterance.rate = 0.9; // 语速稍微放慢点适合学习
        window.speechSynthesis.speak(utterance);
    }

    // 初始化获取列表
    async function fetchWords() {
        const res = await fetch('/api/words');
        wordsData = await res.json();
        renderList();
    }

    function renderList() {
        const listDiv = document.getElementById('list-view');
        listDiv.innerHTML = wordsData.map((item, index) => `
            <div class="word-item" onclick="showDetail(${index})">
                <div class="word-title">${item.word}</div>
                <div class="word-meaning">${item.meaning}</div>
            </div>
        `).join('');
    }

    function showDetail(index) {
        const item = wordsData[index];
        const content = document.getElementById('detail-content');
        
        let examplesHtml = item.examples.map(ex => `
            <div class="example-box">
                <div class="ex-type">${ex.type}</div>
                <div class="ex-en" onclick="speakText('${ex.en.replace(/'/g, "\\'")}')">${ex.en} <span class="play-icon">🔊</span></div>
                <div class="ex-zh">${ex.zh}</div>
            </div>
        `).join('');

        content.innerHTML = `
            <div class="d-word">${item.word}</div>
            <div class="d-phonetic" onclick="speakText('${item.word}')">${item.phonetic} <span class="play-icon">🔊</span></div>
            <div class="d-meaning">${item.meaning}</div>
            ${examplesHtml}
        `;
        document.getElementById('detail-view').style.display = 'flex';
    }

    function closeDetail() {
        document.getElementById('detail-view').style.display = 'none';
    }

    function openModal() {
        document.getElementById('modal-overlay').style.display = 'flex';
        setTimeout(() => document.getElementById('modal').classList.add('active'), 10);
        document.getElementById('word-input').focus();
    }

    function closeModal(e) {
        document.getElementById('modal').classList.remove('active');
        setTimeout(() => document.getElementById('modal-overlay').style.display = 'none', 300);
    }

    async function generateWord() {
        const word = document.getElementById('word-input').value;
        const btn = document.getElementById('submit-btn');
        if(!word) return;

        btn.disabled = true;
        btn.innerText = "AI 思考中 (毒舌模式开启)...";

        try {
            const res = await fetch('/api/generate', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({word})
            });
            
            if(res.ok) {
                document.getElementById('word-input').value = '';
                closeModal();
                fetchWords(); // 刷新列表
            } else {
                const err = await res.json();
                alert('出错了: ' + (err.error || '未知错误'));
            }
        } catch(e) {
            alert('网络错误: ' + e);
        }

        btn.disabled = false;
        btn.innerText = "AI 组局造句";
    }

    fetchWords();
</script>
</body>
</html>
HTMLEOF

# 6. 配置 Systemd 后台服务
echo -e "${DIM}正在配置系统守护进程...${RESET}"

cat << EOF | sudo tee /etc/systemd/system/nini.service > /dev/null
[Unit]
Description=Nini Vocab Dash Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 7. 启动服务
sudo systemctl daemon-reload
sudo systemctl enable nini
sudo systemctl restart nini

# 8. 获取 IP 并完成
IP=$(curl -s -4 ifconfig.me || echo "你的服务器IP")

echo ""
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}  ✅ NINI 单词本 部署完成！${RESET}"
echo -e "${GREEN}====================================================${RESET}"
echo -e "  💻 浏览器访问地址: ${CYAN}http://${IP}:${PORT}${RESET}"
echo -e "  💡 提示："
echo -e "    - 查看运行日志: ${YELLOW}sudo journalctl -u nini -f${RESET}"
echo -e "    - 重启后台服务: ${YELLOW}sudo systemctl restart nini${RESET}"
echo -e "    - 数据保存在: ${DIM}$INSTALL_DIR/vocab.db${RESET}"
echo ""
