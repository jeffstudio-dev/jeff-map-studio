@tool
class_name MapWork
extends RefCounted
## Runs a callable on a worker thread or, on single-threaded browser builds, on the
## main thread one frame later, behind the same is_alive() / wait_to_finish() calls.

var _thread: Thread
var _work: Callable
var _result: Variant
var _frames := 0

static func threads_available() -> bool:
	return not OS.has_feature("web") or OS.has_feature("threads")

func start(work: Callable) -> Error:
	if threads_available():
		_thread = Thread.new()
		return _thread.start(work)
	_work = work
	# Let the busy state draw once before the main thread blocks on the work.
	_frames = 1
	return OK

func is_alive() -> bool:
	if _thread != null:
		return _thread.is_alive()
	if _work.is_valid():
		if _frames > 0:
			_frames -= 1
			return true
		_result = _work.call()
		_work = Callable()
	return false

func wait_to_finish() -> Variant:
	if _thread != null:
		return _thread.wait_to_finish()
	if _work.is_valid():
		_result = _work.call()
		_work = Callable()
	return _result

## Only real threads need joining; pending main-thread work is simply dropped.
func is_started() -> bool:
	return _thread != null and _thread.is_started()
