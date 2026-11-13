extends Control
## 共用卡牌组件 / Shared Card Component
## 可被任何需要卡牌的场景实例化使用
## 鼠标检测和位移动画由 card_set 统一管理
## Mouse detection and movement are managed by CardSet

# 卡牌数据 / Card data
var card_suit: String = ""  # spade, heart, club, diamond, joker
var card_rank: int = 1  # 1-13, 14=小王, 15=大王
var card_value: int = 0  # 用于排序的值 / Value for sorting

# 状态 / State
var is_hovered: bool = false
var original_position: Vector2 = Vector2.ZERO

# 节点引用 / Node references
@onready var card_sprite: TextureRect = $CardSprite
@onready var hint_glow: Panel = get_node_or_null("HintGlow") as Panel
var _hint_tween: Tween

# 信号 / Signals
signal card_hovered(card: Control)   # 悬停 / Hover
signal card_exited(card: Control)    # 离开 / Exit
signal card_clicked(card: Control)   # 点击 / Click

func _ready():
	original_position = position
	# 鼠标事件由 card_set 统一管理，卡牌自身不拦截
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 设置卡牌数据 / Set card data
func set_card_data(suit: String, rank: int, value: int = 0):
	card_suit = suit
	card_rank = rank
	card_value = value if value > 0 else _calculate_value()

## 计算牌值（用于排序）/ Calculate card value for sorting
func _calculate_value() -> int:
	var suit_value = {"spade": 0, "heart": 1, "club": 2, "diamond": 3, "joker": 4}
	return card_rank * 10 + suit_value.get(card_suit, 0)

## 获取牌面名称 / Get card display name
func get_card_name() -> String:
	var suit_names = {"spade": "黑桃", "heart": "红桃", "club": "梅花", "diamond": "方块", "joker": "王"}
	return suit_names.get(card_suit, "?") + _rank_to_string()

func _rank_to_string() -> String:
	match card_rank:
		1: return "A"
		11: return "J"
		12: return "Q"
		13: return "K"
		14: return "小"
		15: return "大"
		_: return str(card_rank)

## 设置悬停状态（由 card_set 调用）/ Set hover state (called by CardSet)
func set_hovered(value: bool):
	if is_hovered == value:
		return
	is_hovered = value
	if is_hovered:
		card_hovered.emit(self)
	else:
		card_exited.emit(self)

## 设置原始位置（由 card_set 在排列时调用）/ Set original position (called during arrange)
func set_original_position(pos: Vector2):
	original_position = pos

## 获取原始位置 / Get original position
func get_original_position() -> Vector2:
	return original_position

## 获取卡牌数据 / Get card data as Dictionary
func get_card_data() -> Dictionary:
	return {"suit": card_suit, "rank": card_rank, "value": card_value}

## 设置卡牌图片 / Set card texture
func set_card_texture(texture: Texture2D):
	if card_sprite:
		card_sprite.texture = texture

## 获取卡牌图片 / Get card texture
func get_card_texture() -> Texture2D:
	if card_sprite:
		return card_sprite.texture
	return null


func set_hint_highlight(enabled: bool) -> void:
	if hint_glow == null:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	hint_glow.visible = enabled
	if not enabled:
		hint_glow.modulate.a = 1.0
		return
	hint_glow.modulate.a = 0.55
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(hint_glow, "modulate:a", 1.0, 0.48)
	_hint_tween.tween_property(hint_glow, "modulate:a", 0.45, 0.48)
