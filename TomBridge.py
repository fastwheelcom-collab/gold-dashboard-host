"""
TomBridge.py — Dashboard ↔ MT4 Bridge | Vantage Demo
=====================================================
Run on Windows VPS where MT4 is installed.

TELEGRAM REPORTS:
  → Every trade placed   : entry, SL, TP, ticket
  → Trade closed (SL/TP) : result, profit/loss, running total
  → Every hour           : open trades, session P&L, wins/losses
  → End of day (23:55)   : full daily report with breakdown

pip install flask requests
python TomBridge.py
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import requests, os, time, threading, json
from datetime import datetime

# ══════════════════════════════════════════
# CONFIG — EDIT THESE
# ══════════════════════════════════════════
TG_TOKEN   = "8865772661:AAFxgcvm514Dlj_4b4cbmjBKFNZCV35amk0"
TG_CHAT_ID = "7015050894"

# In MT4: File → Open Data Folder → go into MQL4\Files → copy path
MT4_FILES  = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL4\Files"

SIGNAL_FILE = os.path.join(MT4_FILES, "TomDashBot_signal.txt")
RESULT_FILE = os.path.join(MT4_FILES, "TomDashBot_result.txt")
REPORT_FILE = os.path.join(MT4_FILES, "TomDashBot_report.csv")
STATUS_FILE = os.path.join(MT4_FILES, "TomDashBot_status.txt")

app = Flask(__name__)
CORS(app)  # Allow all origins

# ══════════════════════════════════════════
# TELEGRAM
# ══════════════════════════════════════════
def tg(msg):
    try:
        requests.post(
            f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage",
            json={"chat_id": TG_CHAT_ID, "text": msg, "parse_mode": "HTML"},
            timeout=5
        )
        print(f"📤 TG: {msg[:60]}...")
    except Exception as e:
        print(f"TG error: {e}")

# ══════════════════════════════════════════
# FILE HELPERS
# ══════════════════════════════════════════
def write_signal(direction, price, reason):
    try:
        os.makedirs(MT4_FILES, exist_ok=True)
        with open(SIGNAL_FILE, 'w') as f:
            f.write(f"{direction}|{price:.2f}|{reason}")
        print(f"✅ Signal → {direction} ${price:.2f}")
        return True
    except Exception as e:
        print(f"❌ Write error: {e}")
        return False

def read_result(timeout=10):
    if os.path.exists(RESULT_FILE):
        try: os.remove(RESULT_FILE)
        except: pass
    start = time.time()
    while time.time() - start < timeout:
        if os.path.exists(RESULT_FILE):
            try:
                with open(RESULT_FILE, 'r') as f:
                    c = f.read().strip()
                parts = c.split('|')
                return {
                    "status": parts[0],
                    "dir":    parts[1],
                    "price":  float(parts[2]),
                    "sl":     float(parts[3]),
                    "tp":     float(parts[4]),
                    "ticket": parts[5],
                    "time":   parts[6] if len(parts) > 6 else "",
                    "reason": parts[7] if len(parts) > 7 else ""
                }
            except: pass
        time.sleep(0.3)
    return None

def read_status():
    try:
        if not os.path.exists(STATUS_FILE): return {}
        with open(STATUS_FILE, 'r') as f:
            line = f.read().strip()
        result = {}
        for part in line.split('|'):
            if '=' in part:
                k, v = part.split('=', 1)
                result[k] = v
        return result
    except:
        return {}

def read_report_today():
    """Parse today's trades from CSV report"""
    if not os.path.exists(REPORT_FILE):
        return []
    try:
        today = datetime.now().strftime('%Y.%m.%d')
        trades = []
        with open(REPORT_FILE, 'r') as f:
            lines = f.readlines()[1:]  # skip header
        for line in lines:
            if today in line and 'CLOSE' in line:
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 9:
                    trades.append({
                        'dir':    parts[3],
                        'entry':  parts[5],
                        'pnl':    float(parts[8]) if parts[8] else 0,
                        'result': parts[9] if len(parts) > 9 else '',
                        'note':   parts[11] if len(parts) > 11 else ''
                    })
        return trades
    except Exception as e:
        print(f"report parse error: {e}")
        return []

