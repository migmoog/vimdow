extends Node
class_name TRSampleScene1


func _ready():
	var args = TRCliArgs.new()
	var user_arg = args.get_arg(["--userdefinedargument"])
	if user_arg:
		print("Used defined arg is: " + user_arg)
	
	print("Hello World 1")
	%Button.pressed.connect(func():
		print("button pressed 1")
		breakpoint
	)
