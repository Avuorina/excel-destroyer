extends Control

var money = 0

func _ready():
	$Label.text = str(money)

func _on_button_pressed():
	money += 1
	$Label.text = str(money)
