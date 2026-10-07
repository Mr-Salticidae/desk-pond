extends RefCounted
class_name UpdateCheck

# 新版本提示（桌面版）。设计见 docs/设计_v0.7_小窗与昼夜.md 第五节。
# 数据源是自有站的一个小文件（香港服务器，国内直连；不直接查 GitHub API，国内访问不稳）：
#   {"version": "0.7.0", "url": "下载页", "notes": "一句话更新说明"}
# 自有站部署时从 GitHub Release 拉 exe 的那一步顺手写出这个文件。
# 请求不带任何玩家数据；不自动下载、不自动安装，只在「?」上亮个小点。

const URL := "https://tiaozhuxiansheng.com/desk-pond/latest.json"
const DEFAULT_PAGE := "https://tiaozhuxiansheng.com/desk-pond/"

static func current_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

# a 是否比 b 新。按 x.y.z 逐段比数字（0.10.0 > 0.9.9）；可带 v 前缀；
# 同一版本号下，带 -beta 之类后缀的预发布版比正式版旧。
static func is_newer(a: String, b: String) -> bool:
	return compare(a, b) > 0

static func compare(a: String, b: String) -> int:
	var pa := _parse(a)
	var pb := _parse(b)
	if pa.is_empty() or pb.is_empty():
		return 0
	var core_a: Array = pa[0]
	var core_b: Array = pb[0]
	for i in range(maxi(core_a.size(), core_b.size())):
		var x: int = core_a[i] if i < core_a.size() else 0
		var y: int = core_b[i] if i < core_b.size() else 0
		if x != y:
			return 1 if x > y else -1
	var pre_a: String = pa[1]
	var pre_b: String = pb[1]
	if pre_a == pre_b:
		return 0
	if pre_a == "":
		return 1
	if pre_b == "":
		return -1
	return 1 if pre_a > pre_b else -1

# "v0.7.1-beta" -> [[0, 7, 1], "beta"]；格式不对返回 []
static func _parse(v: String) -> Array:
	v = v.strip_edges().trim_prefix("v").trim_prefix("V")
	if v == "":
		return []
	var pre := ""
	var dash := v.find("-")
	if dash >= 0:
		pre = v.substr(dash + 1)
		v = v.substr(0, dash)
	var core: Array = []
	for part in v.split("."):
		if not part.is_valid_int():
			return []
		core.append(int(part))
	return [core, pre]

# 解析 latest.json：返回 {version, url, notes}；内容不对返回 {}
static func parse_latest(body: String) -> Dictionary:
	var data: Variant = JSON.parse_string(body)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var version := String(data.get("version", "")).strip_edges()
	if _parse(version).is_empty():
		return {}
	var url := String(data.get("url", "")).strip_edges()
	# 只接受 https 链接，防止被塞进奇怪的协议
	if not url.begins_with("https://"):
		url = DEFAULT_PAGE
	return {
		"version": version.trim_prefix("v"),
		"url": url,
		"notes": String(data.get("notes", "")).strip_edges().left(60),
	}