# ══════════════════════════════════════════
# TELEGRAM REPORTS
# ══════════════════════════════════════════

def tg_trade_placed(result, reason):
    """Sent right when trade is placed"""
    if not result or result['status'] != 'OK': return
    emoji   = '🚀' if result['dir'] == 'BUY' else '📉'
    sl_dist = abs(result['price'] - result['sl'])
    tp_dist = abs(result['tp']    - result['price'])
    s       = read_status()
    tg(
        f"{emoji} <b>TRADE PLACED</b>\n"
        f"{'━'*22}\n"
        f"📌 <b>{result['dir']}</b>  XAUUSD  (Demo)\n"
        f"💰 Entry:   <b>${result['price']:.2f}</b>\n"
        f"🛡 SL:      ${result['sl']:.2f}  <i>(-${sl_dist:.2f})</i>\n"
        f"🎯 TP:      ${result['tp']:.2f}  <i>(+${tp_dist:.2f})</i>\n"
        f"🎫 Ticket:  #{result['ticket']}\n"
        f"{'━'*22}\n"
        f"📋 {reason}\n"
        f"💰 Balance: ${s.get('balance','--')}\n"
        f"🕐 {datetime.now().strftime('%H:%M:%S')} Dubai"
    )

def tg_trade_closed(ticket, direction, entry, close_price, pnl, exit_type):
    """Sent when MT4 closes a trade (SL/TP hit or manual)"""
    emoji  = '✅' if pnl >= 0 else '❌'
    result = 'WIN' if pnl >= 0 else 'LOSS'
    s      = read_status()
    try:
        wins   = int(s.get('wins',   0))
        losses = int(s.get('losses', 0))
        total  = wins + losses
        acc    = round(100 * wins / total, 1) if total > 0 else 0
        cum    = float(s.get('totalpnl', 0))
    except:
        wins = losses = total = acc = cum = 0

    tg(
        f"{emoji} <b>TRADE CLOSED — {result}</b>\n"
        f"{'━'*22}\n"
        f"📌 {direction}  XAUUSD  #{ticket}\n"
        f"💰 Entry:  ${entry:.2f}  →  Close: ${close_price:.2f}\n"
        f"💵 P&L:    <b>${pnl:+.2f}</b>\n"
        f"📝 Exit:   {exit_type}\n"
        f"{'━'*22}\n"
        f"📊 Running: ✅{wins} / ❌{losses}  ({acc}%)\n"
        f"💼 Cumul P&L: <b>${cum:+.2f}</b>\n"
        f"💰 Balance: ${s.get('balance','--')}\n"
        f"🕐 {datetime.now().strftime('%H:%M:%S')} Dubai"
    )

def tg_hourly():
    """Every hour — quick snapshot"""
    s = read_status()
    if not s or not s.get('balance'): return
    try:
        pnl    = float(s.get('totalpnl', 0))
        opnl   = float(s.get('pnl',      0))
        acc    = float(s.get('accuracy',  0))
        wins   = int(s.get('wins',    0))
        losses = int(s.get('losses',  0))
        total  = int(s.get('total',   0))
        open_c = int(s.get('open',    0))
        emoji  = '📈' if pnl >= 0 else '📉'
        tg(
            f"{emoji} <b>HOURLY UPDATE</b>  {datetime.now().strftime('%H:%M')}\n"
            f"{'━'*22}\n"
            f"💰 Balance:  ${s.get('balance','--')}\n"
            f"📊 Equity:   ${s.get('equity','--')}\n"
            f"📌 Open:     {open_c} trade(s)  P&L: ${opnl:+.2f}\n"
            f"{'━'*22}\n"
            f"📈 Today's trades:  {total}\n"
            f"  ✅ Wins:     {wins}\n"
            f"  ❌ Losses:   {losses}\n"
            f"  🎯 Accuracy: {acc:.1f}%\n"
            f"  💵 Cumul P&L: ${pnl:+.2f}\n"
            f"{'━'*22}\n"
            f"🕐 {datetime.now().strftime('%H:%M')} Dubai"
        )
    except Exception as e:
        print(f"hourly error: {e}")

