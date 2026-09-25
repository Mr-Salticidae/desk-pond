extends Node
# Web 外壳适配（autoload 名 WebShell）：让手机版吃满全面屏。
# - B站 Toy App 内：通过 Toy JS SDK（导出预设 head_include 引入）请求「沉浸 + 竖屏」容器，
#   并订阅 onContainerChange 拿到状态栏 / 导航条占掉的 safeArea。
# - 其它浏览器：读 CSS env(safe-area-inset-*)（需要 viewport-fit=cover，同样由 head_include 补上）。
# 两路取较大值，换算成 Godot 设计坐标后通过 safe_area_changed 通知 main 让出刘海 / 手势条。
# 桌面端调试：godot --path . -- --web-layout --safe-area=44,0,34,0 可模拟（上,右,下,左，设计像素）。
#
# 分享（见 EcoShare / ShareCard）：
# - B站 App 内：toy.share 拉起分享面板（只传相对路径 index.html?tank=…，完整链接由平台生成）、
#   toy.saveImageToAlbum 存相册、toy.getQrCode 生成指向这只缸的二维码。
# - 其它浏览器：navigator.share（支持时带上图片），否则下载图片 / 复制链接。
# - 打开别人分享的链接时，take_incoming_code() 取出 ?tank= 并从地址栏抹掉，刷新不会再进朋友家。
#   桌面端调试：-- --visit=<分享码>

signal safe_area_changed(insets: Dictionary)
signal share_result(kind: String, ok: bool, detail: String)   # kind: share / save / copy
signal qr_ready(image: Image)

var insets := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}
var immersive := false
# 分享能力：页面加载后异步探测（Toy SDK 以 async 引入）
var can_toy_share := false
var can_save_album := false
var can_qr := false
var can_native_share := false
var _js_cb: JavaScriptObject
var _js_caps_cb: JavaScriptObject
var _js_done_cb: JavaScriptObject
var _js_qr_cb: JavaScriptObject
var _css := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0, "vw": 0.0}

func _ready() -> void:
	if OS.has_feature("web"):
		_js_cb = JavaScriptBridge.create_callback(_on_js_safe)
		_js_caps_cb = JavaScriptBridge.create_callback(_on_js_caps)
		_js_done_cb = JavaScriptBridge.create_callback(_on_js_done)
		_js_qr_cb = JavaScriptBridge.create_callback(_on_js_qr)
		var win := JavaScriptBridge.get_interface("window")
		win.__dpSafe = _js_cb
		win.__dpCaps = _js_caps_cb
		win.__dpShareDone = _js_done_cb
		win.__dpQrDone = _js_qr_cb
		# 先装分享脚本：_JS_SETUP 里探测到 Toy SDK 时会同步调用 __dpProbeCaps
		JavaScriptBridge.eval(_JS_SHARE, true)
		JavaScriptBridge.eval(_JS_SETUP, true)
		get_tree().root.size_changed.connect(_recompute)
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--safe-area="):
				var parts := arg.trim_prefix("--safe-area=").split(",")
				if parts.size() == 4:
					insets = {"top": float(parts[0]), "right": float(parts[1]), "bottom": float(parts[2]), "left": float(parts[3])}

# ---------- 分享 ----------

func is_web() -> bool:
	return OS.has_feature("web")

# 启动时取一次：别人分享的链接里带的 ?tank= 分享码（取完即从地址栏移除）
func take_incoming_code() -> String:
	if is_web():
		var code = JavaScriptBridge.eval("window.__dpTakeTank ? window.__dpTakeTank() : ''", true)
		return String(code) if code != null else ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visit="):
			return arg.trim_prefix("--visit=")
	return ""

# 当前页面地址 + ?tank=，给浏览器里的「复制链接」用
func page_link(code: String) -> String:
	if not is_web():
		return ""
	var url = JavaScriptBridge.eval("window.__dpPageUrl ? window.__dpPageUrl(%s) : ''" % JSON.stringify(code), true)
	return String(url) if url != null else ""

func _set_png(png_b64: String) -> void:
	var win := JavaScriptBridge.get_interface("window")
	win.__dpPng = png_b64

# 拉起分享：App 内走 Toy 分享面板，否则 navigator.share；结果经 share_result("share", …) 回来
func share(path: String, url: String, title: String, text: String, png_b64: String) -> void:
	if not is_web():
		share_result.emit("share", false, "unsupported")
		return
	_set_png(png_b64)
	JavaScriptBridge.eval("window.__dpShare(%s, %s, %s, %s)" % [JSON.stringify(path), JSON.stringify(url), JSON.stringify(title), JSON.stringify(text)], true)

