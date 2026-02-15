extends RefCounted
class_name TRCliArgs

var arg_dict: Dictionary
func _init():
	arg_dict = {}
	var args = OS.get_cmdline_user_args()
	var idx = 0
	while idx < args.size():
		var arg = args[idx].strip_edges()
		var arg_parts = arg.split("=", true, 1)
		if arg_parts.size() == 2:
			arg_dict[arg_parts[0]] = arg_parts[1]
		elif idx + 1 < args.size():
			idx += 1
			arg_dict[arg] = args[idx]
		idx += 1

func has_arg(flags: Array):
	return get_arg(flags) != null

func get_arg(flags: Array, default = null):
	for flag in flags:
		if arg_dict.has(flag):
			return arg_dict[flag]
	return default

func get_bool(flags: Array, default: bool):
	var val = get_arg(flags)
	if not val: return default
	var is_true = ["t", "true", "y", "yes", "1"].has(val.to_lower())
	var is_false = ["f", "false", "n", "no", "0"].has(val.to_lower())
	if is_true: return true
	if is_false: return false
	return default