def tg_daily_report():
    """23:55 Dubai — full day summary"""
    s      = read_status()
    trades = read_report_today()
    if not s: return
    try:
        pnl    = float(s.get('totalpnl', 0))
        acc    = float(s.get('accuracy', 0))
        wins   = int(s.get('wins',   0))
        losses = int(s.get('losses', 0))
        total  = int(s.get('total',  0))

        # Breakdown by direction
        buy_wins  = sum(1 for t in trades if t['dir']=='BUY'  and t['pnl']>0)
        buy_loss  = sum(1 for t in trades if t['dir']=='BUY'  and t['pnl']<0)
        sel_wins  = sum(1 for t in trades if t['dir']=='SELL' and t['pnl']>0)
        sel_loss  = sum(1 for t in trades if t['dir']=='SELL' and t['pnl']<0)
        buy_pnl   = sum(t['pnl'] for t in trades if t['dir']=='BUY')
        sel_pnl   = sum(t['pnl'] for t in trades if t['dir']=='SELL')

        # Best / worst trade
        best  = max(trades, key=lambda t: t['pnl'])  if trades else None
        worst = min(trades, key=lambda t: t['pnl'])  if trades else None

        grade   = '🟢 GOOD'   if acc >= 60 else '🟡 OK' if acc >= 45 else '🔴 NEEDS WORK'
        verdict = '🏆 PROFITABLE DAY!' if pnl > 0 else '📉 Losing day — review signals'

        tg(
            f"🌙 <b>DAILY REPORT — TomDashBot</b>\n"
            f"📅 {datetime.now().strftime('%A, %d %b %Y')}\n"
            f"{'━'*24}\n"
            f"💰 Balance:   ${s.get('balance','--')}\n"
            f"📊 Equity:    ${s.get('equity','--')}\n"
            f"{'━'*24}\n"
            f"📈 <b>Today's Performance</b>\n"
            f"  Total trades: <b>{total}</b>\n"
            f"  ✅ Wins:       <b>{wins}</b>\n"
            f"  ❌ Losses:     <b>{losses}</b>\n"
            f"  🎯 Accuracy:   <b>{acc:.1f}%</b>  {grade}\n"
            f"  💵 Net P&L:    <b>${pnl:+.2f}</b>\n"
            f"{'━'*24}\n"
            f"📊 <b>By Direction</b>\n"
            f"  BUY  → ✅{buy_wins} ❌{buy_loss}  P&L: ${buy_pnl:+.2f}\n"
            f"  SELL → ✅{sel_wins} ❌{sel_loss}  P&L: ${sel_pnl:+.2f}\n"
            f"{'━'*24}\n"
            + (f"🏅 Best:  ${best['pnl']:+.2f}  ({best['dir']})\n"  if best  else '') +
            (f"💀 Worst: ${worst['pnl']:+.2f}  ({worst['dir']})\n" if worst else '') +
            f"{'━'*24}\n"
            f"{verdict}\n"
            f"🕐 {datetime.now().strftime('%H:%M')} Dubai"
        )
    except Exception as e:
        print(f"daily report error: {e}")

# ══════════════════════════════════════════
# CLOSED TRADE WATCHER
# Polls MT4 status file for newly closed trades
# ══════════════════════════════════════════
last_seen_tickets = set()

