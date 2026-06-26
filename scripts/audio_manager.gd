extends Node
# 全局音频管理（autoload 名 Audio）。
# 轻柔、克制：环境水声常驻低音量循环，事件音一声而过。可一键静音，状态由 main 持久化。

const A_AMBIENT := preload("res://assets/audio/ambient_water.wav")
const A_CHIME := preload("res://assets/audio/chime.wav")
const A_CAST := preload("res://assets/audio/cast.wav")
const A_CATCH := preload("res://assets/audio/catch.wav")
const A_TASK := preload("res://assets/audio/task_done.wav")

const AMBIENT_DB := -16.0
const SFX_DB := -7.0

var muted := false

var _ambient: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ambient = AudioStreamPlayer.new()
	if A_AMBIENT is AudioStreamWAV:
		var amb: AudioStreamWAV = A_AMBIENT
		amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
		amb.loop_begin = 0
		amb.loop_end = int(amb.get_length() * amb.mix_rate)
	_ambient.stream = A_AMBIENT
	_ambient.volume_db = AMBIENT_DB
	add_child(_ambient)
	for i in range(5):
		var p := AudioStreamPlayer.new()
		p.volume_db = SFX_DB
		add_child(p)
		_pool.append(p)

# main 启动时调用，传入存档里的静音设置。
func init_muted(is_muted: bool) -> void:
	muted = is_muted
	_refresh_ambient()

func set_muted(is_muted: bool) -> void:
	muted = is_muted
	_refresh_ambient()

func _refresh_ambient() -> void:
	if _ambient == null:
		return
	if muted:
		_ambient.stop()
	elif not _ambient.playing:
		_ambient.play()

func _play(stream: AudioStream, pitch_min := 1.0, pitch_max := 1.0) -> void:
	if muted or stream == null:
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = stream
	p.pitch_scale = randf_range(pitch_min, pitch_max)
	p.play()

func play_cast() -> void:
	_play(A_CAST, 0.97, 1.04)

func play_chime() -> void:
	_play(A_CHIME)

func play_catch() -> void:
	_play(A_CATCH, 0.96, 1.06)

func play_task_done() -> void:
	_play(A_TASK, 0.98, 1.05)
