extends Node
# 昼夜（autoload 名 DayCycle）。设计见 docs/设计_v0.7_小窗与昼夜.md 第四节。
# 按本地时间在关键帧之间线性插值，四段（清晨 / 白天 / 黄昏 / 夜晚）之间约 1 小时平滑过渡、不跳变。
# 只改画面、不锁内容：没有「只有夜里才来」的访客，也没有「只有早上才钓得到」的鱼。
# 各房间在 _draw() 里读这里的值：天色 sky、整体压暗的遮罩 overlay、夜色强度 night（0 = 白天，1 = 深夜）。
# 调试：godot --path . -- --hour=21.5 固定在晚上九点半，截图和测试不用等到晚上。

signal changed

# 白天的天色 = 现有配色（池塘 / 森林原来的 SKY），白天时一切和 v0.6 一模一样
const DAY_SKY := Color(0.78, 0.89, 0.86)
const NIGHT_SKY := Color(0.10, 0.14, 0.27)
const NIGHT_OVERLAY := Color(0.05, 0.08, 0.22, 0.46)
const CLEAR := Color(1, 1, 1, 0)

# [小时, 天色, 遮罩, 夜色强度]；首尾都是深夜，0 点前后连续
var KEYS := [
	[0.0, NIGHT_SKY, NIGHT_OVERLAY, 1.0],
	[5.0, NIGHT_SKY, NIGHT_OVERLAY, 1.0],
	[6.0, Color(0.93, 0.74, 0.70), Color(0.95, 0.52, 0.42, 0.14), 0.3],   # 清晨：淡粉橙
	[7.5, Color(0.86, 0.88, 0.82), Color(1.0, 0.80, 0.60, 0.05), 0.0],
	[8.0, DAY_SKY, CLEAR, 0.0],                                            # 白天：原配色
	[16.5, DAY_SKY, CLEAR, 0.0],
	[17.5, Color(0.96, 0.70, 0.50), Color(0.95, 0.45, 0.25, 0.15), 0.1],   # 黄昏：橙红
	[18.5, Color(0.52, 0.40, 0.55), Color(0.35, 0.20, 0.42, 0.30), 0.6],
	[19.5, NIGHT_SKY, NIGHT_OVERLAY, 1.0],                                 # 夜晚
	[24.0, NIGHT_SKY, NIGHT_OVERLAY, 1.0],
]

var mode := "auto"            # "auto" 跟随本地时间 / "day" 一直白天（存档 settings.day_cycle）
var fixed_hour := -1.0        # >= 0 时固定在这个钟点（--hour= 调试参数、测试用）

var sky := DAY_SKY
var overlay := CLEAR
var night := 0.0
var phase := "day"

var _timer: Timer

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			fixed_hour = clampf(float(arg.trim_prefix("--hour=")), 0.0, 23.99)
	_timer = Timer.new()
	_timer.wait_time = 30.0
	_timer.timeout.connect(refresh)
	add_child(_timer)
	_timer.start()
	refresh()

func set_mode(new_mode: String) -> void:
	mode = new_mode if new_mode in ["auto", "day"] else "auto"
	refresh()

func current_hour() -> float:
	if fixed_hour >= 0.0:
		return fixed_hour
	var t := Time.get_time_dict_from_system()
	return float(t.hour) + float(t.minute) / 60.0 + float(t.second) / 3600.0

# 重新取一次时间；颜色有可见变化时才发 changed（静态的森林靠它重绘）
func refresh() -> void:
	var s := sample(current_hour() if mode == "auto" else 12.0)
	var moved: bool = absf(float(s["night"]) - night) > 0.002 or not (s["sky"] as Color).is_equal_approx(sky) or not (s["overlay"] as Color).is_equal_approx(overlay)
	sky = s["sky"]
	overlay = s["overlay"]
	night = s["night"]
	phase = s["phase"]
	if moved:
		changed.emit()

# 某个钟点的配色（纯函数，测试直接调）
func sample(hour: float) -> Dictionary:
	hour = fposmod(hour, 24.0)
	var i := 0
	while i < KEYS.size() - 2 and hour >= float(KEYS[i + 1][0]):
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var span := float(b[0]) - float(a[0])
	var t := 0.0 if span <= 0.0 else clampf((hour - float(a[0])) / span, 0.0, 1.0)
	return {
		"sky": (a[1] as Color).lerp(b[1], t),
		"overlay": (a[2] as Color).lerp(b[2], t),
		"night": lerpf(float(a[3]), float(b[3]), t),
		"phase": phase_of(hour),
	}

static func phase_of(hour: float) -> String:
	hour = fposmod(hour, 24.0)
	if hour >= 5.0 and hour < 8.0:
		return "dawn"
	if hour >= 8.0 and hour < 17.0:
		return "day"
	if hour >= 17.0 and hour < 19.0:
		return "dusk"
	return "night"

# 夜里文字要换成浅色，不然深色字压在夜空上看不清
static func ink_for(night_amount: float, day_ink: Color) -> Color:
	return day_ink.lerp(Color(0.86, 0.90, 0.94), clampf((night_amount - 0.35) / 0.4, 0.0, 1.0))