def watch_closed_trades():
    """Background thread — detects when trades close and sends Telegram"""
    global last_seen_tickets
    while True:
        time.sleep(5)
        try:
            if not os.path.exists(REPORT_FILE): continue
            with open(REPORT_FILE, 'r') as f:
                lines = f.readlines()[1:]

            for line in lines:
                if 'CLOSE' not in line: continue
                parts = [p.strip() for p in line.split(',')]
                if len(parts) < 10: continue
                ticket    = parts[4]
                if ticket in last_seen_tickets: continue
                last_seen_tickets.add(ticket)

                direction   = parts[3]
                entry_price = float(parts[5]) if parts[5] else 0
                close_note  = parts[11] if len(parts) > 11 else ''
                pnl         = float(parts[8]) if parts[8] else 0

                # Parse exit type from note
                exit_type = 'TP HIT ✅' if 'TP' in close_note else \
                            'SL HIT ❌' if 'SL' in close_note else \
                            'Manual Close'

                # Get close price from note or estimate
                close_price = entry_price + (pnl / 0.1) if entry_price else 0

                tg_trade_closed(ticket, direction, entry_price, close_price, pnl, exit_type)
        except Exception as e:
            print(f"watcher error: {e}")

# ══════════════════════════════════════════
# AUTONOMOUS TRADING ENGINE
# Fetches price + runs Tom analysis every 30s
# ══════════════════════════════════════════
auto_state = {
    'last_price':      0,
    'prev_price':      0,
    'day_high':        0,
    'day_low':         999999,
    'last_signal':     '',
    'last_signal_time': 0,
    'enabled':         True,
    'last_action':     'Starting...',
    'last_reason':     '',
}
SIGNAL_COOLDOWN = 5 * 60  # 5 minutes between same-direction signals

def fetch_gold_price():
    """Fetch spot XAUUSD price — tries multiple sources"""
    sources = [
        # 1. Metals.live spot
        lambda: requests.get('https://api.metals.live/v1/spot/gold', timeout=5).json(),
        # 2. Swissquote spot
        lambda: None,  # handled separately
        # 3. Yahoo XAUUSD=X spot
        lambda: requests.get(
            'https://query1.finance.yahoo.com/v8/finance/chart/XAUUSD%3DX?interval=1m&range=1d',
            headers={'Accept':'application/json','User-Agent':'Mozilla/5.0'},
            timeout=5
        ).json()['chart']['result'][0]['meta'],
        # 4. Yahoo GC=F futures fallback
        lambda: requests.get(
            'https://query1.finance.yahoo.com/v8/finance/chart/GC%3DF?interval=1m&range=1d',
            headers={'Accept':'application/json','User-Agent':'Mozilla/5.0'},
            timeout=5
        ).json()['chart']['result'][0]['meta'],
    ]

    # Try metals.live
    try:
        d = requests.get('https://api.metals.live/v1/spot/gold', timeout=5).json()
        price = d.get('price') or (d[0].get('price') if isinstance(d, list) else None)
        if price and price > 100:
            return float(price), float(price), float(price), 'metals.live'
    except: pass

    # Try Swissquote
    try:
        d = requests.get('https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD', timeout=5).json()
        sp = next((x for x in d[0]['spreadProfilePrices'] if x['spreadProfile']=='prime'), d[0]['spreadProfilePrices'][0])
        price = (sp['bid'] + sp['ask']) / 2
        if price > 100:
            return float(price), float(price), float(price), 'Swissquote'
    except: pass

    # Try Yahoo spot
    try:
        d = requests.get(
            'https://query1.finance.yahoo.com/v8/finance/chart/XAUUSD%3DX?interval=1m&range=1d',
            headers={'Accept':'application/json','User-Agent':'Mozilla/5.0'}, timeout=5
        ).json()['chart']['result'][0]['meta']
        return float(d['regularMarketPrice']), float(d.get('regularMarketDayHigh', d['regularMarketPrice'])), float(d.get('regularMarketDayLow', d['regularMarketPrice'])), 'Yahoo Spot'
    except: pass

    # Try Yahoo futures
    try:
        d = requests.get(
            'https://query1.finance.yahoo.com/v8/finance/chart/GC%3DF?interval=1m&range=1d',
            headers={'Accept':'application/json','User-Agent':'Mozilla/5.0'}, timeout=5
        ).json()['chart']['result'][0]['meta']
        return float(d['regularMarketPrice']), float(d.get('regularMarketDayHigh', d['regularMarketPrice'])), float(d.get('regularMarketDayLow', d['regularMarketPrice'])), 'Yahoo Futures'
    except: pass

    return None, None, None, None