func save_image(png_b64: String, filename: String) -> void:
	_set_png(png_b64)
	JavaScriptBridge.eval("window.__dpSaveImage(%s)" % JSON.stringify(filename), true)

func copy_text(text: String) -> void:
	JavaScriptBridge.eval("window.__dpCopy(%s)" % JSON.stringify(text), true)

func request_qr(path: String, size: int) -> void:
	if is_web() and can_qr:
		JavaScriptBridge.eval("window.__dpQr(%s, %d)" % [JSON.stringify(path), size], true)

func _on_js_caps(args: Array) -> void:
	if args.is_empty():
		return
	var caps = JSON.parse_string(String(args[0]))
	if typeof(caps) != TYPE_DICTIONARY:
		return
	can_toy_share = bool(caps.get("toyShare", false))
	can_save_album = bool(caps.get("album", false))
	can_qr = bool(caps.get("qr", false))
	can_native_share = bool(caps.get("native", false))

func _on_js_done(args: Array) -> void:
	if args.size() < 3:
		return
	share_result.emit(String(args[0]), bool(args[1]), String(args[2]))

func _on_js_qr(args: Array) -> void:
	if args.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(String(args[0]))) != OK:
		if img.load_jpg_from_buffer(Marshalls.base64_to_raw(String(args[0]))) != OK:
			return
	qr_ready.emit(img)

