extends RefCounted
## Placeholder for rewarded ads (e.g. "watch an ad to keep driving" on the game over card).
## Nothing is shown today: is_ready() is false, so the game never offers an ad.
## To add ads later: install an AdMob plugin (needs the Gradle Android build), load a rewarded ad
## here, return true from is_ready() once it's loaded, and call `done.call(true)` after the reward.

func is_ready() -> bool:
	return false

func show_rewarded(done: Callable) -> void:
	done.call(false)
