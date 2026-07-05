extends Node
# Web 端文字输入桥（autoload 名 WebInput）。
# 手机 webview 里 Godot 画布拿不到系统输入法（实验性虚拟键盘在 B站 App 内实测不弹），
# 改用真 DOM 输入：给每个注册的 LineEdit 盖一层透明命中区，点击后在同一手势内
# focus 顶部的原生输入条（键盘/中文输入法必弹），确定后把文本写回并按回车语义提交。

const SYNC_INTERVAL := 0.15

var _targets: Dictionary = {}
var _js_done: JavaScriptObject
var _sync_accum := 0.0

func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	_js_done = JavaScriptBridge.create_callback(_on_js_done)
	JavaScriptBridge.eval(_JS_SETUP, true)
	var win := JavaScriptBridge.get_interface("window")
	win.__dpDone = _js_done

# id 需全局唯一；attach 后该 LineEdit 在 Web 端的输入一律走 DOM 输入条。
func attach(id: String, line_edit: LineEdit) -> void:
	if not OS.has_feature("web") or line_edit == null:
		return
	line_edit.virtual_keyboard_enabled = false
	_targets[id] = line_edit

func _process(delta: float) -> void:
	_sync_accum += delta
	if _sync_accum < SYNC_INTERVAL:
		return
	_sync_accum = 0.0
	var payload: Array = []
	for id in _targets:
		var le: LineEdit = _targets[id]
		if le == null or not is_instance_valid(le):
			continue
		var entry := {"id": id, "visible": le.is_visible_in_tree()}
		if entry["visible"]:
			var r := le.get_global_rect()
			# 嵌入式子窗口（弹窗卡片）里的控件坐标相对子窗口视口，需叠加子窗口位置
			var w := le.get_window()
			if w != null and w != get_tree().root:
				r.position += Vector2(w.position)
			entry["x"] = r.position.x
			entry["y"] = r.position.y
			entry["w"] = r.size.x
			entry["h"] = r.size.y
			entry["ph"] = le.placeholder_text
			entry["cur"] = le.text
		payload.append(entry)
	JavaScriptBridge.eval("window.__dpSync && window.__dpSync(%s)" % JSON.stringify(payload), true)

func _on_js_done(args: Array) -> void:
	if args.size() < 2 or args[1] == null:
		return
	var id := String(args[0])
	if not _targets.has(id):
		return
	var le: LineEdit = _targets[id]
	if le == null or not is_instance_valid(le):
		return
	var value := String(args[1])
	le.text = value
	le.caret_column = value.length()
	le.text_submitted.emit(value)

# 设计尺寸 400×720 与 main.gd 的 WEB_DESIGN_SIZE 一致（canvas_items + keep 居中信箱）。
const _JS_SETUP := """
(function(){
	if (window.__dpInit) return; window.__dpInit = true;
	var backdrop = document.createElement('div');
	backdrop.style.cssText = 'position:fixed;inset:0;z-index:950;display:none;background:rgba(16,23,26,.45)';
	var bar = document.createElement('div');
	bar.style.cssText = 'position:fixed;left:0;right:0;top:0;z-index:1000;display:none;background:#1b262a;padding:10px;box-sizing:border-box;box-shadow:0 2px 12px rgba(0,0,0,.4)';
	var inp = document.createElement('input');
	inp.type = 'text';
	inp.style.cssText = 'width:calc(100% - 92px);font-size:16px;padding:10px 12px;border:1px solid #56b6c9;border-radius:6px;background:#f6f1e6;color:#1f2a2b;outline:none;box-sizing:border-box;vertical-align:middle';
	var ok = document.createElement('button');
	ok.textContent = '\\u786e\\u5b9a';
	ok.style.cssText = 'width:80px;margin-left:8px;font-size:16px;padding:10px 0;border:none;border-radius:6px;background:#c9824a;color:#fff7ee;vertical-align:middle';
	bar.appendChild(inp); bar.appendChild(ok);
	document.body.appendChild(backdrop); document.body.appendChild(bar);
	var proxies = {}; var active = null;
	function openBar(id){
		var p = proxies[id]; if (!p) return;
		active = id;
		inp.value = p.__cur || ''; inp.placeholder = p.__ph || '';
		backdrop.style.display = 'block'; bar.style.display = 'block';
		inp.focus();
		try { inp.setSelectionRange(inp.value.length, inp.value.length); } catch(e) {}
	}
	function finish(val){
		backdrop.style.display = 'none'; bar.style.display = 'none';
		inp.blur();
		if (active !== null && window.__dpDone) window.__dpDone(active, val);
		active = null;
	}
	ok.addEventListener('click', function(){ finish(inp.value); });
	backdrop.addEventListener('click', function(){ finish(null); });
	inp.addEventListener('keydown', function(e){
		if (e.key === 'Enter') finish(inp.value);
		else if (e.key === 'Escape') finish(null);
	});
	window.__dpSync = function(list){
		var c = document.querySelector('canvas');
		if (!c) return;
		var r = c.getBoundingClientRect();
		var s = Math.min(r.width/400, r.height/720);
		var ox = r.left + (r.width - 400*s)/2, oy = r.top + (r.height - 720*s)/2;
		for (var i = 0; i < list.length; i++) {
			var it = list[i];
			var p = proxies[it.id];
			if (!p) {
				p = document.createElement('div');
				p.style.cssText = 'position:fixed;z-index:900;background:transparent;cursor:text';
				p.setAttribute('data-dp-input', it.id);
				(function(pid){ p.addEventListener('click', function(){ openBar(pid); }); })(it.id);
				document.body.appendChild(p);
				proxies[it.id] = p;
			}
			if (it.visible) {
				p.__ph = it.ph || ''; p.__cur = it.cur || '';
				p.style.left = (ox + it.x*s) + 'px';
				p.style.top = (oy + it.y*s) + 'px';
				p.style.width = (it.w*s) + 'px';
				p.style.height = (it.h*s) + 'px';
				p.style.display = 'block';
			} else {
				p.style.display = 'none';
			}
		}
	};
})();
"""
