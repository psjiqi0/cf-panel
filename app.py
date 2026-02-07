import os
import time
import json
import base64
import subprocess
import re
import secrets
from pathlib import Path
from functools import wraps
from flask import Flask, render_template, request, jsonify, session, redirect, url_for
from flask_session import Session
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.security import generate_password_hash, check_password_hash
import requests

MAIN_DIR = "/etc/cf_pro"
LOG_DIR = os.path.join(MAIN_DIR, "logs")
API_CONFIG_DIR = os.path.join(MAIN_DIR, "configs")
CREDS_DIR = os.path.join(MAIN_DIR, "creds")
YML_DIR = os.path.join(MAIN_DIR, "yml")
XRAY_DIR = os.path.join(MAIN_DIR, "xray")
CF_BIN = os.path.join(MAIN_DIR, "cloudflared")
XR_BIN = os.path.join(XRAY_DIR, "xray")
USERS_FILE = os.path.join(MAIN_DIR, "users.json")

os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(API_CONFIG_DIR, exist_ok=True)
os.makedirs(CREDS_DIR, exist_ok=True)
os.makedirs(YML_DIR, exist_ok=True)
os.makedirs(XRAY_DIR, exist_ok=True)

app = Flask(__name__, template_folder="./templates", static_folder="./static")
app.config['SECRET_KEY'] = os.environ.get('FLASK_SECRET_KEY', secrets.token_hex(32))
app.config['SESSION_TYPE'] = 'filesystem'
app.config['SESSION_COOKIE_SECURE'] = True
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'

Session(app)
limiter = Limiter(app=app, key_func=get_remote_address, default_limits=["200 per day", "50 per hour"])


def init_users():
    """初始化默认用户（如果文件不存在）"""
    if not os.path.exists(USERS_FILE):
        default_pass = 'admin123'
        users = {
            'admin': {
                'password_hash': generate_password_hash(default_pass),
                'created': time.time()
            }
        }
        with open(USERS_FILE, 'w') as f:
            json.dump(users, f)
        os.chmod(USERS_FILE, 0o600)
        print(f"[INIT] Created default admin user with password: {default_pass}")


def get_users():
    """读取用户文件"""
    if not os.path.exists(USERS_FILE):
        return {}
    try:
        with open(USERS_FILE, 'r') as f:
            return json.load(f)
    except Exception:
        return {}


def save_users(users):
    """保存用户文件"""
    with open(USERS_FILE, 'w') as f:
        json.dump(users, f)
    os.chmod(USERS_FILE, 0o600)