func _on_js_safe(args: Array) -> void:
	if args.is_empty():
		return
	var parsed = JSON.parse_string(String(args[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_css = parsed
	immersive = bool(parsed.get("immersive", false))
	_recompute()

# CSS 像素 → 设计像素：画布铺满窗口，所以比例就是「可见宽度 / innerWidth」
func _recompute() -> void:
	var vw := float(_css.get("vw", 0.0))
	if vw <= 0.0:
		return
	var k := get_tree().root.get_visible_rect().size.x / vw
	var next := {}
	for side in ["top", "right", "bottom", "left"]:
		next[side] = roundf(float(_css.get(side, 0.0)) * k)
	if next != insets:
		insets = next
		safe_area_changed.emit(insets)

const _JS_SETUP := """
(function(){
	if (window.__dpShellInit) return; window.__dpShellInit = true;
	var probe = document.createElement('div');
	probe.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;' +
		'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
	document.body.appendChild(probe);
	var toySafe = null, immersive = false;
	function report(){
		var cs = getComputedStyle(probe);
		var s = {
			top: parseFloat(cs.paddingTop) || 0, right: parseFloat(cs.paddingRight) || 0,
			bottom: parseFloat(cs.paddingBottom) || 0, left: parseFloat(cs.paddingLeft) || 0
		};
		if (toySafe) for (var k in s) s[k] = Math.max(s[k], toySafe[k] || 0);
		s.vw = window.innerWidth; s.vh = window.innerHeight; s.immersive = immersive;
		if (window.__dpSafe) window.__dpSafe(JSON.stringify(s));
	}
	window.addEventListener('resize', function(){ setTimeout(report, 60); });
	window.addEventListener('orientationchange', function(){ setTimeout(report, 300); });
	// Toy SDK 以 async 方式加载，这里最多等 5 秒；不在 B站 App 里时 isSupport 为 false，安静跳过
	function tryToy(n){
		var toy = window.toy;
		if (!toy || !toy.isSupport) {
			if (n < 20) setTimeout(function(){ tryToy(n + 1); }, 250);
			else if (window.__dpProbeCaps) window.__dpProbeCaps();
			return;
		}
		if (window.__dpProbeCaps) window.__dpProbeCaps();
		try {
			toy.isSupport('getContainerState').then(function(ok){
				if (!ok) return;
				// 先订阅再切模式：setContainerMode 的 Promise 不代表已生效，以通知为准
				toy.onContainerChange(function(st){
					if (!st) return;
					if (st.safeArea) toySafe = st.safeArea;
					if (typeof st.immersive === 'boolean') immersive = st.immersive;
					setTimeout(report, 30);
				});
				toy.isSupport('setContainerMode').then(function(can){
					if (can) toy.setContainerMode({ orientation: 'portrait', immersive: true }).catch(function(){});
				}).catch(function(){});
			}).catch(function(){});
		} catch (e) {}
	}
	tryToy(0);
	setTimeout(report, 100);
})();
"""

const _JS_SHARE := """
(function(){
	if (window.__dpShareInit) return; window.__dpShareInit = true;
	var caps = { toyShare: false, album: false, qr: false, native: !!navigator.share };
	function report(){ if (window.__dpCaps) window.__dpCaps(JSON.stringify(caps)); }
	window.__dpProbeCaps = function(){
		var toy = window.toy;
		if (!toy || !toy.isSupport) { report(); return; }
		var ask = function(a){ try { return toy.isSupport(a).catch(function(){ return false; }); } catch (e) { return Promise.resolve(false); } };
		Promise.all([ask('share'), ask('saveImageToAlbum'), ask('getQrCode')]).then(function(r){
			caps.toyShare = !!r[0]; caps.album = !!r[1]; caps.qr = !!r[2]; report();
		});
	};
	report();
	function done(kind, ok, detail){ if (window.__dpShareDone) window.__dpShareDone(kind, !!ok, String(detail || '')); }
	function pngBytes(){
		var bin = atob(window.__dpPng || ''); var arr = new Uint8Array(bin.length);
		for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
		return arr;
	}
	window.__dpTakeTank = function(){
		try {
			var u = new URL(window.location.href);
			var c = u.searchParams.get('tank') || '';
			if (!c && u.hash) { var m = /[#&]tank=([A-Za-z0-9_-]+)/.exec(u.hash); if (m) c = m[1]; }
			if (c) { u.searchParams.delete('tank'); u.hash = u.hash.replace(/[#&]?tank=[A-Za-z0-9_-]+/, ''); history.replaceState(null, '', u.pathname + u.search + u.hash); }
			return c;
		} catch (e) { return ''; }
	};
	window.__dpPageUrl = function(code){
		try { var u = new URL(window.location.href); u.hash = ''; u.search = '?tank=' + code; return u.toString(); } catch (e) { return ''; }
	};
	function nativeShare(url, title, text){
		if (!navigator.share) return false;
		var data = { title: title, text: text };
		if (url) data.url = url;
		try {
			var file = new File([pngBytes()], 'desk-pond-tank.png', { type: 'image/png' });
			if (navigator.canShare && navigator.canShare({ files: [file] })) data.files = [file];
		} catch (e) {}
		navigator.share(data).then(function(){ done('share', true, 'native'); })
			.catch(function(e){ done('share', false, (e && e.name) || 'error'); });
		return true;
	}
	window.__dpShare = function(path, url, title, text){
		var toy = window.toy;
		if (caps.toyShare && toy && toy.share) {
			toy.share({ path: path }).then(function(){ done('share', true, 'toy'); })
				.catch(function(e){ if (!nativeShare(url, title, text)) done('share', false, 'toy'); });
			return;
		}
		if (!nativeShare(url, title, text)) done('share', false, 'unsupported');
	};
	function download(filename){
		try {
			var blob = new Blob([pngBytes()], { type: 'image/png' });
			var a = document.createElement('a');
			a.href = URL.createObjectURL(blob); a.download = filename;
			document.body.appendChild(a); a.click();
			setTimeout(function(){ URL.revokeObjectURL(a.href); a.remove(); }, 2000);
			done('save', true, 'download');
		} catch (e) { done('save', false, 'download'); }
	}
	window.__dpSaveImage = function(filename){
		var toy = window.toy;
		if (caps.album && toy && toy.saveImageToAlbum) {
			toy.saveImageToAlbum({ base64Data: 'data:image/png;base64,' + (window.__dpPng || ''), hintMsg: '生态缸卡片已保存到相册' })
				.then(function(){ done('save', true, 'album'); })
				.catch(function(){ download(filename); });
			return;
		}
		download(filename);
	};
	window.__dpCopy = function(text){
		function fallback(){
			try {
				var ta = document.createElement('textarea');
				ta.value = text; ta.style.cssText = 'position:fixed;left:-9999px;top:0';
				document.body.appendChild(ta); ta.select();
				var ok = document.execCommand('copy'); ta.remove(); done('copy', ok, 'exec');
			} catch (e) { done('copy', false, 'exec'); }
		}
		if (navigator.clipboard && navigator.clipboard.writeText)
			navigator.clipboard.writeText(text).then(function(){ done('copy', true, 'clipboard'); }).catch(fallback);
		else fallback();
	};
	window.__dpQr = function(path, size){
		var toy = window.toy;
		if (!caps.qr || !toy || !toy.getQrCode) return;
		toy.getQrCode({ path: path, size: size }).then(function(r){
			var b = (r && r.base64) || ''; var i = b.indexOf(',');
			if (b.indexOf('data:') === 0 && i >= 0) b = b.slice(i + 1);
			if (b && window.__dpQrDone) window.__dpQrDone(b);
		}).catch(function(){});
	};
})();
"""