def get_dubai_hour():
    """Get current hour in Dubai time (UTC+4)"""
    import calendar
    utc_now = datetime.utcnow()
    dubai_hour = (utc_now.hour + 4) % 24
    dubai_min  = utc_now.minute
    return dubai_hour + dubai_min / 60

def tom_analysis(price, prev, high, low):
    """
    Same logic as Tom Assistant panel in dashboard.
    Returns: action, reason, direction (BUY/SELL/None)
    """
    if not price or not prev or price <= 0:
        return 'WAIT', 'No price data', None

    chg      = price - prev
    pct      = (chg / prev) * 100 if prev else 0
    rng      = high - low if high and low else 0
    pct_abs  = abs(pct)
    is_bull  = chg > 0
    is_strong = pct_abs > 0.4
    is_flat   = pct_abs < 0.1
    is_overbought = rng > 5 and price > high - (rng * 0.1)
    is_oversold   = rng > 5 and price < low  + (rng * 0.1)

    # Session check (Dubai time UTC+4)
    h = get_dubai_hour()
    london_open = 11 <= h < 19
    ny_open     = h >= 16 or h < 1
    tokyo_open  = 3  <= h < 12
    overlap     = london_open and ny_open
    any_open    = london_open or ny_open or tokyo_open
    sess_label  = 'London+NY overlap ⚡' if overlap else 'London' if london_open else 'New York' if ny_open else 'Tokyo' if tokyo_open else 'Off-hours'

    # Decision logic — mirrors dashboard JS exactly
    if not any_open:
        return 'WAIT', f'All sessions closed ({sess_label}) — low volume', None

    if is_flat:
        return 'WAIT', f'Price flat ({pct:+.2f}%) — no clear direction — ranging', None

    if is_bull and is_strong and not is_overbought:
        reason = f'Gold +{pct:.2f}% | Strong bull momentum | {sess_label} | Room to high ${high:.0f}'
        return 'BUY', reason, 'BUY'

    if is_bull and is_overbought:
        return 'WAIT', f'Bullish but near day high ${high:.0f} — too risky to chase', None

    if is_bull and not is_strong:
        return 'WAIT', f'Mild bullish +{pct:.2f}% — wait for stronger momentum', None

    if not is_bull and is_strong and not is_oversold:
        reason = f'Gold {pct:.2f}% | Strong bear momentum | {sess_label} | Room to low ${low:.0f}'
        return 'SELL', reason, 'SELL'

    if not is_bull and is_oversold:
        return 'WAIT', f'Bearish but near day low ${low:.0f} — bounce risk', None

    return 'WAIT', f'Mild move {pct:+.2f}% — no clear setup yet', None

