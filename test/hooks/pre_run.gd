extends GutHookScript
## Runs before every test: no test may write to the real room list on GitHub.


func run() -> void:
	RoomBoard.use_token_file = false
