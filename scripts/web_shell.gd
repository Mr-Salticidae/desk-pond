extends Node
# Web 外壳适配（autoload 名 WebShell）：让手机版吃满全面屏。
# - B站 Toy App 内：通过 Toy JS SDK（导出预设 head_include 引入）请求「沉浸 + 竖屏」容器，
#   并订阅 onContainerChange 拿到状态栏 / 导航条占掉的 safeArea。
# - 其它浏览器：读 CSS env(safe-area-inset-*)（需要 viewport-fit=cover，同样由 head_include 补上）。
# 两路取较大值，换算成 Godot 设计坐标后通过 safe_area_changed 通知 main 让出刘海 / 手势条。
# 桌面端调试：godot --path . -- --web-layout --safe-area=44,0,34,0 可模拟（上,右,下,左，设计像素）。

signal safe_area_changed(insets: Dictionary)

var insets := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}
var immersive := false
var _js_cb: JavaScriptObject
var _css := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0, "vw": 0.0}

func _ready() -> void:
	if OS.has_feature("web"):
		_js_cb = JavaScriptBridge.create_callback(_on_js_safe)
		var win := JavaScriptBridge.get_interface("window")
		win.__dpSafe = _js_cb
		JavaScriptBridge.eval(_JS_SETUP, true)
		get_tree().root.size_changed.connect(_recompute)
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--safe-area="):
				var parts := arg.trim_prefix("--safe-area=").split(",")
				if parts.size() == 4:
					insets = {"top": float(parts[0]), "right": float(parts[1]), "bottom": float(parts[2]), "left": float(parts[3])}

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
		if (!toy || !toy.isSupport) { if (n < 20) setTimeout(function(){ tryToy(n + 1); }, 250); return; }
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
