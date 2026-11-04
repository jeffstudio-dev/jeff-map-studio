@tool
class_name MapGenerationJob
extends RefCounted
## Only this mutex-protected object is shared between the worker and main thread.
var _mutex := Mutex.new()
var _cancelled: bool = false
var _progress: float = 0.0
var _message: String = "准备生成"
var error: String = ""

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock()
	var result := _cancelled
	_mutex.unlock()
	return result

func report(value: float, message: String) -> void:
	_mutex.lock()
	_progress = value
	_message = message
	_mutex.unlock()

func status() -> Array:
	_mutex.lock()
	var result := [_progress, _message]
	_mutex.unlock()
	return result