def require_login(f):
    """装饰器：要求登录"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'username' not in session:
            if request.method == 'POST' or request.path.startswith('/api/'):
                return jsonify({'ok': False, 'error': 'unauthorized'}), 401
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function


def check_bin(path):
    return os.path.isfile(path) and os.access(path, os.X_OK)


init_users()


@app.route('/login', methods=['GET', 'POST'])
@limiter.limit("5 per minute")
def login():
    if request.method == 'POST':
        data = request.json or {}
        username = data.get('username')
        password = data.get('password')
        users = get_users()
        
        if username in users and check_password_hash(users[username]['password_hash'], password):
            session['username'] = username
            return jsonify({'ok': True, 'message': 'login success'})
        else:
            return jsonify({'ok': False, 'error': 'invalid username or password'}), 401
    return render_template('login.html')


@app.route('/logout', methods=['POST'])
def logout():
    session.clear()
    return jsonify({'ok': True})


@app.route('/api/change_password', methods=['POST'])
@require_login
@limiter.limit("10 per hour")
def change_password():
    data = request.json or {}
    username = session.get('username')
    old_pass = data.get('old_password')
    new_pass = data.get('new_password')
    
    if not (old_pass and new_pass) or len(new_pass) < 8:
        return jsonify({'ok': False, 'error': 'password must be at least 8 characters'}), 400
    
    users = get_users()
    if not check_password_hash(users[username]['password_hash'], old_pass):
        return jsonify({'ok': False, 'error': 'old password incorrect'}), 401
    
    users[username]['password_hash'] = generate_password_hash(new_pass)
    save_users(users)
    return jsonify({'ok': True, 'message': 'password changed'})


@app.route('/')
@require_login
def index():
    return render_template('index.html', username=session.get('username'))


@app.route('/api/check', methods=['GET'])
@require_login
def api_check():
    return jsonify({
        'cloudflared': check_bin(CF_BIN),
        'xray': check_bin(XR_BIN),
        'main_dir': MAIN_DIR
    })


@app.route('/api/temp_tunnel', methods=['POST'])
@require_login
def temp_tunnel():
    data = request.json or {}
    port = str(data.get('port', '8080'))
    logfile = os.path.join(LOG_DIR, 'temp.log')
    try:
        if os.path.exists(logfile):
            os.remove(logfile)
    except Exception:
        pass

    if not check_bin(CF_BIN):
        return jsonify({'ok': False, 'error': 'cloudflared not found at ' + CF_BIN}), 400

    cmd = [CF_BIN, 'tunnel', '--url', f'http://localhost:{port}']
    with open(logfile, 'wb') as lf:
        p = subprocess.Popen(cmd, stdout=lf, stderr=lf)
    domain = None
    for attempt in range(12):
        time.sleep(1)
        if os.path.exists(logfile):
            try:
                txt = Path(logfile).read_text(errors='ignore')
                m = re.search(r'https://[a-zA-Z0-9\-]+\.trycloudflare\.com', txt)
                if m:
                    domain = m.group(0)
                    break
            except Exception:
                continue
    return jsonify({'ok': True, 'domain': domain, 'pid': p.pid})


@app.route('/api/zones', methods=['POST'])
@require_login
def api_zones():
    data = request.json or {}
    token = data.get('token')
    if not token:
        return jsonify({'ok': False, 'error': 'token required'}), 400
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    try:
        r = requests.get('https://api.cloudflare.com/client/v4/zones', headers=headers, timeout=10)
        j = r.json()
    except Exception as e:
        return jsonify({'ok': False, 'error': f'cloudflare api error: {str(e)}'}), 500
    if not j.get('success'):
        return jsonify({'ok': False, 'error': 'api returned success=false', 'detail': j.get('errors')}), 400
    zones = [{'id': z.get('id'), 'name': z.get('name')} for z in j.get('result', [])]
    return jsonify({'ok': True, 'zones': zones})


@app.route('/api/register', methods=['POST'])
@require_login
def api_register():
    payload = request.json or {}
    CF_TOKEN = payload.get('token')
    CF_ACCOUNT_ID = payload.get('account_id')
    DOMAIN_NAME = payload.get('domain')
    ZONE_ID = payload.get('zone_id')
    SUB_DOMAIN = payload.get('subdomain', '')
    TYPE = payload.get('type', 'http')
    LOCAL_PORT = payload.get('local_port')

    if not (CF_TOKEN and CF_ACCOUNT_ID and (DOMAIN_NAME or ZONE_ID) and LOCAL_PORT):
        return jsonify({'ok': False, 'error': 'missing required fields'}), 400

    if not re.match(r'^[a-zA-Z0-9\-\.]+$', DOMAIN_NAME) or '..' in DOMAIN_NAME:
        return jsonify({'ok': False, 'error': 'invalid domain name'}), 400
    if SUB_DOMAIN and not re.match(r'^[a-zA-Z0-9\-]+$', SUB_DOMAIN):
        return jsonify({'ok': False, 'error': 'invalid subdomain'}), 400

    FULL_DOMAIN = DOMAIN_NAME if not SUB_DOMAIN else f"{SUB_DOMAIN}.{DOMAIN_NAME}"

    headers = {'Authorization': f'Bearer {CF_TOKEN}', 'Content-Type': 'application/json'}
    t_name = f"cf-pro-{int(time.time())}"
    try:
        create_r = requests.post(f"https://api.cloudflare.com/client/v4/accounts/{CF_ACCOUNT_ID}/tunnels", headers=headers, json={"name": t_name}, timeout=10)
        cr = create_r.json()
    except Exception as e:
        return jsonify({'ok': False, 'error': f'tunnel creation request failed: {str(e)}'}), 500
    
    if cr is None:
        return jsonify({'ok': False, 'error': 'tunnel creation returned null response'}), 500
    
    if not cr.get('success'):
        return jsonify({'ok': False, 'error': 'tunnel creation failed', 'detail': cr.get('errors')}), 400
    
    tid = cr.get('result', {}).get('id')
    ttk = cr.get('result', {}).get('token')
    if not tid or not ttk:
        return jsonify({'ok': False, 'error': 'tunnel creation failed: no id or token in response'}), 500

    cred_path = os.path.join(CREDS_DIR, f"{tid}.json")
    try:
        decoded = base64.b64decode(ttk)
        with open(cred_path, 'wb') as f:
            f.write(decoded)
        os.chmod(cred_path, 0o600)
    except Exception as e:
        return jsonify({'ok': False, 'error': f'failed to save credentials: {str(e)}'}), 500

    yml_file = os.path.join(YML_DIR, f"{FULL_DOMAIN}.yml")
    yml_content = f"""tunnel: {tid}\ncredentials-file: {cred_path}\nloglevel: info\ningress:\n  - hostname: {FULL_DOMAIN}\n    service: {TYPE}://localhost:{LOCAL_PORT}\n  - service: http_status:404\n"""
    with open(yml_file, 'w') as f:
        f.write(yml_content)

    conf_url = f"https://api.cloudflare.com/client/v4/accounts/{CF_ACCOUNT_ID}/cfd_tunnel/{tid}/configurations"
    conf_payload = {"config": {"ingress": [{"hostname": FULL_DOMAIN, "service": f"{TYPE}://localhost:{LOCAL_PORT}"}, {"service": "http_status:404"}]}}
    requests.put(conf_url, headers=headers, json=conf_payload)

    dns_content = f"{tid}.cfargotunnel.com"
    dns_payload = {"type": "CNAME", "name": FULL_DOMAIN, "content": dns_content, "proxied": True, "ttl": 1}
    if ZONE_ID:
        requests.post(f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/dns_records", headers=headers, json=dns_payload)

    api_cfg = {'api_token': ttk, 'domain': FULL_DOMAIN, 'local_port': str(LOCAL_PORT), 'yml_path': yml_file}
    with open(os.path.join(API_CONFIG_DIR, f"{FULL_DOMAIN}.json"), 'w') as f:
        json.dump(api_cfg, f)
    os.chmod(os.path.join(API_CONFIG_DIR, f"{FULL_DOMAIN}.json"), 0o600)

    if check_bin(CF_BIN):
        logfile = os.path.join(LOG_DIR, f"{FULL_DOMAIN}.log")
        try:
            p = subprocess.Popen([CF_BIN, 'tunnel', 'run', '--token', ttk], stdout=open(logfile, 'ab'), stderr=open(logfile, 'ab'))
        except Exception as e:
            return jsonify({'ok': True, 'domain': FULL_DOMAIN, 'note': f'created but failed to run: {e}'}), 200

    return jsonify({'ok': True, 'domain': FULL_DOMAIN})


@app.route('/api/list', methods=['GET'])
@require_login
def api_list():
    res = []
    for p in Path(API_CONFIG_DIR).glob('*.json'):
        try:
            j = json.loads(p.read_text())
            res.append(j)
        except Exception:
            continue
    return jsonify({'ok': True, 'items': res})


@app.route('/api/delete', methods=['POST'])
@require_login
def api_delete():
    data = request.json or {}
    domain = data.get('domain')
    if not domain or not re.match(r'^[a-zA-Z0-9\-\.]+$', domain):
        return jsonify({'ok': False, 'error': 'invalid domain'}), 400
    
    cfg_file = os.path.join(API_CONFIG_DIR, f"{domain}.json")
    if not os.path.exists(cfg_file):
        return jsonify({'ok': False, 'error': 'domain not found'}), 404
    
    try:
        with open(cfg_file, 'r') as f:
            cfg = json.load(f)
        token = cfg.get('api_token')
        if token:
            subprocess.run(['pkill', '-f', token], check=False)
        os.remove(cfg_file)
        return jsonify({'ok': True, 'message': f'{domain} deleted'})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/run', methods=['POST'])
@require_login
def api_run():
    data = request.json or {}
    domain = data.get('domain')
    if not domain or not re.match(r'^[a-zA-Z0-9\-\.]+$', domain):
        return jsonify({'ok': False, 'error': 'invalid domain'}), 400
    
    cfg = os.path.join(API_CONFIG_DIR, f"{domain}.json")
    if not os.path.exists(cfg):
        return jsonify({'ok': False, 'error': 'config not found'}), 404
    j = json.loads(Path(cfg).read_text())
    token = j.get('api_token')
    logfile = os.path.join(LOG_DIR, f"{domain}.log")
    try:
        subprocess.run(['pkill', '-f', token], check=False)
    except Exception:
        pass
    if not check_bin(CF_BIN):
        return jsonify({'ok': False, 'error': 'cloudflared not available'}), 400
    p = subprocess.Popen([CF_BIN, 'tunnel', 'run', '--token', token], stdout=open(logfile, 'ab'), stderr=open(logfile, 'ab'))
    return jsonify({'ok': True, 'pid': p.pid})


@app.route('/api/start_node', methods=['POST'])
@require_login
def api_start_node():
    data = request.json or {}
    mtype = data.get('type', 'VMess')
    use_domain = data.get('domain')
    port = int(data.get('port', 8080))
    uuid = data.get('uuid') or (Path('/proc/sys/kernel/random/uuid').read_text().strip() if os.path.exists('/proc/sys/kernel/random/uuid') else 'uuid-fallback')
    path = data.get('path', '/ws')

    proto = 'vmess' if mtype.lower().startswith('vmess') else 'vless'
    config = {
        "inbounds": [{
            "port": port,
            "listen": "127.0.0.1",
            "protocol": proto,
            "settings": {"clients": [{"id": uuid}] if proto == 'vmess' else {}},
            "streamSettings": {"network": "ws", "wsSettings": {"path": path}}
        }],
        "outbounds": [{"protocol": "freedom"}]
    }
    cfg_path = os.path.join(XRAY_DIR, 'config.json')
    with open(cfg_path, 'w') as f:
        json.dump(config, f)
    try:
        subprocess.run(['pkill', '-f', XR_BIN], check=False)
    except Exception:
        pass
    if not check_bin(XR_BIN):
        return jsonify({'ok': False, 'error': 'xray binary not found'}), 400
    p = subprocess.Popen([XR_BIN, 'run', '-c', cfg_path], stdout=open(os.devnull, 'wb'), stderr=open(os.devnull, 'wb'))
    d = use_domain or 'localhost'
    if mtype.lower().startswith('vmess'):
        j = {"v":"2","ps":f"CF-{d}","add":d,"port":"443","id":uuid,"aid":"0","net":"ws","type":"none","path":path,"tls":"tls","sni":d,"host":d}
        link = 'vmess://' + base64.b64encode(json.dumps(j).encode()).decode()
    else:
        link = f"vless://{uuid}@{d}:443?encryption=none&type=ws&security=tls&host={d}&sni={d}&path={path}#CF-{d}"
    return jsonify({'ok': True, 'pid': p.pid, 'link': link})


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