def auto_trading_engine():
    """Main autonomous trading loop — runs every 30 seconds"""
    print('🤖 Auto trading engine started')
    open_price = None

    while True:
        time.sleep(30)
        try:
            if not auto_state['enabled']:
                continue

            price, high, low, source = fetch_gold_price()
            if not price:
                print('⚠️ Price fetch failed — skipping cycle')
                continue

            # Track day open price (first fetch of the day)
            now = datetime.utcnow()
            if open_price is None or now.hour == 0 and now.minute < 1:
                open_price = price

            prev  = open_price or price
            day_h = max(auto_state['day_high'], price)
            day_l = min(auto_state['day_low'],  price) if auto_state['day_low'] < 999999 else price
            auto_state['day_high'] = day_h
            auto_state['day_low']  = day_l
            auto_state['last_price'] = price

            action, reason, direction = tom_analysis(price, prev, day_h, day_l)
            auto_state['last_action'] = action
            auto_state['last_reason'] = reason

            print(f'🔍 [{source}] ${price:.2f} | {action} | {reason[:60]}')

            if not direction:
                continue

            # Cooldown — don't repeat same direction within 5 min
            now_ts = time.time()
            same_dir   = direction == auto_state['last_signal']
            in_cooldown = (now_ts - auto_state['last_signal_time']) < SIGNAL_COOLDOWN

            if same_dir and in_cooldown:
                remaining = int(SIGNAL_COOLDOWN - (now_ts - auto_state['last_signal_time']))
                print(f'⏳ Cooldown {remaining}s — skipping duplicate {direction}')
                continue

            # Fire the trade
            auto_state['last_signal']      = direction
            auto_state['last_signal_time'] = now_ts

            print(f'🚀 AUTO FIRE: {direction} @ ${price:.2f}')
            ok = write_signal(direction, price, f'[AUTO] {reason}')
            if ok:
                result = read_result(timeout=10)
                if result and result['status'] == 'OK':
                    tg_trade_placed(result, f'[AUTO] {reason}')
                else:
                    tg(f'⚠️ <b>AUTO SIGNAL SENT</b> — No MT4 reply\n{direction} @ ${price:.2f}\n{reason}')
            else:
                tg(f'❌ Auto trade FAILED — signal file write error\n{direction} @ ${price:.2f}')

        except Exception as e:
            print(f'Auto engine error: {e}')

# ── AUTO TRADE TOGGLE ENDPOINT ──
@app.route('/auto/toggle', methods=['POST'])
def auto_toggle():
    auto_state['enabled'] = not auto_state['enabled']
    status = 'ENABLED' if auto_state['enabled'] else 'DISABLED'
    tg(f'🤖 Auto trading <b>{status}</b> via dashboard')
    return jsonify({'ok': True, 'enabled': auto_state['enabled'], 'status': status})

@app.route('/auto/status', methods=['GET'])
def auto_status():
    return jsonify({
        'ok':          True,
        'enabled':     auto_state['enabled'],
        'last_price':  auto_state['last_price'],
        'last_action': auto_state['last_action'],
        'last_reason': auto_state['last_reason'],
        'last_signal': auto_state['last_signal'],
    })

# ══════════════════════════════════════════
# PERIODIC SCHEDULER
# ══════════════════════════════════════════
def scheduler():
    last_hour = -1
    last_day  = -1
    while True:
        time.sleep(60)
        now = datetime.now()

        # Hourly update
        if now.hour != last_hour:
            last_hour = now.hour
            tg_hourly()

        # Daily report at 23:55
        if now.hour == 23 and now.minute >= 55 and now.day != last_day:
            last_day = now.day
            tg_daily_report()

# ══════════════════════════════════════════
# FLASK ENDPOINTS
# ══════════════════════════════════════════
@app.route('/signal', methods=['POST'])
def receive_signal():
    data      = request.json or {}
    direction = data.get('direction','').upper()
    price     = float(data.get('price', 0))
    reason    = data.get('reason', 'Dashboard')

    if direction not in ('BUY','SELL','CLOSE'):
        return jsonify({"ok": False, "error": "invalid direction"})

    ok = write_signal(direction, price, reason)
    if not ok:
        tg("❌ <b>TomBridge ERROR</b>\nCan't write signal file — check MT4_FILES path")
        return jsonify({"ok": False, "error": "file write failed"})

    result = read_result(timeout=10)

    if result and result['status'] == 'OK':
        tg_trade_placed(result, reason)
        return jsonify({"ok": True, "result": result})

    elif result and result['status'] == 'FAIL':
        tg(f"❌ <b>TRADE FAILED</b>\nError: {result['ticket']}\n{direction} @ ${price:.2f}")
        return jsonify({"ok": False, "result": result})

    else:
        tg(
            f"⚠️ <b>SIGNAL SENT — No MT4 reply</b>\n"
            f"{direction} @ ${price:.2f}\n"
            f"Check MT4 terminal\nReason: {reason}"
        )
        return jsonify({"ok": True, "msg": "Signal sent, awaiting MT4"})

@app.route('/status', methods=['GET'])
def api_status():
    s = read_status()
    s['ok']            = True
    s['mt4_connected'] = os.path.exists(STATUS_FILE)
    s['report_exists'] = os.path.exists(REPORT_FILE)
    return jsonify(s)

@app.route('/close', methods=['POST'])
def api_close():
    write_signal("CLOSE", 0, "Dashboard close all")
    tg("🔴 <b>CLOSE ALL</b> command sent to MT4")
    return jsonify({"ok": True})

@app.route('/report', methods=['GET'])
def api_report():
    try:
        if not os.path.exists(REPORT_FILE):
            return jsonify({"ok": False, "error": "No report yet"})
        with open(REPORT_FILE, 'r') as f:
            content = f.read()
        return app.response_class(
            content, mimetype='text/csv',
            headers={"Content-Disposition":"attachment; filename=TomDashBot_report.csv"}
        )
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

@app.route('/daily', methods=['GET'])
def api_daily():
    tg_daily_report()
    return jsonify({"ok": True, "msg": "Daily report sent to Telegram"})

@app.route('/ping', methods=['GET'])
def ping():
    return jsonify({"ok": True, "msg": "TomBridge running", "mt4_ok": os.path.exists(MT4_FILES)})

@app.route('/')
def serve_dashboard():
    dashboard = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'index.html')
    if os.path.exists(dashboard):
        with open(dashboard, 'r', encoding='utf-8') as f:
            return f.read(), 200, {'Content-Type': 'text/html'}
    return '<h2>Dashboard not found. Place index.html next to TomBridge.py</h2>', 404

# ══════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════
if __name__ == "__main__":
    print("=" * 55)
    print("  TomBridge — Dashboard → MT4 | Vantage Demo")
    print("=" * 55)
    print(f"  MT4 Files: {MT4_FILES}")

    if not os.path.exists(MT4_FILES):
        print(f"\n⚠️  MT4 Files folder NOT found!")
        print(f"   In MT4: File → Open Data Folder → MQL4\\Files")
        print(f"   Paste that path into MT4_FILES above\n")
    else:
        print(f"  ✅ MT4 Files folder found")

    # Start background threads
    threading.Thread(target=scheduler,            daemon=True).start()
    threading.Thread(target=watch_closed_trades,  daemon=True).start()
    threading.Thread(target=auto_trading_engine,  daemon=True).start()
    print('🤖 Autonomous trading engine: ACTIVE (every 30s)')

    tg(
        f"🌉 <b>TomBridge STARTED</b>\n"
        f"{'━'*22}\n"
        f"✅ Dashboard → MT4 bridge active\n"
        f"📊 Symbol: XAUUSD | Vantage Demo\n"
        f"⚡ Every signal = auto trade\n\n"
        f"📣 <b>Telegram notifications:</b>\n"
        f"  → Every trade placed\n"
        f"  → Every trade closed (SL/TP)\n"
        f"  → Hourly P&L snapshot\n"
        f"  → Daily report at 23:55\n"
        f"{'━'*22}\n"
        f"Waiting for signals..."
    )

    print("🌐 Listening on port 5055...\n")
    app.run(host='0.0.0.0', port=5055, debug=False)
